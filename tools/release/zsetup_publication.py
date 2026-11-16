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
import freeze as release_freeze


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


def build(release, installer, windows_installer, entrypoints, channel_entrypoint,
          windows_channel_entrypoint, freeze_manifest, output,
          allow_fixture_freeze=False):
    release = release.resolve()
    installer = installer.resolve()
    windows_installer = windows_installer.resolve()
    entrypoints = entrypoints.resolve()
    channel_entrypoint = channel_entrypoint.resolve()
    windows_channel_entrypoint = windows_channel_entrypoint.resolve()
    output = output.absolute()
    require(not output.exists() and not output.is_symlink(), "publication output must be new")
    manifest = zsetup_release.verify_release(release)
    frozen = release_freeze.verify(freeze_manifest.resolve().parent)
    require(release == (freeze_manifest.resolve().parent / "zsetup").resolve(),
            "zsetup release must come from the reviewed freeze")
    require(frozen["sourcePolicy"] == "clean-committed" or
            (allow_fixture_freeze and frozen["sourcePolicy"] == "explicit-test-fixture"),
            "publication requires a clean committed freeze")
    version = manifest["version"]
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", version),
            "invalid release version")
    require(installer.is_file() and not installer.is_symlink(), "installer is unavailable")
    require(windows_installer.is_file() and not windows_installer.is_symlink(),
            "Windows installer is unavailable")
    require((entrypoints / "install.sh").is_file(), "generic entrypoint is unavailable")
    require(channel_entrypoint.is_file() and not channel_entrypoint.is_symlink(),
            "channel entrypoint is unavailable")
    require(windows_channel_entrypoint.is_file() and not windows_channel_entrypoint.is_symlink(),
            "Windows channel entrypoint is unavailable")
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
        copy_file(windows_installer, stage / "installers" / version / "kai-skills-install.ps1")
        for source in files(entrypoints):
            copy_file(source, stage / "entrypoints" / version / source.relative_to(entrypoints))
        copy_file(channel_entrypoint, stage / "setup.sh")
        copy_file(channel_entrypoint, stage / "install.sh")
        copy_file(windows_channel_entrypoint, stage / "setup.ps1")
        copy_file(freeze_manifest.resolve(), stage / "release-freeze.json")
        (stage / "stable").write_text(version + "\n", encoding="utf-8")
        publication = {
            "schemaVersion": 2,
            "distribution": "kai-skills-zsetup-publication",
            "version": version,
            "minimumZsetupVersion": manifest["minimumZsetupVersion"],
            "freezeReleaseId": frozen["releaseId"],
            "sourceRoots": SOURCE_ROOTS,
            "releaseManifest": f"releases/{version}/release-manifest.json",
            "installer": {
                "path": f"installers/{version}/kai-skills-install.sh",
                "size": installer.stat().st_size,
                "sha256": "sha256:" + sha(installer),
            },
            "windowsInstaller": {
                "path": f"installers/{version}/kai-skills-install.ps1",
                "size": windows_installer.stat().st_size,
                "sha256": "sha256:" + sha(windows_installer),
            },
            "channelEntry": {
                "path": "setup.sh",
                "aliases": ["install.sh"],
                "role": "version-free-current-channel",
                "size": channel_entrypoint.stat().st_size,
                "sha256": "sha256:" + sha(channel_entrypoint),
            },
            "windowsChannelEntry": {
                "path": "setup.ps1",
                "aliases": [],
                "role": "version-free-current-channel",
                "size": windows_channel_entrypoint.stat().st_size,
                "sha256": "sha256:" + sha(windows_channel_entrypoint),
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
    frozen = release_freeze.verify_identity(json.loads((directory / "release-freeze.json").read_text()))
    require(publication.get("freezeReleaseId") == frozen["releaseId"], "publication freeze identity mismatch")
    require((directory / "stable").read_text() == version + "\n", "stable mismatch")
    release = directory / "releases" / version
    zsetup_release.verify_release(release)
    manifest_path = release / "release-manifest.json"
    record = frozen["files"].get("zsetup/release-manifest.json", {})
    require(record.get("sha256") == "sha256:" + sha(manifest_path) and
            record.get("size") == manifest_path.stat().st_size,
            "publication release differs from freeze")
    installer = directory / publication["installer"]["path"]
    require(installer.stat().st_size == publication["installer"]["size"] and
            "sha256:" + sha(installer) == publication["installer"]["sha256"],
            "installer pin mismatch")
    windows_installer = directory / publication["windowsInstaller"]["path"]
    require(windows_installer.stat().st_size == publication["windowsInstaller"]["size"] and
            "sha256:" + sha(windows_installer) == publication["windowsInstaller"]["sha256"],
            "Windows installer pin mismatch")
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
    windows_channel = directory / publication["windowsChannelEntry"]["path"]
    require(publication["windowsChannelEntry"]["role"] == "version-free-current-channel" and
            publication["windowsChannelEntry"]["aliases"] == [] and
            windows_channel.stat().st_size == publication["windowsChannelEntry"]["size"] and
            "sha256:" + sha(windows_channel) == publication["windowsChannelEntry"]["sha256"],
            "public Windows channel entrypoint mismatch")
    require(b"KAI_SKILLS_REQUESTED_RELEASE" not in windows_channel.read_bytes(),
            "public Windows channel entrypoint must not pin a release")
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
    builder.add_argument("--windows-installer", required=True, type=Path)
    builder.add_argument("--entrypoints", required=True, type=Path)
    builder.add_argument("--channel-entrypoint", required=True, type=Path)
    builder.add_argument("--windows-channel-entrypoint", required=True, type=Path)
    builder.add_argument("--freeze-manifest", required=True, type=Path)
    builder.add_argument("--allow-fixture-freeze", action="store_true")
    builder.add_argument("--output", required=True, type=Path)
    checker = commands.add_parser("verify")
    checker.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        result = (build(args.release, args.installer, args.windows_installer, args.entrypoints,
                        args.channel_entrypoint, args.windows_channel_entrypoint,
                        args.freeze_manifest, args.output,
                        args.allow_fixture_freeze)
                  if args.command == "build" else verify(args.directory))
        print(json.dumps({"status": "passed", "version": result["version"]}))
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(1, "failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
