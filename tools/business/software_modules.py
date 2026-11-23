"""Hashes bind relocated native modules to the entrypoint plan contract."""
import hashlib, re
from pathlib import Path

def refresh_modules(root, check=False):
    root = Path(root)
    if not (root / "market").is_dir(): return
    for name in ("market", "scoop"):
        modules = sorted((root / name).glob("*.ps1"))
        if name == "scoop": modules += [root / "market.ps1"]
        lines = ["# BEGIN OWNED MODULE HASHES", "$softwareModules=[ordered]@{"]
        for member in modules:
            if member.is_symlink(): raise SystemExit("module symlink rejected")
            lines.append("    '" + member.relative_to(root).as_posix() + "'='" + hashlib.sha256(member.read_bytes()).hexdigest() + "'")
        lines += ["}", "# END OWNED MODULE HASHES"]
        path = root / (name + ".ps1"); old = path.read_text()
        new, count = re.subn(r"# BEGIN OWNED MODULE HASHES.*?# END OWNED MODULE HASHES", "\n".join(lines), old, flags=re.S)
        if count != 1: raise SystemExit("module hash region missing")
        if check and old != new: raise SystemExit("stale module hashes: " + name)
        if not check: path.write_text(new)
