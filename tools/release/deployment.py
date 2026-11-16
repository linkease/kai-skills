#!/usr/bin/env python3
"""Package and transact the /binary/kai deployment from one reviewed freeze."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import urllib.parse
import urllib.request


PUBLIC_BASES = [
    "https://dl.istoreos.com/binary/kai",
    "https://fw.d4ctech.com/binary/kai",
    "https://fw20.koolcenter.com/binary/kai",
    "https://fw.koolcenter.com/binary/kai",
]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
release_freeze = load("deployment_freeze", HERE / "freeze.py")
publication_tool = load("deployment_publication", HERE / "zsetup_publication.py")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n").encode()


def safe(value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value,
            "unsafe deployment path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in ("", ".", "..") for part in value.split("/")),
            "unsafe deployment path")
    return value


def copy(source, destination):
    require(source.is_file() and not source.is_symlink(), "unsafe deployment source")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    destination.chmod(0o755 if source.suffix == ".sh" else 0o644)


def build(freeze_root, publication, output, allow_fixture_freeze=False):
    freeze_root, publication, output = Path(freeze_root).resolve(), Path(publication).resolve(), Path(output).absolute()
    require(not output.exists() and not output.is_symlink(), "deployment package output must be new")
    frozen = release_freeze.verify(freeze_root)
    require(frozen["sourcePolicy"] == "clean-committed" or
            (allow_fixture_freeze and frozen["sourcePolicy"] == "explicit-test-fixture"),
            "deployment requires a clean committed freeze")
    public = publication_tool.verify(publication)
    require(public.get("freezeReleaseId") == frozen["releaseId"], "publication and freeze differ")
    release_hex = frozen["releaseId"].split(":", 1)[1]
    with tempfile.TemporaryDirectory(prefix=".kai-deployment-", dir=output.parent) as name:
        stage = Path(name)
        records = []

        def add(source, kind, destination):
            safe(destination)
            target = stage / kind / destination
            copy(source, target)
            records.append({"kind": kind, "source": f"{kind}/{destination}",
                            "destination": destination, "sha256": sha(target),
                            "size": target.stat().st_size,
                            "mode": 0o755 if target.suffix == ".sh" else 0o644})

        for source in sorted(path for path in publication.rglob("*") if path.is_file()):
            relative = source.relative_to(publication).as_posix()
            kind = "immutable" if relative.startswith(("releases/", "installers/", "entrypoints/")) else "pointers"
            add(source, kind, "kai-skills/" + relative)
        snapshot_archive = freeze_root / "kaiplus/snapshot.tar.gz"
        archive_destination = f"defaults/snapshot-v2/releases/{release_hex}/snapshot.tar.gz"
        add(snapshot_archive, "immutable", archive_destination)
        index = json.loads((freeze_root / "kaiplus/index.json").read_text())
        index["archive"] = f"releases/{release_hex}/snapshot.tar.gz"
        index_path = stage / ".index.json"
        index_path.write_bytes(canonical(index))
        add(index_path, "pointers", "defaults/snapshot-v2/index.json")
        index_path.unlink()
        add(freeze_root / "freeze-manifest.json", "pointers", "release-freeze.json")
        records.sort(key=lambda item: (item["kind"], item["destination"]))
        core = {
            "schemaVersion": 1,
            "deployment": "kai-public",
            "version": frozen["version"],
            "freezeReleaseId": frozen["releaseId"],
            "publicBases": PUBLIC_BASES,
            "files": records,
            "activationOrder": [item["destination"] for item in records if item["kind"] == "pointers" and
                                item["destination"] not in ("kai-skills/stable", "defaults/snapshot-v2/index.json")] +
                               ["kai-skills/stable", "defaults/snapshot-v2/index.json"],
        }
        core["deploymentId"] = "sha256:" + hashlib.sha256(canonical(core)).hexdigest()
        (stage / "deployment-manifest.json").write_bytes(canonical(core))
        verify(stage)
        stage.rename(output)
    return core


def verify(package):
    package = Path(package).resolve()
    manifest = json.loads((package / "deployment-manifest.json").read_text())
    deployment_id = manifest.pop("deploymentId", None)
    require(deployment_id == "sha256:" + hashlib.sha256(canonical(manifest)).hexdigest(),
            "deployment identity mismatch")
    manifest["deploymentId"] = deployment_id
    require(manifest.get("schemaVersion") == 1 and manifest.get("deployment") == "kai-public" and
            manifest.get("publicBases") == PUBLIC_BASES, "invalid deployment manifest")
    destinations = set()
    for record in manifest["files"]:
        require(record.get("kind") in ("immutable", "pointers"), "invalid deployment file kind")
        source, destination = safe(record.get("source")), safe(record.get("destination"))
        require(destination not in destinations, "duplicate deployment destination")
        destinations.add(destination)
        path = package / source
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == record.get("size") and
                sha(path) == record.get("sha256"), "deployment file mismatch")
    require(set(manifest["activationOrder"]) ==
            {item["destination"] for item in manifest["files"] if item["kind"] == "pointers"},
            "activation order differs from pointer set")
    frozen = release_freeze.verify_identity(json.loads((package / "pointers/release-freeze.json").read_text()))
    require(frozen["releaseId"] == manifest["freezeReleaseId"], "deployment freeze differs")
    return manifest


def _atomic_copy(source, destination, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".kai-write-", delete=False) as stream:
        temporary = Path(stream.name)
        with source.open("rb") as body:
            shutil.copyfileobj(body, stream)
        stream.flush(); os.fsync(stream.fileno())
    try:
        temporary.chmod(mode)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def _locked(root):
    root.mkdir(parents=True, exist_ok=True)
    lock = (root / ".kai-release.lock").open("a+b")
    fcntl.flock(lock, fcntl.LOCK_EX)
    return lock


def _snapshot_root(root, manifest):
    return root / ".rollouts" / manifest["deploymentId"].split(":", 1)[1]


def stage(package, root):
    package, root = Path(package).resolve(), Path(root).resolve()
    manifest = verify(package)
    lock = _locked(root)
    try:
        snapshot = _snapshot_root(root, manifest)
        if snapshot.exists():
            require((snapshot / "phase").read_text().strip() == "staged", "rollout already exists in another phase")
            return manifest
        for record in manifest["files"]:
            if record["kind"] != "immutable":
                continue
            destination = root / record["destination"]
            if destination.exists():
                require(destination.is_file() and not destination.is_symlink() and
                        destination.stat().st_size == record["size"] and sha(destination) == record["sha256"],
                        "immutable destination conflict: " + record["destination"])
            else:
                _atomic_copy(package / record["source"], destination, record["mode"])
        temporary = snapshot.with_name(snapshot.name + ".new")
        require(not temporary.exists(), "stale rollout snapshot staging directory")
        (temporary / "baseline").mkdir(parents=True)
        baseline = []
        for record in manifest["files"]:
            if record["kind"] != "pointers":
                continue
            destination = root / record["destination"]
            item = {"destination": record["destination"], "exists": destination.exists()}
            if destination.exists():
                require(destination.is_file() and not destination.is_symlink(), "unsafe mutable destination")
                target = temporary / "baseline" / record["destination"]
                copy(destination, target)
                item.update({"sha256": sha(destination), "size": destination.stat().st_size,
                             "mode": destination.stat().st_mode & 0o777})
            baseline.append(item)
        (temporary / "baseline.json").write_bytes(canonical(baseline))
        (temporary / "deployment-id").write_text(manifest["deploymentId"] + "\n")
        (temporary / "phase").write_text("staged\n")
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        temporary.rename(snapshot)
        return manifest
    finally:
        lock.close()


def _verify_baseline(root, snapshot):
    for item in json.loads((snapshot / "baseline.json").read_text()):
        destination = root / item["destination"]
        require(destination.exists() == item["exists"], "mutable destination changed after stage")
        if item["exists"]:
            require(destination.is_file() and sha(destination) == item["sha256"] and
                    destination.stat().st_size == item["size"], "mutable destination changed after stage")


def _restore(root, snapshot):
    for item in json.loads((snapshot / "baseline.json").read_text()):
        destination = root / item["destination"]
        if item["exists"]:
            _atomic_copy(snapshot / "baseline" / item["destination"], destination, item["mode"])
        elif destination.exists():
            require(destination.is_file() and not destination.is_symlink(), "unsafe rollback destination")
            destination.unlink()


def verify_origin(package, root, phase):
    manifest = verify(package)
    expected = [item for item in manifest["files"] if phase == "activated" or item["kind"] == "immutable"]
    for item in expected:
        path = Path(root) / item["destination"]
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == item["size"] and
                sha(path) == item["sha256"], "origin readback mismatch: " + item["destination"])
    return len(expected)


def readback(package, root, bases, phase, output, opener=urllib.request.urlopen):
    manifest = verify(package)
    require(phase in ("staged", "activated"), "invalid readback phase")
    require(list(bases) == PUBLIC_BASES, "all four ordered public bases are required")
    count = verify_origin(package, root, phase)
    expected = [item for item in manifest["files"] if phase == "activated" or item["kind"] == "immutable"]
    for base in bases:
        parsed = urllib.parse.urlsplit(base)
        require(parsed.scheme == "https" and parsed.netloc and not parsed.query and not parsed.fragment,
                "invalid public base")
        for item in expected:
            url = base.rstrip("/") + "/" + "/".join(urllib.parse.quote(part) for part in item["destination"].split("/"))
            with opener(url, timeout=60) as response:
                body = response.read(item["size"] + 1)
            require(len(body) == item["size"] and
                    "sha256:" + hashlib.sha256(body).hexdigest() == item["sha256"],
                    "public readback mismatch: " + base + "/" + item["destination"])
    evidence = {"schemaVersion": 1, "deploymentId": manifest["deploymentId"], "phase": phase,
                "originVerified": True, "publicBases": list(bases), "filesPerTarget": count}
    output = Path(output)
    require(not output.exists(), "readback evidence output must be new")
    output.write_bytes(canonical(evidence))
    return evidence


def activate(package, root, evidence_path, fail_after=0):
    package, root = Path(package).resolve(), Path(root).resolve()
    manifest = verify(package)
    evidence = json.loads(Path(evidence_path).read_text())
    require(evidence == {"schemaVersion": 1, "deploymentId": manifest["deploymentId"],
                         "phase": "staged", "originVerified": True, "publicBases": PUBLIC_BASES,
                         "filesPerTarget": len([item for item in manifest["files"] if item["kind"] == "immutable"])},
            "staged readback evidence is incomplete or stale")
    lock = _locked(root)
    try:
        snapshot = _snapshot_root(root, manifest)
        require(snapshot.is_dir() and (snapshot / "phase").read_text().strip() == "staged", "rollout is not staged")
        verify_origin(package, root, "staged")
        _verify_baseline(root, snapshot)
        applied = 0
        try:
            records = {item["destination"]: item for item in manifest["files"] if item["kind"] == "pointers"}
            for destination_name in manifest["activationOrder"]:
                record = records[destination_name]
                _atomic_copy(package / record["source"], root / destination_name, record["mode"])
                applied += 1
                if fail_after and applied == fail_after:
                    raise OSError("injected activation interruption")
        except BaseException:
            _restore(root, snapshot)
            raise
        (snapshot / "phase").write_text("activated\n")
        return manifest
    finally:
        lock.close()


def rollback(package, root):
    package, root = Path(package).resolve(), Path(root).resolve()
    manifest = verify(package)
    lock = _locked(root)
    try:
        snapshot = _snapshot_root(root, manifest)
        require(snapshot.is_dir() and (snapshot / "phase").read_text().strip() == "activated", "rollout is not active")
        for item in manifest["files"]:
            if item["kind"] == "pointers":
                destination = root / item["destination"]
                require(destination.is_file() and sha(destination) == item["sha256"],
                        "refusing out-of-order rollback")
        _restore(root, snapshot)
        (snapshot / "phase").write_text("rolled-back\n")
        return manifest
    finally:
        lock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build")
    builder.add_argument("--freeze", required=True, type=Path)
    builder.add_argument("--publication", required=True, type=Path)
    builder.add_argument("--output", required=True, type=Path)
    builder.add_argument("--allow-fixture-freeze", action="store_true")
    checker = commands.add_parser("verify"); checker.add_argument("package", type=Path)
    for name in ("stage", "rollback"):
        command = commands.add_parser(name); command.add_argument("package", type=Path); command.add_argument("root", type=Path)
    activation = commands.add_parser("activate")
    activation.add_argument("package", type=Path); activation.add_argument("root", type=Path)
    activation.add_argument("--evidence", required=True, type=Path)
    reader = commands.add_parser("readback")
    reader.add_argument("package", type=Path); reader.add_argument("root", type=Path)
    reader.add_argument("--phase", choices=("staged", "activated"), required=True)
    reader.add_argument("--output", required=True, type=Path)
    reader.add_argument("--base", action="append", required=True)
    args = parser.parse_args()
    try:
        if args.command == "build":
            result = build(args.freeze, args.publication, args.output, args.allow_fixture_freeze)
        elif args.command == "verify": result = verify(args.package)
        elif args.command == "stage": result = stage(args.package, args.root)
        elif args.command == "activate": result = activate(args.package, args.root, args.evidence)
        elif args.command == "rollback": result = rollback(args.package, args.root)
        else: result = readback(args.package, args.root, args.base, args.phase, args.output)
        print(json.dumps({"status": "passed", "command": args.command,
                          "deploymentId": result.get("deploymentId", "")}))
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(1, "failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
