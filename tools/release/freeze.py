#!/usr/bin/env python3
"""Build and verify one reproducible KAI release freeze.

The freeze is the only input accepted by deployment preparation. It binds the
same clean source commits to the KaiPlus snapshot and zsetup schema-3 release.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def source_identity(root, allow_dirty_fixture=False):
    root = Path(root).resolve()
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    require(re.fullmatch(r"[0-9a-f]{40,64}", commit), "invalid source commit")
    dirty = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"], text=True
    )
    if dirty and not allow_dirty_fixture:
        raise ValueError(f"release freeze requires clean committed source: {root.name}")
    return {"commit": commit, "state": "fixture-worktree" if dirty else "committed"}


def files(directory):
    directory = Path(directory)
    return {
        path.relative_to(directory).as_posix(): {
            "sha256": sha256(path), "size": path.stat().st_size,
        }
        for path in sorted(directory.rglob("*")) if path.is_file()
    }


def build_once(kai_root, reasonix_root, destination, version):
    kai_root, reasonix_root = Path(kai_root).resolve(), Path(reasonix_root).resolve()
    zsetup_release = load_module("freeze_zsetup_release", kai_root / "tools/release/zsetup_release.py")
    snapshot = load_module("freeze_kaiplus_snapshot", kai_root / "tools/build-kaiplus-snapshot.py")
    zsetup_release.build(kai_root, destination / "zsetup")
    snapshot_root = destination / "kaiplus" / "snapshot"
    snapshot_root.parent.mkdir(parents=True)
    manifest = snapshot.build(reasonix_root, snapshot_root, version, source_root=kai_root)
    archive = destination / "kaiplus" / "snapshot.tar.gz"
    snapshot.archive(snapshot_root, archive)
    index = {
        "schemaVersion": 2,
        "version": version,
        "minKaiVersion": manifest["minKaiVersion"],
        "contentDigest": manifest["contentDigest"],
        "archive": archive.name,
        "manifestSHA256": hashlib.sha256((snapshot_root / "snapshot.json").read_bytes()).hexdigest(),
        "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "size": archive.stat().st_size,
    }
    (destination / "kaiplus" / "index.json").write_bytes(canonical(index))
    return index


def build(kai_root, reasonix_root, output, version, expected_kai_commit="",
          expected_reasonix_commit="", allow_dirty_fixture=False):
    kai_root, reasonix_root, output = Path(kai_root).resolve(), Path(reasonix_root).resolve(), Path(output).absolute()
    require(not output.exists() and not output.is_symlink(), "freeze output must be new")
    require(output.parent.is_dir() and output.resolve() == output, "unsafe freeze output")
    sources = {
        "kai-skills": source_identity(kai_root, allow_dirty_fixture),
        "reasonix-kai": source_identity(reasonix_root, allow_dirty_fixture),
    }
    if expected_kai_commit:
        require(sources["kai-skills"]["commit"] == expected_kai_commit, "kai-skills commit differs from review")
    if expected_reasonix_commit:
        require(sources["reasonix-kai"]["commit"] == expected_reasonix_commit, "reasonix-kai commit differs from review")
    with tempfile.TemporaryDirectory(prefix=".kai-freeze-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        first, second = temporary / "first", temporary / "second"
        first.mkdir(); second.mkdir()
        index = build_once(kai_root, reasonix_root, first, version)
        build_once(kai_root, reasonix_root, second, version)
        first_files, second_files = files(first), files(second)
        require(first_files == second_files, "two release builds are not byte-identical")
        capability = first / "kaiplus/snapshot/capability-catalog.json"
        zsetup_manifest = first / "zsetup/release-manifest.json"
        manifest = {
            "schemaVersion": 1,
            "version": version,
            "sourcePolicy": "clean-committed" if not allow_dirty_fixture else "explicit-test-fixture",
            "sources": sources,
            "protocols": {"capabilityCatalog": 1, "kaiplusSnapshot": 2, "zsetupRelease": 3},
            "identities": {
                "capabilityCatalogSHA256": sha256(capability),
                "kaiplusManifestSHA256": "sha256:" + index["manifestSHA256"],
                "kaiplusContentDigest": index["contentDigest"],
                "kaiplusArchiveSHA256": "sha256:" + index["sha256"],
                "zsetupManifestSHA256": sha256(zsetup_manifest),
            },
            "files": first_files,
        }
        release_id = hashlib.sha256(canonical(manifest)).hexdigest()
        manifest["releaseId"] = "sha256:" + release_id
        first.rename(output)
        (output / "freeze-manifest.json").write_bytes(canonical(manifest))
    return verify(output)


def verify_identity(value):
    manifest = json.loads(json.dumps(value))
    release_id = manifest.pop("releaseId", None)
    require(release_id == "sha256:" + hashlib.sha256(canonical(manifest)).hexdigest(), "freeze release identity mismatch")
    manifest["releaseId"] = release_id
    require(manifest.get("schemaVersion") == 1 and manifest.get("sourcePolicy") in
            ("clean-committed", "explicit-test-fixture"), "invalid freeze manifest")
    return manifest


def verify(directory):
    directory = Path(directory).resolve()
    manifest_path = directory / "freeze-manifest.json"
    manifest = verify_identity(json.loads(manifest_path.read_text(encoding="utf-8")))
    actual = files(directory)
    actual.pop("freeze-manifest.json", None)
    require(actual == manifest["files"], "freeze file set or digest changed")
    identities = manifest["identities"]
    require(sha256(directory / "kaiplus/snapshot/capability-catalog.json") == identities["capabilityCatalogSHA256"],
            "capability catalog identity mismatch")
    require(sha256(directory / "zsetup/release-manifest.json") == identities["zsetupManifestSHA256"],
            "zsetup release identity mismatch")
    index = json.loads((directory / "kaiplus/index.json").read_text())
    require("sha256:" + index["manifestSHA256"] == identities["kaiplusManifestSHA256"] and
            "sha256:" + index["sha256"] == identities["kaiplusArchiveSHA256"] and
            index["contentDigest"] == identities["kaiplusContentDigest"], "KaiPlus index identity mismatch")
    return manifest


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    build_parser = subcommands.add_parser("build")
    build_parser.add_argument("--kai-root", type=Path, default=root)
    build_parser.add_argument("--reasonix-root", type=Path, required=True)
    build_parser.add_argument("--output", type=Path, required=True)
    build_parser.add_argument("--version", required=True)
    build_parser.add_argument("--expected-kai-commit", default="")
    build_parser.add_argument("--expected-reasonix-commit", default="")
    build_parser.add_argument("--allow-dirty-fixture", action="store_true")
    verify_parser = subcommands.add_parser("verify")
    verify_parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            result = build(args.kai_root, args.reasonix_root, args.output, args.version,
                           args.expected_kai_commit, args.expected_reasonix_commit,
                           args.allow_dirty_fixture)
            print(json.dumps({"status": "frozen", "releaseId": result["releaseId"]}))
        else:
            result = verify(args.directory)
            print(json.dumps({"status": "verified", "releaseId": result["releaseId"]}))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        parser.exit(1, "failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
