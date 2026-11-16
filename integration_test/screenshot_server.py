#!/usr/bin/env python3
"""Host-side helper for integration_test/app_flow_test.dart.

The test running on the emulator asks for a screenshot with
GET http://10.0.2.2:<port>/shot?name=<nn_name_theme>; this server captures
the device screen with `adb exec-out screencap -p` and writes
<out_dir>/<name>.png. It only listens on 127.0.0.1 (the emulator reaches it
as 10.0.2.2).

    python3 integration_test/screenshot_server.py <out_dir> [port] [serial]
"""

import os
import re
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "screens"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
SERIAL = sys.argv[3] if len(sys.argv) > 3 else "emulator-5554"
ADB = os.path.expanduser(os.environ.get("ADB", "~/Android/Sdk/platform-tools/adb"))
NAME = re.compile(r"^[0-9a-z_]{1,80}$")


def dismiss_system_anr():
    """Closes an emulator "System UI isn't responding" dialog (not the app's)
    so it does not cover the screenshot."""
    windows = subprocess.run(
        [ADB, "-s", SERIAL, "shell", "dumpsys", "window", "windows"],
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout
    if "Application Not Responding" in windows:
        sys.stderr.write("shot: dismissing a system ANR dialog\n")
        subprocess.run(
            [ADB, "-s", SERIAL, "shell", "am", "broadcast", "-a",
             "android.intent.action.CLOSE_SYSTEM_DIALOGS"],
            capture_output=True,
            timeout=30,
        )
        time.sleep(0.5)


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, text):
        body = text.encode()
        self.send_response(status)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/ping":
            return self._reply(200, "pong")
        if url.path != "/shot":
            return self._reply(404, "not found")
        name = (parse_qs(url.query).get("name") or [""])[0]
        if not NAME.match(name):
            return self._reply(400, "bad name")
        dismiss_system_anr()
        png = subprocess.run(
            [ADB, "-s", SERIAL, "exec-out", "screencap", "-p"],
            capture_output=True,
            timeout=30,
        ).stdout
        if not png.startswith(b"\x89PNG"):
            return self._reply(500, "screencap failed")
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, name + ".png"), "wb") as f:
            f.write(png)
        return self._reply(200, "ok")

    def log_message(self, fmt, *args):
        sys.stderr.write("shot: " + (fmt % args) + "\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
