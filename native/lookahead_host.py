#!/usr/bin/env python3
"""Native messaging host for the AirPlay Handoff extension.

Firefox speaks a length-prefixed JSON protocol on stdin/stdout.
Message: {"url": "...", "mode": "safari" | "player"}
"""
import json, os, struct, subprocess, sys

def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return None
    n = struct.unpack("<I", raw)[0]
    return json.loads(sys.stdin.buffer.read(n).decode("utf-8"))

def send_message(obj):
    data = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()

def main():
    msg = read_message()
    if not msg:
        return
    url = msg.get("url", "")
    if not url.startswith(("http://", "https://")):
        send_message({"ok": False, "error": "bad url"})
        return
    mode = msg.get("mode", "safari")
    try:
        if mode == "player":
            player = os.path.expanduser("~/.local/bin/lookahead-play")
            subprocess.Popen([player, url],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.Popen(["/usr/bin/open", "-a", "Safari", url],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        send_message({"ok": True, "mode": mode})
    except Exception as e:
        send_message({"ok": False, "error": str(e)})

if __name__ == "__main__":
    main()
