#!/usr/bin/env python3
"""Build a complete schema-2 KaiPlus snapshot from owned canonical sources.

Business packages are the existing independent packages, with exactly the same
digests. Canonical layers are transition resources; they are included in the
same transaction as packages, rules and prompts, never updated separately.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/business"))
from model import Distribution
from package import build_package


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    Path(path).chmod(0o644)


def git_source(root):
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    dirty = subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True)
    return {"commit": commit, "state": "worktree" if dirty else "clean"}


def content_digest(files):
    digest = hashlib.sha256()
    for name, record in sorted(files.items()):
        digest.update(f"{name}\0{record['sha256']}\0{record['size']}\0{record['mode']}\n".encode())
    return "sha256:" + digest.hexdigest()


def build(reasonix, output, version):
    reasonix, output = Path(reasonix).resolve(), Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("output must be a fresh directory")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}", version):
        raise ValueError("invalid release version")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".kaiplus-snapshot-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        consumer = temporary / "consumer"
        registry_path = consumer / "internal/systempack/builtin/registry.json"
        registry_path.parent.mkdir(parents=True)
        shutil.copy2(reasonix / "internal/systempack/builtin/registry.json", registry_path)
        shutil.copytree(reasonix / "kaiplus-defaults", consumer / "kaiplus-defaults")
        subprocess.run([sys.executable, str(ROOT / "tools/sync-kai-system-packs.py"),
                        "--reasonix", str(consumer), "--apply"], check=True, stdout=subprocess.DEVNULL)
        stage = temporary / "snapshot"
        shutil.move(consumer / "kaiplus-defaults", stage)
        for name in ["version", ".gitignore", "profiles-version.json", "profiles-update.lock"]:
            (stage / name).unlink(missing_ok=True)
        registry = json.loads(registry_path.read_text())
        dump(stage / "registry.json", registry)
        distribution = Distribution(ROOT)
        packages = []
        for name, metadata in sorted(distribution.packages.items()):
            if metadata["kind"] == "transport":
                continue
            packages.append(build_package(distribution, name, stage / "skills" / name))
        by_id = {p["id"]: p for p in packages}
        collections = {}
        selections = [("bundle:" + name, distribution.select(bundle=name, own_transport=True))
                      for name in distribution.bundles]
        for platform in distribution.config["architectureSupport"]:
            for mode in ["on-device", "remote-control"]:
                selections.append((f"system:{platform}:{mode}", distribution.select(
                    platform=platform, mode=mode, all_skills=True, own_transport=True)))
        for name, selection in selections:
            collections[name] = [{key: by_id[p["id"]][key] for key in ["id", "version", "treeDigest"]}
                                 for p in selection["packages"]]
        dump(stage / "collections.json", collections)
        files = {}
        for path in sorted(stage.rglob("*")):
            if path.is_symlink():
                raise ValueError("snapshot source contains a symlink")
            if not path.is_file():
                continue
            mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
            path.chmod(mode)
            files[path.relative_to(stage).as_posix()] = {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "size": path.stat().st_size, "mode": mode}
        manifest = {"schemaVersion": 2, "version": version, "minKaiVersion": (reasonix / "VERSION").read_text().strip(),
                    "contentDigest": content_digest(files),
                    "sources": {"kai-skills": git_source(ROOT), "reasonix-kai": git_source(reasonix)},
                    "files": files, "packages": packages, "collections": collections, "registry": registry}
        dump(stage / "snapshot.json", manifest)
        stage.rename(output)
    return manifest


def archive(root, destination):
    # Fixed ownership, modes and timestamps; gzip's header has no wall-clock time.
    import gzip
    with Path(destination).open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as gz:
        with tarfile.open(fileobj=gz, mode="w") as tar:
            for path in [root] + sorted(root.rglob("*")):
                info = tar.gettarinfo(str(path), "snapshot" if path == root else "snapshot/" + path.relative_to(root).as_posix())
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.mode = (0o755 if path.stat().st_mode & 0o111 else 0o644) if path.is_file() else 0o755
                if path.is_file():
                    with path.open("rb") as body:
                        tar.addfile(info, body)
                else:
                    tar.addfile(info)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reasonix", type=Path, default=ROOT.parent / "reasonix-kai")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    manifest = build(args.reasonix, args.output, args.version)
    tarball = args.output.with_name(args.output.name + ".tar.gz")
    archive(args.output, tarball)
    index = {"schemaVersion": 2, "version": args.version, "minKaiVersion": manifest["minKaiVersion"],
             "contentDigest": manifest["contentDigest"], "archive": tarball.name,
             "manifestSHA256": hashlib.sha256((args.output / "snapshot.json").read_bytes()).hexdigest(),
             "sha256": hashlib.sha256(tarball.read_bytes()).hexdigest(), "size": tarball.stat().st_size}
    dump(args.output.with_name(args.output.name + ".index.json"), index)
    print(json.dumps({"packages": len(manifest["packages"]), "collections": len(manifest["collections"]), **index}))


if __name__ == "__main__":
    main()
