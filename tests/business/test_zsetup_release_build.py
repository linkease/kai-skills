import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "zsetup_release_build", ROOT / "tools/release/zsetup_release.py"
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ZsetupReleaseBuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="kai zsetup build ")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = Path(cls.temporary.name)
        cls.source = cls.work / "source"
        cls.source.mkdir()
        for name in ("skills", "bundles"):
            shutil.copytree(ROOT / name, cls.source / name)
        for name in (
            "business-catalog.json",
            "catalog.json",
            "install.sh",
            "install.ps1",
            "tools/install-business.sh",
            "tools/release/business_release.py",
            "tools/release/zsetup_release.py",
            "docs/architecture/kai-skills-zsetup-contract.json",
        ):
            target = cls.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for args in (
            ["init", "-q"],
            ["add", "."],
            ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
             "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"],
        ):
            subprocess.run(["git", "-C", str(cls.source), *args], check=True, capture_output=True)
        cls.first = cls.work / "first"
        cls.second = cls.work / "second"
        cls.manifest = release.build(cls.source, cls.first)
        release.build(cls.source, cls.second)

    def test_build_has_one_artifact_per_skill_and_three_locked_systems(self):
        catalog = json.loads((self.source / "business-catalog.json").read_text())
        artifacts = self.manifest["artifacts"]
        self.assertEqual(len(artifacts), len(catalog["skills"]) + 3)
        self.assertEqual(
            {(item["kind"], item["id"]) for item in artifacts if item["kind"] == "system"},
            {("system", "istoreos"), ("system", "ubuntu"), ("system", "windows")},
        )
        self.assertEqual(
            {item["id"] for item in artifacts if item["kind"] == "skill"},
            {item["id"] for item in catalog["skills"]},
        )
        self.assertTrue(all(item["expandedSize"] > 0 and item["fileCount"] > 0
                            for item in artifacts))

    def test_two_builds_are_byte_identical_and_verify(self):
        self.assertEqual(release.file_digests(self.first), release.file_digests(self.second))
        self.assertEqual(release.verify_release(self.first)["version"], self.manifest["version"])

    def test_single_skill_is_a_self_contained_managed_distribution(self):
        artifact = next(item for item in self.manifest["artifacts"]
                        if item["kind"] == "skill" and item["id"] == "kai-software")
        root = release.extract_for_test(self.first, artifact)
        self.addCleanup(shutil.rmtree, root.parent)
        self.assertTrue((root / "install.sh").is_file())
        self.assertTrue((root / "install.ps1").is_file())
        self.assertTrue((root / "tools/install-business.sh").is_file())
        self.assertEqual(artifact["fileCount"], len(list(release.tree_members(root))))
        self.assertEqual(artifact["expandedSize"], sum(path.stat().st_size for path in release.tree_members(root)))
        catalog = json.loads((root / "business-catalog.json").read_text())
        self.assertEqual([item["id"] for item in catalog["skills"]], ["kai-software"])
        self.assertEqual(list((root / "skills").glob("*/SKILL.md")),
                         [root / "skills/kai-software/SKILL.md"])

    def test_system_members_are_exactly_the_lock_members(self):
        for identity in ("istoreos", "ubuntu", "windows"):
            artifact = next(item for item in self.manifest["artifacts"]
                            if item["kind"] == "system" and item["id"] == identity)
            root = release.extract_for_test(self.first, artifact)
            self.addCleanup(shutil.rmtree, root.parent)
            lock = json.loads((root / "bundles" / f"{identity}-all-on-device.json").read_text())
            self.assertEqual(artifact["members"], [member["id"] for member in lock["members"]])
            self.assertEqual(
                {path.parent.name for path in (root / "skills").glob("*/SKILL.md")},
                set(artifact["members"]),
            )

    def test_existing_output_and_tampering_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "new directory"):
            release.build(self.source, self.first)
        changed = self.work / "changed"
        shutil.copytree(self.first, changed)
        path = next(changed.glob("skills/*.tar.gz"))
        path.write_bytes(path.read_bytes() + b"tampered")
        with self.assertRaises(ValueError):
            release.verify_release(changed)


if __name__ == "__main__":
    unittest.main()
