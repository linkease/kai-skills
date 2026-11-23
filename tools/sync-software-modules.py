#!/usr/bin/env python3
"""Update or verify the native module graph owned by kai-software."""
import argparse, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "tools/business"))
from software_modules import refresh_modules
p = argparse.ArgumentParser(); p.add_argument("--check", action="store_true"); args = p.parse_args()
refresh_modules(root / "components/system-packs/common/skills/kai-software/scripts", args.check)
