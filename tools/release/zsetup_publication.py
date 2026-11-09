#!/usr/bin/env python3
"""Compose the immutable public /binary/kai/kai-skills tree."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

import zsetup_release


SOURCE_ROOTS = [
    "https://dl.istoreos.com/binary/kai/kai-skills",
    "https://fw.d4ctech.com/binary/kai/kai-skills",
    "https://fw20.koolcenter.com/binary/kai/kai-skills",
    "https://fw.koolcenter.com/binary/kai/kai-skills",
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def files(root):
    return sorted(path for path in Path(root).rglob("*") if path.is_file())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def copy_file(source, destination):
    require(source.is_file() and not source.is_symlink(), f"unsafe source {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    destination.chmod(0o755 if source.suffix == ".sh" else 0o644)


def build(release, installer, entrypoints, channel_entrypoint, output):
    release = release.resolve()
    installer = installer.resolve()
    entrypoints = entrypoints.resolve()
    channel_entrypoint = channel_entrypoint.resolve()
    output = output.absolute()
    require(not output.exists() and not output.is_symlink(), "publication output must be new")
    manifest = zsetup_release.verify_release(release)
    version = manifest["version"]
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", version),
            "invalid release version")
    require(installer.is_file() and not installer.is_symlink(), "installer is unavailable")
    require((entrypoints / "install.sh").is_file(), "generic entrypoint is unavailable")
    require(channel_entrypoint.is_file() and not channel_entrypoint.is_symlink(),
            "channel entrypoint is unavailable")
    expected_entries = {"install.sh"}
    expected_entries.update(f"skills/{item['id']}.sh" for item in manifest["artifacts"]
                            if item["kind"] == "skill")
    expected_entries.update(f"systems/{item['id']}.sh" for item in manifest["artifacts"]
                            if item["kind"] == "system")
    actual_entries = {path.relative_to(entrypoints).as_posix() for path in files(entrypoints)}
    require(actual_entries == expected_entries, "entrypoint set does not match release artifacts")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".kai-publication-", dir=output.parent) as name:
        stage = Path(name)
        for source in files(release):
            copy_file(source, stage / "releases" / version / source.relative_to(release))
        copy_file(installer, stage / "installers" / version / "kai-skills-install.sh")
        for source in files(entrypoints):
            copy_file(source, stage / "entrypoints" / version / source.relative_to(entrypoints))
        copy_file(channel_entrypoint, stage / "setup.sh")
        copy_file(channel_entrypoint, stage / "install.sh")
        (stage / "stable").write_text(version + "\n", encoding="utf-8")
        publication = {
            "schemaVersion": 2,
            "distribution": "kai-skills-zsetup-publication",
            "version": version,
            "minimumZsetupVersion": manifest["minimumZsetupVersion"],
            "sourceRoots": SOURCE_ROOTS,
            "releaseManifest": f"releases/{version}/release-manifest.json",
            "installer": {
                "path": f"installers/{version}/kai-skills-install.sh",
                "size": installer.stat().st_size,
                "sha256": "sha256:" + sha(installer),
            },
            "channelEntry": {
                "path": "setup.sh",
                "aliases": ["install.sh"],
                "role": "version-free-current-channel",
                "size": channel_entrypoint.stat().st_size,
                "sha256": "sha256:" + sha(channel_entrypoint),
            },
            "entrypoints": sorted(expected_entries),
        }
        (stage / "publication-manifest.json").write_text(
            json.dumps(publication, ensure_ascii=True, sort_keys=True,
                       separators=(",", ":")) + "\n", encoding="utf-8"
        )
        checksums = "".join(
            f"{sha(path)}  {path.relative_to(stage).as_posix()}\n"
            for path in files(stage)
            if path.name != "PUBLICATION-SHA256SUMS"
        )
        (stage / "PUBLICATION-SHA256SUMS").write_text(checksums, encoding="utf-8")
        verify(stage)
        stage.rename(output)
    return publication


def verify(directory):
    directory = Path(directory).resolve()
    publication = json.loads((directory / "publication-manifest.json").read_text())
    require(publication["schemaVersion"] == 2 and
            publication["distribution"] == "kai-skills-zsetup-publication",
            "invalid publication manifest")
    require(publication["sourceRoots"] == SOURCE_ROOTS, "source root order mismatch")
    version = publication["version"]
    require((directory / "stable").read_text() == version + "\n", "stable mismatch")
    release = directory / "releases" / version
    zsetup_release.verify_release(release)
    installer = directory / publication["installer"]["path"]
    require(installer.stat().st_size == publication["installer"]["size"] and
            "sha256:" + sha(installer) == publication["installer"]["sha256"],
            "installer pin mismatch")
    channel = directory / publication["channelEntry"]["path"]
    require(publication["channelEntry"]["role"] == "version-free-current-channel" and
            channel.stat().st_size == publication["channelEntry"]["size"] and
            "sha256:" + sha(channel) == publication["channelEntry"]["sha256"],
            "public channel entrypoint mismatch")
    require(publication["channelEntry"]["aliases"] == ["install.sh"] and
            (directory / "install.sh").read_bytes() == channel.read_bytes(),
            "public channel alias mismatch")
    require(b"KAI_SKILLS_REQUESTED_RELEASE=" not in channel.read_bytes(),
            "public channel entrypoint must not pin a release")
    expected = "".join(
        f"{sha(path)}  {path.relative_to(directory).as_posix()}\n"
        for path in files(directory)
        if path.name != "PUBLICATION-SHA256SUMS"
    )
    require((directory / "PUBLICATION-SHA256SUMS").read_text() == expected,
            "publication checksum list mismatch")
    return publication


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build")
    builder.add_argument("--release", required=True, type=Path)
    builder.add_argument("--installer", required=True, type=Path)
    builder.add_argument("--entrypoints", required=True, type=Path)
    builder.add_argument("--channel-entrypoint", required=True, type=Path)
    builder.add_argument("--output", required=True, type=Path)
    checker = commands.add_parser("verify")
    checker.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        result = (build(args.release, args.installer, args.entrypoints,
                        args.channel_entrypoint, args.output)
                  if args.command == "build" else verify(args.directory))
        print(json.dumps({"status": "passed", "version": result["version"]}))
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(1, "failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
