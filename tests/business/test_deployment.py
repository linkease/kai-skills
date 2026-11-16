import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.parse


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT.parent / "zsetup-scripts"
sys.path.insert(0, str(ROOT / "tools/release"))
import deployment


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class DeploymentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="kai deployment fixture ")
        cls.work = Path(cls.temporary.name)
        cls.freeze = cls.work / "freeze"
        subprocess.run([
            sys.executable, "-B", str(ROOT / "tools/release/freeze.py"), "build",
            "--reasonix-root", str(ROOT.parent / "reasonix-kai"),
            "--output", str(cls.freeze), "--version", "1.2.6-test",
            "--allow-dirty-fixture",
        ], check=True)
        release = cls.freeze / "zsetup"
        installer = cls.work / "installer.sh"
        entries = cls.work / "entries"
        channel = cls.work / "channel-install.sh"
        subprocess.run([
            sys.executable, "-B", str(SCRIPTS / "kai-skills/build.py"),
            "--release", str(release), "--output", str(installer),
            "--freeze-manifest", str(cls.freeze / "freeze-manifest.json"),
            "--allow-fixture-freeze", "--entrypoints-dir", str(entries),
        ], check=True)
        subprocess.run([
            sys.executable, "-B", str(SCRIPTS / "kai-skills/build.py"),
            "--channel-only", "--channel-entrypoint", str(channel),
        ], check=True)
        cls.publication = cls.work / "publication"
        subprocess.run([
            sys.executable, "-B", str(ROOT / "tools/release/zsetup_publication.py"), "build",
            "--release", str(release), "--installer", str(installer),
            "--entrypoints", str(entries), "--channel-entrypoint", str(channel),
            "--freeze-manifest", str(cls.freeze / "freeze-manifest.json"),
            "--allow-fixture-freeze", "--output", str(cls.publication),
        ], check=True)
        cls.package = cls.work / "deployment"
        deployment.build(cls.freeze, cls.publication, cls.package, allow_fixture_freeze=True)
        cls.manifest = deployment.verify(cls.package)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(prefix="kai deployment case ", dir=self.work))
        self.root = self.case / "public_html/binary/kai"

    def tearDown(self):
        shutil.rmtree(self.case)

    def fake_opener(self, corrupt_host=None):
        def open_url(url, timeout):
            self.assertEqual(timeout, 60)
            parsed = urllib.parse.urlsplit(url)
            prefix = "/binary/kai/"
            self.assertTrue(parsed.path.startswith(prefix))
            relative = urllib.parse.unquote(parsed.path[len(prefix):])
            body = (self.root / relative).read_bytes()
            if parsed.netloc == corrupt_host:
                body = body + b"corrupt"
            return Response(body)
        return open_url

    def seed_pointers(self):
        seeded = {
            "kai-skills/stable": b"previous-version\n",
            "defaults/snapshot-v2/index.json": b'{"previous":true}\n',
        }
        for relative, body in seeded.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
        return seeded

    def staged_evidence(self):
        evidence = self.case / "staged-readback.json"
        deployment.readback(
            self.package, self.root, deployment.PUBLIC_BASES, "staged", evidence,
            opener=self.fake_opener(),
        )
        return evidence

    def test_package_is_freeze_bound_and_has_only_kai_destinations(self):
        self.assertEqual(self.manifest["publicBases"], deployment.PUBLIC_BASES)
        self.assertEqual(
            self.manifest["freezeReleaseId"],
            json.loads((self.freeze / "freeze-manifest.json").read_text())["releaseId"],
        )
        destinations = [item["destination"] for item in self.manifest["files"]]
        self.assertFalse(any(item.startswith("zsetup/") for item in destinations))
        self.assertIn("kai-skills/setup.sh", destinations)
        self.assertIn("defaults/snapshot-v2/index.json", destinations)
        self.assertEqual(self.manifest["activationOrder"][-2:], [
            "kai-skills/stable", "defaults/snapshot-v2/index.json",
        ])

    def test_stage_activate_readback_and_rollback_are_transactional(self):
        seeded = self.seed_pointers()
        deployment.stage(self.package, self.root)
        for relative, body in seeded.items():
            self.assertEqual((self.root / relative).read_bytes(), body)
        evidence = self.staged_evidence()
        deployment.activate(self.package, self.root, evidence)
        deployment.verify_origin(self.package, self.root, "activated")
        activated = self.case / "activated-readback.json"
        result = deployment.readback(
            self.package, self.root, deployment.PUBLIC_BASES, "activated", activated,
            opener=self.fake_opener(),
        )
        self.assertEqual(result["phase"], "activated")
        deployment.rollback(self.package, self.root)
        for relative, body in seeded.items():
            self.assertEqual((self.root / relative).read_bytes(), body)
        for item in self.manifest["files"]:
            if item["kind"] == "pointers" and item["destination"] not in seeded:
                self.assertFalse((self.root / item["destination"]).exists())
            if item["kind"] == "immutable":
                self.assertTrue((self.root / item["destination"]).is_file())

    def test_activation_interruption_restores_every_pointer(self):
        seeded = self.seed_pointers()
        deployment.stage(self.package, self.root)
        evidence = self.staged_evidence()
        with self.assertRaisesRegex(OSError, "injected activation interruption"):
            deployment.activate(self.package, self.root, evidence, fail_after=2)
        for relative, body in seeded.items():
            self.assertEqual((self.root / relative).read_bytes(), body)
        for item in self.manifest["files"]:
            if item["kind"] == "pointers" and item["destination"] not in seeded:
                self.assertFalse((self.root / item["destination"]).exists())

    def test_bad_cdn_readback_cannot_create_activation_evidence(self):
        deployment.stage(self.package, self.root)
        evidence = self.case / "bad-readback.json"
        with self.assertRaisesRegex(ValueError, "public readback mismatch"):
            deployment.readback(
                self.package, self.root, deployment.PUBLIC_BASES, "staged", evidence,
                opener=self.fake_opener("fw20.koolcenter.com"),
            )
        self.assertFalse(evidence.exists())

    def test_immutable_conflict_and_out_of_order_rollback_are_rejected(self):
        immutable = next(item for item in self.manifest["files"] if item["kind"] == "immutable")
        conflict = self.root / immutable["destination"]
        conflict.parent.mkdir(parents=True, exist_ok=True)
        conflict.write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "immutable destination conflict"):
            deployment.stage(self.package, self.root)

        shutil.rmtree(self.root)
        deployment.stage(self.package, self.root)
        deployment.activate(self.package, self.root, self.staged_evidence())
        pointer = self.root / self.manifest["activationOrder"][0]
        pointer.write_bytes(b"newer rollout")
        with self.assertRaisesRegex(ValueError, "refusing out-of-order rollback"):
            deployment.rollback(self.package, self.root)


if __name__ == "__main__":
    unittest.main()
