#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess

NOTIF_DIR = os.path.realpath(os.path.expanduser("~/.local/state/omarchy/notifications"))
HIST_DIR = os.path.join(NOTIF_DIR, "history")

def is_safe_file(path):
    if not path or not isinstance(path, str):
        return False
    try:
        real = os.path.realpath(path)
        if os.path.islink(path):
            return False
        parent = os.path.dirname(real)
        if parent not in (NOTIF_DIR, HIST_DIR):
            return False
        base = os.path.basename(real)
        return bool(re.match(r"^[0-9]+-[0-9]+\.json$", base))
    except Exception:
        return False

def sanitize(s, max_len=1000):
    if not isinstance(s, str):
        return ""
    # Strip ANSI escape sequences
    s = re.sub(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", "", s)
    # Strip control chars except \n and \t
    s = re.sub(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "", s)
    # Strip Unicode bidi overrides
    s = re.sub(r"[\u200E\u200F\u202A-\u202E\u2066-\u2069]", "", s)
    return s[:max_len]

def list_notifications():
    items = []
    seen = set()
    for d in [NOTIF_DIR, HIST_DIR]:
        if not os.path.isdir(d):
            continue
        try:
            for entry in os.scandir(d):
                if entry.is_file() and not entry.is_symlink() and re.match(r"^[0-9]+-[0-9]+\.json$", entry.name):
                    try:
                        with open(entry.path, "r", encoding="utf-8", errors="replace") as f:
                            data = json.load(f)
                        nid = f"{data.get('timestamp', 0)}:{data.get('id', data.get('originalId', 0))}"
                        if nid not in seen:
                            seen.add(nid)
                            items.append({
                                "id": data.get("id", data.get("originalId", 0)),
                                "app": sanitize(data.get("app", "Notification"), 64),
                                "summary": sanitize(data.get("summary", ""), 256),
                                "body": sanitize(data.get("body", ""), 1024),
                                "glyph": sanitize(data.get("glyph", ""), 8),
                                "urgency": int(data.get("urgency", 1)),
                                "timestamp": int(data.get("timestamp", 0)),
                                "file": entry.path
                            })
                    except Exception:
                        pass
        except Exception:
            pass

    items.sort(key=lambda x: x["timestamp"], reverse=True)
    print(json.dumps(items[:50]))

def dismiss_file(file_path):
    if is_safe_file(file_path) and os.path.isfile(file_path):
        try:
            os.unlink(file_path)
            print("ok")
            return
        except Exception as e:
            print(f"error: {e}", file=sys.stderr)
    print("invalid")

def clear_all():
    # Remove notification JSON files safely
    for d in [NOTIF_DIR, HIST_DIR]:
        if os.path.isdir(d):
            try:
                for entry in os.scandir(d):
                    if entry.is_file() and not entry.is_symlink() and re.match(r"^[0-9]+-[0-9]+\.json$", entry.name):
                        try:
                            os.unlink(entry.path)
                        except Exception:
                            pass
            except Exception:
                pass
    # Request Omarchy notification service to clear in-memory state
    try:
        subprocess.run(["omarchy-shell", "notifications", "clear"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        subprocess.run(["omarchy-shell", "notifications", "dismissAll"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    except Exception:
        pass
    print("ok")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        list_notifications()
    elif cmd == "dismiss" and len(sys.argv) > 2:
        dismiss_file(sys.argv[2])
    elif cmd == "clear":
        clear_all()
    else:
        print("Usage: helper.py [list|dismiss <file>|clear]", file=sys.stderr)
        sys.exit(1)
