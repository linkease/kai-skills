import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "zsetup_release", ROOT / "tools/release/zsetup_release.py"
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ZsetupReleaseSchemaTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kai zsetup schema ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "skills").mkdir()
        (self.root / "systems").mkdir()
        self.skill = self.root / "skills/kai-software.tar.gz"
        self.system = self.root / "systems/istoreos.tar.gz"
        self.ubuntu = self.root / "systems/ubuntu.tar.gz"
        self.skill.write_bytes(b"single-skill-fixture")
        self.system.write_bytes(b"system-fixture")
        self.ubuntu.write_bytes(b"ubuntu-system-fixture")
        self.manifest = {
            "schemaVersion": 3,
            "distribution": "kai-skills-zsetup",
            "version": "1.2.3",
            "sourceCommit": "a" * 40,
            "sourceState": "committed",
            "minimumZsetupVersion": "0.6.0",
            "archiveFormat": "tar.gz",
            "artifacts": [
                self.artifact("skill", "kai-software", self.skill, ["kai-software"]),
                self.artifact("system", "istoreos", self.system, ["kai-software"]),
                self.artifact("system", "ubuntu", self.ubuntu, ["kai-software"]),
            ],
            "systems": [
                {
                    "id": "istoreos",
                    "platform": "istoreos",
                    "mode": "on-device",
                    "lockPath": "bundles/istoreos-all-on-device.json",
                    "members": [
                        {"id": "kai-software", "version": "1.2.3", "treeDigest": "sha256:" + "2" * 64}
                    ],
                },
                {
                    "id": "ubuntu",
                    "platform": "ubuntu",
                    "mode": "on-device",
                    "lockPath": "bundles/ubuntu-all-on-device.json",
                    "members": [
                        {"id": "kai-software", "version": "1.2.3", "treeDigest": "sha256:" + "2" * 64}
                    ],
                },
            ],
        }

    def artifact(self, kind, identity, path, members):
        return {
            "kind": kind,
            "id": identity,
            "version": "1.2.3",
            "path": path.relative_to(self.root).as_posix(),
            "size": path.stat().st_size,
            "expandedSize": 4096,
            "fileCount": 3,
            "sha256": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest(),
            "treeDigest": "sha256:" + "1" * 64,
            "root": "kai-" + kind + "-" + identity,
            "members": members,
        }

    def test_exact_single_and_system_layout_is_accepted(self):
        result = release.verify_manifest(self.root, self.manifest)
        self.assertEqual(result["version"], "1.2.3")

    def test_canonical_manifest_bytes_are_deterministic(self):
        first = release.canonical_json(self.manifest)
        second = release.canonical_json(json.loads(first))
        self.assertEqual(first, second)
        self.assertTrue(first.endswith(b"\n"))

    def test_unsafe_duplicate_and_wrong_integrity_records_are_rejected(self):
        mutations = []
        for path in ("/absolute.tar.gz", "skills/../escape.tar.gz", "skills\\escape.tar.gz"):
            changed = json.loads(json.dumps(self.manifest))
            changed["artifacts"][0]["path"] = path
            mutations.append(changed)
        duplicate = json.loads(json.dumps(self.manifest))
        duplicate["artifacts"].append(duplicate["artifacts"][0])
        mutations.append(duplicate)
        wrong_size = json.loads(json.dumps(self.manifest))
        wrong_size["artifacts"][0]["size"] += 1
        mutations.append(wrong_size)
        wrong_sha = json.loads(json.dumps(self.manifest))
        wrong_sha["artifacts"][0]["sha256"] = "sha256:" + "0" * 64
        mutations.append(wrong_sha)
        for changed in mutations:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                release.verify_manifest(self.root, changed)

    def test_system_members_must_match_the_system_artifact(self):
        changed = json.loads(json.dumps(self.manifest))
        changed["systems"][0]["members"].append(
            {"id": "extra", "version": "1.2.3", "treeDigest": "sha256:" + "3" * 64}
        )
        with self.assertRaisesRegex(ValueError, "system members"):
            release.verify_manifest(self.root, changed)

    def test_only_normative_tar_gzip_artifacts_are_accepted(self):
        for value in ("zip", "tar.zst", "tgz"):
            changed = json.loads(json.dumps(self.manifest))
            changed["archiveFormat"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.verify_manifest(self.root, changed)


if __name__ == "__main__":
    unittest.main()
