#!/usr/bin/env python3
"""Serve the glow-up design pages and save Keep / Hide choices to glowup-state.json.

    python3 docs/design/source/kit/glowup-serve.py

Then open http://localhost:8765/glowup-index.html (or the Wi-Fi address it prints, on the phone).
glowup-state.json holds everyone's choices and comments; agents read it to know what people like:
    {"choices": {page: {option: {person: "keep" | "hide"}}},
     "comments": {page: {option: [{"who", "text", "at"}]}},
     "albums": {album name: ["page/option", ...]}}
"""
import http.server
import json
import os
import re
import socket
import threading

KIT = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(KIT, "glowup-state.json")
PORT = 8765
lock = threading.Lock()


def load():
    try:
        with open(STATE) as f:
            raw = json.load(f)
    except FileNotFoundError:
        raw = {}
    if "choices" in raw or "comments" in raw or "albums" in raw:
        return {"choices": raw.get("choices", {}), "comments": raw.get("comments", {}), "albums": raw.get("albums", {})}
    # First version: {page: {option: "keep" | "hide"}}, all Marc's.
    return {"choices": {pg: {o: {"Marc": v} for o, v in opts.items()} for pg, opts in raw.items()}, "comments": {}, "albums": {}}


def apply(state, op):
    """Same rules as apply() in the pages' shared script."""
    page, option = op["page"], op["id"]
    if op["op"] == "choice":
        by_who = state["choices"].setdefault(page, {}).setdefault(option, {})
        if op["value"]:
            by_who[op["who"]] = op["value"]
        else:
            by_who.pop(op["who"], None)
        if not by_who:
            del state["choices"][page][option]
        if not state["choices"][page]:
            del state["choices"][page]
    elif op["op"] == "album":
        key, items = f"{page}/{option}", state["albums"].get(op["album"], [])
        items = items + [key] if op["value"] and key not in items else [k for k in items if op["value"] or k != key]
        if items:
            state["albums"][op["album"]] = items
        else:
            state["albums"].pop(op["album"], None)
    elif op["op"] == "comment":
        state["comments"].setdefault(page, {}).setdefault(option, []).append({"who": op["who"], "text": op["text"], "at": op["at"]})
    else:
        left = [c for c in state["comments"].get(page, {}).get(option, []) if not (c["at"] == op["at"] and c["who"] == op["who"])]
        if left:
            state["comments"][page][option] = left
        elif page in state["comments"]:
            state["comments"][page].pop(option, None)
            if not state["comments"][page]:
                del state["comments"][page]


def valid(op):
    slug = lambda v, n: isinstance(v, str) and re.fullmatch(rf"[a-z0-9-]{{1,{n}}}", v)
    name = lambda v: isinstance(v, str) and 0 < len(v.strip()) <= 24 and v == v.strip() and v.isprintable()
    if not (isinstance(op, dict) and slug(op.get("page"), 40) and slug(op.get("id"), 60) and name(op.get("who"))):
        return False
    if op.get("op") == "choice":
        return op.get("value") in ("keep", "hide", None)
    if op.get("op") == "comment":
        return isinstance(op.get("text"), str) and 0 < len(op["text"]) <= 2000 and isinstance(op.get("at"), str) and len(op["at"]) <= 40
    if op.get("op") == "album":
        a = op.get("album")
        return isinstance(a, str) and 0 < len(a) <= 30 and a == a.strip() and a.isprintable() and isinstance(op.get("value"), bool)
    return op.get("op") == "uncomment" and isinstance(op.get("at"), str)


def save(state):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=4, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, STATE)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=KIT, **kwargs)

    def end_headers(self):
        # Pages opened straight from disk (file://) talk to this server too.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_json(self, value, code=200):
        body = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/glowup-state":
            with lock:
                return self.send_json(load())
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/glowup-index.html")
            return self.end_headers()
        super().do_GET()

    def do_POST(self):
        if self.path != "/glowup-state":
            return self.send_error(404)
        try:
            op = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        except ValueError:
            op = None
        if not valid(op):
            return self.send_json({"error": "expected {op: choice|comment|uncomment, page, id, who, ...}"}, 400)
        with lock:
            state = load()
            apply(state, op)
            save(state)
        self.send_json(state)

    def log_message(self, fmt, *args):
        if self.command == "POST":
            print(f"saved: {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        lan = s.getsockname()[0]
        s.close()
    except OSError:
        lan = None
    print(f"Mac:   http://localhost:{PORT}/glowup-index.html")
    if lan:
        print(f"Phone (same Wi-Fi): http://{lan}:{PORT}/glowup-index.html")
    print(f"Choices save to {STATE}")
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
