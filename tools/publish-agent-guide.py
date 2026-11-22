#!/usr/bin/env python3
"""Publish the standalone Agent guide; server settings stay outside Git."""
import argparse
import hashlib
from pathlib import Path
import re
import shlex
import subprocess
import time
import urllib.request

DEFAULT_URL = "https://fw.koolcenter.com/binary/kai/kai-skills/agent-install.md"
SOURCE = Path(__file__).resolve().parents[1] / "docs/distribution/agent-install.md"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "publish", "verify"])
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--host", help="SSH destination or configured alias")
    parser.add_argument("--root", help="Existing absolute kai-skills origin directory")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    data = args.source.read_bytes()
    if not data or "# KAI Skills" not in data.decode("utf-8"):
        parser.error("source must be a nonempty UTF-8 KAI Skills guide")
    digest = hashlib.sha256(data).hexdigest()
    if not args.url.startswith("https://") or args.timeout < 1:
        parser.error("HTTPS URL and positive timeout required")
    print(f"Guide: {args.source}; SHA256: {digest}; URL: {args.url}", flush=True)
    if args.action == "plan":
        return
    if args.action == "publish":
        if not args.host or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.@-]*", args.host):
            parser.error("valid --host required")
        if not args.root or not re.fullmatch(r"/[A-Za-z0-9_./-]+/kai-skills", args.root) or ".." in args.root.split("/"):
            parser.error("absolute --root ending in /kai-skills required")
        # stdin carries only document bytes. All shell values are quoted or fixed.
        remote = """set -eu
root=%s
test -d "$root" && test ! -L "$root"
cd "$root"
mkdir .agent-guide-lock || { echo 'Another guide publication is active' >&2; exit 1; }
tmp=
trap 'test -z "$tmp" || rm -f "$tmp"; rmdir .agent-guide-lock' EXIT
if test -L guides; then exit 1; fi
mkdir -p guides
tmp=$(mktemp "$root/.agent-install.XXXXXX")
cat > "$tmp"
test "$(sha256sum "$tmp" | cut -d ' ' -f 1)" = %s
if test -e agent-install.md || test -L agent-install.md; then
  test -f agent-install.md && test ! -L agent-install.md
  old=$(sha256sum agent-install.md | cut -d ' ' -f 1)
  test ! -L "guides/$old.md"
  if test -e "guides/$old.md"; then cmp agent-install.md "guides/$old.md"; else cp agent-install.md "guides/$old.md"; fi
fi
test ! -L guides/%s.md
if test -e guides/%s.md; then cmp "$tmp" guides/%s.md; else cp "$tmp" guides/%s.md; fi
chmod 644 "$tmp" guides/%s.md
mv -f "$tmp" agent-install.md
tmp=
echo 'Origin published; waiting for public readback'
""" % (shlex.quote(args.root), digest, digest, digest, digest, digest, digest)
        subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                        "-o", "ConnectTimeout=15", args.host, remote], input=data, check=True)
    deadline = time.monotonic() + args.timeout
    while True:
        try:
            request = urllib.request.Request(args.url, headers={"Cache-Control": "no-cache"})
            with urllib.request.urlopen(request, timeout=15) as response:
                actual = response.read()
            if actual == data:
                print("Public HTTPS content matches local guide byte for byte")
                return
            error = "public content has not synchronized"
        except (OSError, ValueError) as exc:
            error = str(exc)
        if time.monotonic() >= deadline:
            raise SystemExit("Public verification failed; origin may already be updated: " + error)
        print("Waiting: " + error, flush=True)
        time.sleep(5)


if __name__ == "__main__":
    main()
