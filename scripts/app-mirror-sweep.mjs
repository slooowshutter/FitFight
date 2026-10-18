// Opens every map link of a mirror page in headless Chrome, then taps every button on it. Each design option
// registered with variant(...) is swept too, on its own links. Reports exceptions, console errors,
// "Not mirrored yet" screens and unknown actions.
// Usage: node scripts/app-mirror-sweep.mjs [page.html] [--no-clicks]   (default: docs/design/source/kit/app.html)
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";

const page = resolve(process.argv.slice(2).find((a) => !a.startsWith("--")) || new URL("../docs/design/source/kit/app.html", import.meta.url).pathname);
const clicks = !process.argv.includes("--no-clicks");
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
    "--headless=new", "--disable-gpu", `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "sweep-"))}`,
    "--allow-file-access-from-files", "--window-size=1400,1000", "about:blank",
], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (targets.length) break; } catch {}
    await sleep(200);
}
const ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map();
const problems = [];
let current = "load";
ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); return; }
    if (msg.method === "Runtime.exceptionThrown") problems.push(`${current}: EXCEPTION ${msg.params.exceptionDetails.exception?.description?.split("\n").slice(0, 2).join(" | ") || msg.params.exceptionDetails.text}`);
    if (msg.method === "Runtime.consoleAPICalled" && msg.params.type === "error") problems.push(`${current}: console.error ${msg.params.args.map((a) => a.value ?? a.description).join(" ").slice(0, 200)}`);
    if (msg.method === "Log.entryAdded" && msg.params.entry.level === "error" && !/favicon/.test(msg.params.entry.text)) problems.push(`${current}: log ${msg.params.entry.text} ${msg.params.entry.url || ""}`.slice(0, 240));
};
const send = (method, params = {}) => new Promise((r) => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
const run = async (expression) => {
    const res = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (res.result?.exceptionDetails) throw new Error(res.result.exceptionDetails.exception?.description || res.result.exceptionDetails.text);
    return res.result?.result?.value;
};
await send("Runtime.enable");
await send("Log.enable");
await send("Page.enable");
await send("Page.navigate", { url: `file://${page}` });
await sleep(1500);

const links = await run(`LINKS.flatMap((g) => g.items.map(([title, hash, o = {}]) => ({ group: g.group, title, hash, o })))`);
// Every option after each feature's first (the default) is swept on that feature's links, or on every link.
const variantRuns = await run(`Object.entries(VARIANTS).flatMap(([key, f]) => f.options.slice(1).map((o) => ({ key, id: o.id, hashes: (f.links || []).map(([, hash]) => hash) })))`);
// Copy from the map's own links only, or each option would also copy the options before it.
const base = [...links];
for (const v of variantRuns) {
    const own = v.hashes.length ? base.filter((l) => v.hashes.includes(l.hash)) : base;
    const extra = v.hashes.filter((h) => !links.some((l) => l.hash === h)).map((hash) => ({ group: "Variant", title: hash, hash, o: {} }));
    for (const l of [...own, ...extra]) links.push({ ...l, title: `${l.title} [${v.key}: ${v.id}]`, variants: { [v.key]: v.id } });
}
console.log(`${links.length} links`);
const open = (link) => run(`(() => {
    const o = ${JSON.stringify(link.o)};
    clearTimeout(toast.timer); S.toast = null; S.menu = null;
    S.scenario = o.scenario || "populated"; S.data = makeData(S.scenario); S.ui = {};
    S.account = o.account || "signedIn"; S.admin = !!o.admin; S.environment = "staging"; S.theme = "night";
    S.variants = ${JSON.stringify(link.variants || {})};
    ACT.accountChanged(S.account);
    go(${JSON.stringify(link.hash)});
    return true;
})()`);
const check = () => run(`(() => {
    const text = document.getElementById("phone").innerText;
    const out = [];
    if (/Not mirrored yet/.test(text)) out.push("NOT MIRRORED: " + (text.match(/“([^”]+)”/)?.[1] || text.slice(0, 80).replace(/\\n/g, " ")));
    if (/failed to draw/.test(text)) out.push("FAILED TO DRAW: " + text.slice(0, 160).replace(/\\n/g, " "));
    return out;
})()`);
let clicked = 0;
for (const link of links) {
    current = `${link.group} › ${link.title} (${link.hash})`;
    try { await open(link); } catch (e) { problems.push(`${current}: open threw ${e.message.split("\n")[0]}`); continue; }
    await sleep(60);
    for (const p of await check()) problems.push(`${current}: ${p}`);
    if (!clicks) continue;
    const count = await run(`document.querySelectorAll("#phone [data-on]:not([disabled])").length`);
    for (let i = 0; i < count; i++) {
        await open(link);
        await sleep(20);
        const spec = await run(`(() => { const el = document.querySelectorAll("#phone [data-on]:not([disabled])")[${i}]; if (!el) return null; const s = el.dataset.on; el.click(); return s; })()`);
        if (spec == null) continue;
        clicked++;
        current = `${link.group} › ${link.title} › tap "${spec}"`;
        await sleep(30);
        for (const p of await check()) problems.push(`${current}: ${p}`);
        const unknown = await run(`S.toast && S.toast.title === "Not mirrored yet" ? S.toast.message : null`);
        if (unknown) problems.push(`${current}: ${unknown}`);
    }
}
console.log(`${clicked} taps`);
const unique = [...new Set(problems)];
console.log(unique.length ? unique.join("\n") : "No problems");
ws.close();
chrome.kill();
process.exit(0);
