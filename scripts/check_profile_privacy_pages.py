#!/usr/bin/env python3
"""Render the public Profile disclosure in both languages on a disposable CI server."""
from html.parser import HTMLParser
from pathlib import Path
import os
import shutil
import subprocess
import time
import urllib.request

root = Path(__file__).resolve().parents[1]
output = Path(os.environ["RUNNER_TEMP"]) / "profile-privacy-pages"
output.mkdir(exist_ok=True)
chrome = shutil.which("google-chrome") or shutil.which("chromium")
if not chrome:
    raise SystemExit("The cloud runner needs Chrome to render the legal pages")


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.headings = []
        self.links = []
        self.heading = False

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "h2":
            self.heading = True
        if tag == "a":
            self.links.append(values.get("href"))

    def handle_endtag(self, tag):
        if tag == "h2":
            self.heading = False

    def handle_data(self, data):
        if self.heading:
            self.headings.append(data)


with (output / "next.log").open("w") as log:
    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--hostname", "127.0.0.1", "--port", "4637"],
        cwd=root / "web", stdout=log, stderr=subprocess.STDOUT,
    )
    try:
        for attempt in range(120):
            if server.poll() is not None:
                raise RuntimeError("Next.js exited before the legal check")
            try:
                with urllib.request.urlopen("http://127.0.0.1:4637/privacy", timeout=5) as response:
                    if response.status == 200:
                        break
            except (OSError, TimeoutError):
                time.sleep(0.5)
        else:
            raise RuntimeError("Next.js did not start")
        for language, path, heading, support in [
            ("en", "/privacy", "Profiles, Friends, and optional sharing", "/support"),
            ("fr", "/fr/privacy", "Profils, amis et partage facultatif", "/fr/support"),
        ]:
            url = f"http://127.0.0.1:4637{path}#profiles"
            result = subprocess.run([
                chrome, "--headless", "--no-sandbox", "--disable-dev-shm-usage",
                f"--user-data-dir={output / language}", "--window-size=393,852",
                "--virtual-time-budget=1500", "--dump-dom", url,
            ], check=True, capture_output=True, text=True, timeout=45)
            page = Page()
            page.feed(result.stdout)
            if heading not in page.headings or support not in page.links:
                raise RuntimeError(f"Missing rendered disclosure or legal navigation in {language}")
            subprocess.run([
                chrome, "--headless", "--no-sandbox", "--disable-dev-shm-usage",
                f"--user-data-dir={output / language}", "--window-size=393,852",
                "--virtual-time-budget=1500", f"--screenshot={output / (language + '.png')}", url,
            ], check=True, capture_output=True, timeout=45)
            print(f"{language}: signed-out disclosure and support link rendered at 393x852")
    finally:
        server.terminate()
        server.wait(timeout=15)
