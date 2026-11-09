#!/usr/bin/env python3
"""Build-time schema and integrity helpers for the zsetup distribution.

The target does not run Python. Runtime download, verification and extraction
belong to zsetup; this module freezes and validates the bytes it will consume.
"""
import hashlib
import argparse
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/business"))
from package import members as tree_members, tree_digest, write_json

_legacy_spec = importlib.util.spec_from_file_location(
    "kai_business_release", Path(__file__).with_name("business_release.py")
)
_legacy = importlib.util.module_from_spec(_legacy_spec)
_legacy_spec.loader.exec_module(_legacy)


SCHEMA_VERSION = 3
ARCHIVE_FORMAT = "tar.gz"
DISTRIBUTION = "kai-skills-zsetup"
MINIMUM_ZSETUP_VERSION = "0.6.0"
SYSTEMS = {"istoreos", "ubuntu", "windows"}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def canonical_json(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return "sha256:" + value.hexdigest()


def safe_relative(value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value,
            "unsafe release path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in ("", ".", "..") for part in value.split("/")),
            "unsafe release path")
    return value


def _sha(value, field):
    require(isinstance(value, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", value),
            "invalid " + field)
    return value


def verify_manifest(directory, manifest):
    directory = Path(directory).resolve()
    require(manifest.get("schemaVersion") == SCHEMA_VERSION, "unsupported zsetup release schema")
    require(manifest.get("distribution") == DISTRIBUTION, "invalid distribution")
    require(manifest.get("minimumZsetupVersion") == MINIMUM_ZSETUP_VERSION,
            "invalid minimum zsetup version")
    require(manifest.get("archiveFormat") == ARCHIVE_FORMAT, "unsupported archive format")
    require(isinstance(manifest.get("version"), str) and manifest["version"], "missing release version")
    require(re.fullmatch(r"[0-9a-f]{40,64}", manifest.get("sourceCommit", "")), "invalid source commit")
    require(manifest.get("sourceState") in ("committed", "worktree"), "invalid source state")

    identities, paths, system_artifacts = set(), set(), {}
    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list) and artifacts, "release has no artifacts")
    for artifact in artifacts:
        kind, identity = artifact.get("kind"), artifact.get("id")
        require(kind in ("skill", "system") and isinstance(identity, str) and identity,
                "invalid artifact identity")
        key = (kind, identity)
        require(key not in identities, "duplicate artifact identity")
        identities.add(key)
        path = safe_relative(artifact.get("path"))
        expected_prefix = kind + "s/"
        require(path.startswith(expected_prefix) and path.endswith("." + ARCHIVE_FORMAT),
                "artifact path does not match kind or format")
        require(path not in paths, "duplicate artifact path")
        paths.add(path)
        file_path = directory / path
        require(file_path.resolve() == file_path.absolute() and file_path.is_file(),
                "missing or aliased artifact")
        require(isinstance(artifact.get("size"), int) and artifact["size"] > 0 and
                artifact["size"] == file_path.stat().st_size, "artifact size mismatch")
        require(isinstance(artifact.get("expandedSize"), int) and artifact["expandedSize"] > 0,
                "invalid expanded size")
        require(isinstance(artifact.get("fileCount"), int) and
                0 < artifact["fileCount"] <= 1_000_000, "invalid archive file count")
        require(_sha(artifact.get("sha256"), "artifact sha256") == digest(file_path),
                "artifact sha256 mismatch")
        _sha(artifact.get("treeDigest"), "tree digest")
        safe_relative(artifact.get("root"))
        require("/" not in artifact["root"], "artifact root must be one directory")
        require(artifact.get("version") == manifest["version"], "artifact version mismatch")
        members = artifact.get("members")
        require(isinstance(members, list) and members and len(set(members)) == len(members) and
                all(isinstance(member, str) and member for member in members), "invalid artifact members")
        if kind == "skill":
            require(members == [identity], "single skill artifact has extra members")
        else:
            require(identity in SYSTEMS, "unsupported system artifact")
            system_artifacts[identity] = members

    systems = manifest.get("systems")
    require(isinstance(systems, list), "invalid systems")
    seen_systems = set()
    for system in systems:
        identity = system.get("id")
        require(identity in SYSTEMS and identity not in seen_systems, "invalid or duplicate system")
        seen_systems.add(identity)
        require(system.get("platform") == identity and system.get("mode") == "on-device",
                "invalid system selection")
        safe_relative(system.get("lockPath"))
        members = system.get("members")
        require(isinstance(members, list) and members, "empty system lock")
        member_ids = []
        for member in members:
            require(set(member) == {"id", "version", "treeDigest"}, "invalid system lock member")
            require(isinstance(member["id"], str) and member["id"], "invalid system member id")
            require(member["version"] == manifest["version"], "system member version mismatch")
            _sha(member["treeDigest"], "system member tree digest")
            member_ids.append(member["id"])
        require(len(set(member_ids)) == len(member_ids), "duplicate system member")
        require(system_artifacts.get(identity) == member_ids, "system members differ from artifact")
    require(seen_systems == SYSTEMS and set(system_artifacts) == SYSTEMS,
            "release must contain iStoreOS, Ubuntu and Windows systems")
    return manifest


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def file_digests(directory):
    directory = Path(directory)
    return {
        path.relative_to(directory).as_posix(): digest(path)
        for path in tree_members(directory)
    }


def _source_identity(root):
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    require(re.fullmatch(r"[0-9a-f]{40,64}", commit), "invalid actual Git commit")
    dirty = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"], text=True
    )
    return commit, "worktree" if dirty else "committed"


def _copy_file(root, stage, relative):
    source = root / safe_relative(relative)
    require(source.is_file() and not source.is_symlink(), "missing or aliased source: " + relative)
    target = stage / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def _stage_distribution(root, stage, catalog, selected, source, lock=None):
    for relative in ("install.sh", "install.ps1", "tools/install-business.sh"):
        _copy_file(root, stage, relative)
    for package in selected:
        source_path = root / safe_relative(package["path"])
        require(source_path.is_dir() and not source_path.is_symlink(), "missing package source")
        shutil.copytree(source_path, stage / package["path"])
    filtered = dict(catalog)
    filtered["skills"] = selected
    filtered["bundles"] = {}
    write_json(stage / "business-catalog.json", filtered)
    if lock is not None:
        _copy_file(root, stage, lock["lockPath"])
    write_json(stage / "SOURCE.json", source)


def _release_units(root, catalog):
    packages = {item["id"]: item for item in catalog["skills"]}
    require(len(packages) == len(catalog["skills"]), "duplicate catalog skill")
    units = []
    for identity in sorted(packages):
        units.append({"kind": "skill", "id": identity, "members": [identity],
                      "selected": [packages[identity]], "lock": None})
    systems = []
    for identity in sorted(SYSTEMS):
        lock_path = f"bundles/{identity}-all-on-device.json"
        lock = read(root / lock_path)
        require(lock.get("id") == f"system:{identity}:on-device" and
                lock.get("platform") == identity and lock.get("mode") == "on-device",
                "invalid system lock: " + identity)
        for member in lock["members"]:
            require(member == {key: packages[member["id"]][key]
                               for key in ("id", "version", "treeDigest")},
                    "stale system lock: " + identity)
        selected = [packages[member["id"]] for member in lock["members"]]
        record = {"id": identity, "platform": identity, "mode": "on-device",
                  "lockPath": lock_path, "members": lock["members"]}
        systems.append(record)
        units.append({"kind": "system", "id": identity,
                      "members": [member["id"] for member in lock["members"]],
                      "selected": selected, "lock": record})
    return units, systems


def build(root, output):
    root, output = Path(root).resolve(), Path(output).absolute()
    require(not output.exists(), "output must be a new directory")
    require(output.parent.is_dir() and output.resolve() == output, "unsafe output parent")
    catalog = read(root / "business-catalog.json")
    version = catalog["version"]
    units, systems = _release_units(root, catalog)
    commit, state = _source_identity(root)
    source_paths = [
        "business-catalog.json",
        "install.sh",
        "install.ps1",
        "tools/install-business.sh",
        "tools/release/zsetup_release.py",
        "docs/architecture/kai-skills-zsetup-contract.json",
    ] + [system["lockPath"] for system in systems]
    source_files = {name: digest(root / name) for name in sorted(source_paths)}
    with tempfile.TemporaryDirectory(prefix=".kai-zsetup-release-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        candidate = temporary / "candidate"
        (candidate / "skills").mkdir(parents=True)
        (candidate / "systems").mkdir()
        artifacts = []
        for unit in units:
            stage = temporary / "stage"
            stage.mkdir()
            source = {
                "schemaVersion": 3,
                "distribution": DISTRIBUTION,
                "sourceCommit": commit,
                "sourceState": state,
                "kind": unit["kind"],
                "id": unit["id"],
                "members": [
                    {key: package[key] for key in ("id", "version", "treeDigest")}
                    for package in unit["selected"]
                ],
                "sourceFiles": source_files,
            }
            _stage_distribution(root, stage, catalog, unit["selected"], source, unit["lock"])
            staged_files = list(tree_members(stage))
            top = f"kai-{unit['kind']}-{unit['id']}-v{version}"
            relative = f"{unit['kind']}s/{unit['id']}.{ARCHIVE_FORMAT}"
            target = candidate / relative
            _legacy.archive(stage, top, target, ARCHIVE_FORMAT)
            artifacts.append({
                "kind": unit["kind"],
                "id": unit["id"],
                "version": version,
                "path": relative,
                "size": target.stat().st_size,
                "expandedSize": sum(path.stat().st_size for path in staged_files),
                "fileCount": len(staged_files),
                "sha256": digest(target),
                "treeDigest": tree_digest(stage),
                "root": top,
                "members": unit["members"],
            })
            shutil.rmtree(stage)
        manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "distribution": DISTRIBUTION,
            "version": version,
            "sourceCommit": commit,
            "sourceState": state,
            "minimumZsetupVersion": MINIMUM_ZSETUP_VERSION,
            "archiveFormat": ARCHIVE_FORMAT,
            "sourceFiles": source_files,
            "systems": systems,
            "artifacts": artifacts,
        }
        (candidate / "release-manifest.json").write_bytes(canonical_json(manifest))
        sums = []
        for path in tree_members(candidate):
            relative = path.relative_to(candidate).as_posix()
            if relative != "SHA256SUMS":
                sums.append(digest(path).split(":", 1)[1] + "  " + relative + "\n")
        (candidate / "SHA256SUMS").write_text("".join(sums), encoding="utf-8")
        verify_release(candidate)
        candidate.rename(output)
    return manifest


def extract_for_test(directory, artifact):
    temporary = Path(tempfile.mkdtemp(prefix="kai-zsetup-extract-"))
    _legacy.unpack(Path(directory) / artifact["path"], ARCHIVE_FORMAT, temporary, artifact["root"])
    return temporary / artifact["root"]


def verify_release(directory):
    directory = Path(directory).resolve()
    manifest_path = directory / "release-manifest.json"
    require(manifest_path.is_file() and not manifest_path.is_symlink(), "missing release manifest")
    manifest = read(manifest_path)
    verify_manifest(directory, manifest)
    systems = {item["id"]: item for item in manifest["systems"]}
    for artifact in manifest["artifacts"]:
        root = extract_for_test(directory, artifact)
        try:
            require(tree_digest(root) == artifact["treeDigest"], "archive tree digest mismatch")
            files = list(tree_members(root))
            require(len(files) == artifact["fileCount"] and
                    sum(path.stat().st_size for path in files) == artifact["expandedSize"],
                    "archive expansion bounds mismatch")
            require((root / "install.sh").is_file() and
                    (root / "install.ps1").is_file() and
                    (root / "tools/install-business.sh").is_file(), "managed installer missing")
            catalog = read(root / "business-catalog.json")
            require([item["id"] for item in catalog["skills"]] == artifact["members"],
                    "archive catalog members mismatch")
            require({path.parent.name for path in (root / "skills").glob("*/SKILL.md")} ==
                    set(artifact["members"]), "archive skill members mismatch")
            for package in catalog["skills"]:
                require(tree_digest(root / package["path"]) == package["treeDigest"],
                        "archive package digest mismatch")
            if artifact["kind"] == "system":
                system = systems[artifact["id"]]
                lock = read(root / system["lockPath"])
                require(lock["members"] == system["members"], "archive system lock mismatch")
            source = read(root / "SOURCE.json")
            require(source["sourceCommit"] == manifest["sourceCommit"] and
                    source["sourceState"] == manifest["sourceState"] and
                    source["sourceFiles"] == manifest["sourceFiles"], "archive source mismatch")
        finally:
            shutil.rmtree(root.parent)
    expected_sums = "".join(
        digest(path).split(":", 1)[1] + "  " + path.relative_to(directory).as_posix() + "\n"
        for path in tree_members(directory)
        if path.relative_to(directory).as_posix() != "SHA256SUMS"
    )
    require((directory / "SHA256SUMS").read_text(encoding="utf-8") == expected_sums,
            "SHA256SUMS mismatch")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("directory", type=Path)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            manifest = build(ROOT, args.directory)
            print(json.dumps({"status": "built", "artifacts": len(manifest["artifacts"]),
                              "sourceState": manifest["sourceState"]}))
        else:
            manifest = verify_release(args.directory)
            print(json.dumps({"status": "verified", "artifacts": len(manifest["artifacts"])}))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, "failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
