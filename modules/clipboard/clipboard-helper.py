#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from io import BytesIO
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "caelestia" / "cliphist"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

IMG_RE = re.compile(
    r"^(\d+)\s+\[\[\s*binary data\s+([0-9.]+)\s*(KiB|MiB)\s+(png|jpg|jpeg|webp)\s*([0-9x]+)?\s*\]\]"
)


def cmd_list(limit: int = 150):
    try:
        raw = subprocess.check_output(["cliphist", "list"], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        print("[]")
        return

    items = []
    for line in raw.splitlines()[:limit]:
        if not line.strip():
            continue
        m = IMG_RE.match(line)
        if m:
            cid = m.group(1)
            size = f"{m.group(2)} {m.group(3)}"
            fmt = m.group(4).upper()
            dim = m.group(5) or ""
            dim_str = f" ({dim})" if dim else ""
            items.append({
                "id": cid,
                "isImage": True,
                "format": fmt,
                "dim": dim,
                "size": size,
                "preview": f"{fmt} Image • {size}{dim_str}",
                "raw": line,
            })
        else:
            parts = line.split("\t", 1)
            cid = parts[0]
            txt = parts[1] if len(parts) > 1 else ""
            clean_preview = re.sub(r"\s+", " ", txt).strip()
            items.append({
                "id": cid,
                "isImage": False,
                "format": "TEXT",
                "dim": "",
                "size": f"{len(txt)} chars",
                "preview": clean_preview,
                "raw": line,
            })

    print(json.dumps(items))


def cmd_decode(cid: str):
    target = CACHE_DIR / f"{cid}.png"
    if not target.exists():
        try:
            raw_bytes = subprocess.check_output(["cliphist", "decode", cid], stderr=subprocess.DEVNULL)
            target.write_bytes(raw_bytes)
        except Exception as e:
            sys.stderr.write(f"Decode error: {e}\n")
            print("")
            return
    print(str(target))


def cmd_get_text(cid: str):
    try:
        raw_bytes = subprocess.check_output(["cliphist", "decode", cid], stderr=subprocess.DEVNULL)
        print(raw_bytes.decode("utf-8", errors="replace"))
    except Exception:
        print("")


def cmd_copy(cid: str):
    try:
        raw_bytes = subprocess.check_output(["cliphist", "decode", cid], stderr=subprocess.DEVNULL)
        subprocess.run(["wl-copy"], input=raw_bytes, check=True)
        print("ok")
    except Exception as e:
        sys.stderr.write(f"Copy error: {e}\n")
        print("error")


def cmd_delete(cid: str):
    # Find full raw line by listing or matching id
    try:
        raw = subprocess.check_output(["cliphist", "list"], text=True, stderr=subprocess.DEVNULL)
        for line in raw.splitlines():
            if line.startswith(f"{cid}\t") or line.startswith(f"{cid} "):
                subprocess.run(["cliphist", "delete"], input=line.encode("utf-8"), check=True)
                break
        target = CACHE_DIR / f"{cid}.png"
        if target.exists():
            target.unlink(missing_ok=True)
        print("ok")
    except Exception as e:
        sys.stderr.write(f"Delete error: {e}\n")
        print("error")


def main():
    if len(sys.argv) < 2:
        cmd_list()
        return

    sub = sys.argv[1]
    if sub == "list":
        lim = int(sys.argv[2]) if len(sys.argv) > 2 else 150
        cmd_list(lim)
    elif sub == "decode" and len(sys.argv) > 2:
        cmd_decode(sys.argv[2])
    elif sub == "get-text" and len(sys.argv) > 2:
        cmd_get_text(sys.argv[2])
    elif sub == "copy" and len(sys.argv) > 2:
        cmd_copy(sys.argv[2])
    elif sub == "delete" and len(sys.argv) > 2:
        cmd_delete(sys.argv[2])
    else:
        cmd_list()


if __name__ == "__main__":
    main()
