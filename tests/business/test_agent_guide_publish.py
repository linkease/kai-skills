import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("guide_publish", Path(__file__).resolve().parents[2] / "tools/publish-agent-guide.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)
RUN = subprocess.run


class GuidePublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "kai-skills"
        self.root.mkdir()
        self.source = Path(self.temp.name) / "guide.md"
        self.source.write_text("# KAI Skills\nnew guide\n")

    def publish(self):
        def local_ssh(command, **kwargs):
            self.assertIn("StrictHostKeyChecking=yes", command)
            return RUN(["sh", "-c", command[-1]], **kwargs)
        def readback(*args, **kwargs):
            return io.BytesIO((self.root / "agent-install.md").read_bytes())
        with patch.object(sys, "argv", ["publish", "publish", "--source", str(self.source), "--host", "example", "--root", str(self.root)]), patch.object(module.subprocess, "run", side_effect=local_ssh), patch.object(module.urllib.request, "urlopen", side_effect=readback), contextlib.redirect_stdout(io.StringIO()):
            module.main()

    def test_publish_retains_old_content_and_retries_idempotently(self):
        old = b"# KAI Skills\nold guide\n"
        (self.root / "agent-install.md").write_bytes(old)
        self.publish()
        self.publish()
        self.assertEqual((self.root / "agent-install.md").read_bytes(), self.source.read_bytes())
        self.assertEqual((self.root / "guides" / (hashlib.sha256(old).hexdigest() + ".md")).read_bytes(), old)
        self.assertFalse((self.root / ".agent-guide-lock").exists())
        self.assertEqual(list(self.root.glob(".agent-install.*")), [])

    def test_concurrent_publish_does_not_replace_document(self):
        (self.root / ".agent-guide-lock").mkdir()
        (self.root / "agent-install.md").write_bytes(b"old")
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual((self.root / "agent-install.md").read_bytes(), b"old")
        self.assertTrue((self.root / ".agent-guide-lock").exists())

    def test_conflicting_history_aborts_without_replacing_current(self):
        (self.root / "agent-install.md").write_bytes(b"old")
        (self.root / "guides").mkdir()
        digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        (self.root / "guides" / (digest + ".md")).write_bytes(b"corrupted")
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual((self.root / "agent-install.md").read_bytes(), b"old")
        self.assertFalse((self.root / ".agent-guide-lock").exists())


if __name__ == "__main__":
    unittest.main()
