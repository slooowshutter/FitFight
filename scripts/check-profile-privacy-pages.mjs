/** Disposable cloud browser check. Chrome and Node are provided by GitHub's runner. */
import { spawn } from "node:child_process";
import { mkdir, open, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const output = join(process.env.RUNNER_TEMP, "profile-privacy-pages");
await mkdir(output, { recursive: true });
const log = await open(join(output, "next.log"), "w");
const server = spawn("npm", ["run", "dev", "--", "--hostname", "127.0.0.1", "--port", "4637"], {
    cwd: new URL("../web", import.meta.url), stdio: ["ignore", log.fd, log.fd],
});
let chrome;
let socket;
try {
    for (let attempt = 0; attempt < 120; attempt++) {
        if (server.exitCode !== null) throw new Error("Next.js exited before the legal check");
        try {
            if ((await fetch("http://127.0.0.1:4637/privacy")).ok) break;
        } catch {}
        if (attempt === 119) throw new Error("Next.js did not start");
        await delay(500);
    }
    chrome = spawn("google-chrome", ["--headless", "--no-sandbox", "--disable-dev-shm-usage",
        "--remote-debugging-port=9222", `--user-data-dir=${join(output, "chrome")}`, "about:blank"], { stdio: "ignore" });
    let target;
    for (let attempt = 0; attempt < 60; attempt++) {
        try {
            const targets = await (await fetch("http://127.0.0.1:9222/json")).json();
            target = targets.find((item) => item.type === "page");
            if (target) break;
        } catch {}
        await delay(250);
    }
    if (!target) throw new Error("Chrome did not expose its page");
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
        socket.addEventListener("open", resolve, { once: true });
        socket.addEventListener("error", reject, { once: true });
    });
    let sequence = 0;
    const pending = new Map();
    socket.addEventListener("message", (event) => {
        const response = JSON.parse(event.data);
        const request = pending.get(response.id);
        if (!request) return;
        pending.delete(response.id);
        clearTimeout(request.timeout);
        if (response.error) request.reject(new Error(JSON.stringify(response.error)));
        else request.resolve(response.result);
    });
    function command(method, params = {}) {
        return new Promise((resolve, reject) => {
            const id = ++sequence;
            const timeout = setTimeout(() => reject(new Error(`${method} timed out`)), 30000);
            pending.set(id, { resolve, reject, timeout });
            socket.send(JSON.stringify({ id, method, params }));
        });
    }
    await command("Page.enable");
    await command("Emulation.setDeviceMetricsOverride", { width: 393, height: 852, deviceScaleFactor: 1, mobile: true });
    for (const [language, path, heading, support] of [
        ["en", "/privacy", "Profiles, Friends, and optional sharing", "/support"],
        ["fr", "/fr/privacy", "Profils, amis et partage facultatif", "/fr/support"],
    ]) {
        await command("Page.navigate", { url: `http://127.0.0.1:4637${path}` });
        let ready = false;
        for (let attempt = 0; attempt < 120; attempt++) {
            const result = await command("Runtime.evaluate", {
                expression: `location.pathname === ${JSON.stringify(path)} && document.querySelector('#profiles h2')?.textContent === ${JSON.stringify(heading)} && !!document.querySelector('a[href="${support}"]')`,
                returnByValue: true,
            });
            if (result.result.value === true) { ready = true; break; }
            await delay(250);
        }
        if (!ready) throw new Error(`Missing rendered disclosure in ${language}`);
        await command("Runtime.evaluate", {
            expression: "document.fonts.ready.then(() => { document.documentElement.style.scrollBehavior = 'auto'; document.querySelector('#profiles').scrollIntoView({ behavior: 'instant' }); })",
            awaitPromise: true,
        });
        await delay(500);
        const layout = await command("Runtime.evaluate", {
            expression: "document.documentElement.scrollWidth <= window.innerWidth && document.querySelector('#profiles').getBoundingClientRect().top >= -1",
            returnByValue: true,
        });
        if (!layout.result.value) throw new Error(`Overflow or hidden section in ${language}`);
        const screenshot = await command("Page.captureScreenshot", { format: "png" });
        await writeFile(join(output, `${language}.png`), Buffer.from(screenshot.data, "base64"));
        console.log(`${language}: signed-out disclosure rendered at 393x852 without horizontal overflow`);
    }
} finally {
    socket?.close();
    chrome?.kill();
    server.kill();
    await log.close();
}
