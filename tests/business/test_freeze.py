import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("kai_release_freeze", ROOT / "tools/release/freeze.py")
freeze = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(freeze)


def commit(root):
    subprocess.run(["git", "-C", str(root), "init", "-q"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(root), "remote", "add", "origin",
                    "https://example.invalid/" + root.name + ".git"], check=True, capture_output=True)
    for args in (
        ["add", "."],
        ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
         "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"],
    ):
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


class FreezeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="kai freeze test ")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = Path(cls.temporary.name)
        cls.kai = cls.work / "kai-skills"
        shutil.copytree(ROOT, cls.kai, ignore=shutil.ignore_patterns(".git", "__pycache__", "dist"))
        cls.kai_commit = commit(cls.kai)
        cls.reasonix = cls.work / "reasonix-kai"
        for source in (ROOT.parent / "reasonix-kai" / "VERSION",):
            target = cls.reasonix / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        shutil.copytree(ROOT.parent / "reasonix-kai" / "kaiplus-defaults", cls.reasonix / "kaiplus-defaults")
        registry = cls.reasonix / "internal/systempack/builtin/registry.json"
        registry.parent.mkdir(parents=True)
        shutil.copyfile(ROOT.parent / "reasonix-kai" / "internal/systempack/builtin/registry.json", registry)
        cls.reasonix_commit = commit(cls.reasonix)
        cls.output = cls.work / "freeze"
        cls.manifest = freeze.build(
            cls.kai, cls.reasonix, cls.output, "1.2.5-test",
            expected_kai_commit=cls.kai_commit,
            expected_reasonix_commit=cls.reasonix_commit,
        )

    def test_freeze_builds_twice_and_binds_both_distributions(self):
        output = self.output
        manifest = self.manifest
        self.assertEqual(manifest["sourcePolicy"], "clean-committed")
        self.assertEqual(manifest["sources"]["kai-skills"]["commit"], self.kai_commit)
        self.assertTrue(manifest["releaseId"].startswith("sha256:"))
        self.assertEqual(freeze.verify(output)["releaseId"], manifest["releaseId"])
        self.assertEqual(
            manifest["identities"]["capabilityCatalogSHA256"],
            freeze.sha256(output / "kaiplus/snapshot/capability-catalog.json"),
        )
        zsetup_manifest = json.loads((output / "zsetup/release-manifest.json").read_text())
        self.assertEqual(zsetup_manifest["sourceCommit"], self.kai_commit)

    def test_dirty_source_wrong_commit_and_tampering_are_rejected(self):
        dirty = self.kai / "untracked-freeze-input"
        dirty.write_text("dirty")
        try:
            with self.assertRaisesRegex(ValueError, "clean committed"):
                freeze.build(self.kai, self.reasonix, self.work / "dirty", "1.2.5-test")
        finally:
            dirty.unlink()
        with self.assertRaisesRegex(ValueError, "differs from review"):
            freeze.build(self.kai, self.reasonix, self.work / "wrong", "1.2.5-test",
                         expected_kai_commit="0" * 40)
        changed = self.work / "changed"
        shutil.copytree(self.output, changed)
        archive = next((changed / "zsetup/skills").glob("*.tar.gz"))
        archive.write_bytes(archive.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "file set or digest"):
            freeze.verify(changed)


if __name__ == "__main__":
    unittest.main()
