import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "components/system-packs/linux/skills/kai-network-quality"
SCRIPT = SKILL / "scripts/network.sh"


class NetworkQualityContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kai-fastnet-contract-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.calls = self.work / "calls"
        self.fastnet = self.work / "FastNet"
        self.fastnet.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" >> \"$FASTNET_CALL_LOG\"\n"
            "printf '%s\\n' '{\"schemaVersion\":1,\"command\":\"fixture\",\"status\":\"succeeded\",\"result\":{}}'\n"
        )
        self.fastnet.chmod(0o700)
        self.request = self.work / "request.json"
        self.request.write_text(json.dumps({
            "schemaVersion": 1,
            "profile": "software-install",
            "targets": [{"id": "artifact", "url": "https://example.test/file"}],
            "metadata": {"operationId": "operation-1"},
        }))
        self.request.chmod(0o600)
        self.env = {
            **os.environ,
            "FASTNET_BIN": str(self.fastnet),
            "FASTNET_CALL_LOG": str(self.calls),
        }

    def run_script(self, *args, confirmed=False, extra_env=None):
        env = dict(self.env)
        if confirmed:
            env["KAIPLUS_CONFIRMED"] = "1"
        if extra_env:
            env.update(extra_env)
        return subprocess.run(["sh", str(SCRIPT), *map(str, args)], env=env,
                              text=True, capture_output=True, timeout=10)

    def call_lines(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_inspect_and_validate_are_non_saturating_machine_calls(self):
        result = self.run_script("inspect")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), ["inspect", "--json"])
        self.calls.unlink()
        result = self.run_script("validate", self.request)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), ["agent", "validate", "--request", str(self.request), "--json"])

    def test_diagnose_is_blocked_before_confirmation(self):
        result = self.run_script("diagnose", self.request)
        self.assertEqual(result.returncode, 8)
        self.assertFalse(self.calls.exists())
        self.assertEqual(json.loads(result.stdout)["error"]["code"], "confirmation_required")

    def test_confirmed_diagnose_and_measure_use_ai_namespace(self):
        result = self.run_script("diagnose", self.request, confirmed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), ["agent", "execute", "--request", str(self.request), "--json"])
        self.calls.unlink()
        result = self.run_script("measure", "quick", confirmed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), ["measure", "quick", "--confirmed", "--json"])

    def test_lan_token_is_not_placed_in_wrapper_arguments(self):
        result = self.run_script("measure", "lan", "router.lan:3200", "4", confirmed=True,
                                 extra_env={"FASTNET_LAN_TOKEN": "secret-token"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("secret-token", self.call_lines())

    def test_monitor_requires_confirmation_and_uses_private_store_argument(self):
        store = self.work / "history.jsonl"
        blocked = self.run_script("monitor", self.request, store)
        self.assertEqual(blocked.returncode, 8)
        self.assertFalse(self.calls.exists())
        result = self.run_script("monitor", self.request, store, "10m", "2", confirmed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), [
            "monitor", "run", "--request", str(self.request), "--store", str(store),
            "--interval", "10m", "--count", "2", "--confirmed", "--jsonl",
        ])

    def test_expiring_lan_session_uses_token_file_not_token_value(self):
        token_file = self.work / "lan.token"
        token_file.write_text("secret-token\n")
        token_file.chmod(0o600)
        result = self.run_script("lan-test", "router.lan:3200", token_file, "4", "8", confirmed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call_lines(), [
            "lan", "test", "--addr", "router.lan:3200", "--token-file", str(token_file),
            "--parallel", "4", "--duration", "8", "--confirmed", "--json",
        ])
        self.assertNotIn("secret-token", self.call_lines())

    def test_software_and_acceleration_contracts_keep_owner_boundaries(self):
        software = (ROOT / "components/system-packs/common/skills/kai-software/SKILL.md").read_text()
        acceleration = (ROOT / "components/system-packs/common/skills/kai-download-acceleration/SKILL.md").read_text()
        handoff = (SKILL / "data/install-handoff.md").read_text()
        for phrase in ["401/403/404", "at most once", "validate"]:
            self.assertIn(phrase, software)
        self.assertIn("Broad WAN degradation", acceleration)
        self.assertIn("operationId", handoff)
        self.assertIn("do not retry installation", handoff)


if __name__ == "__main__":
    unittest.main()
