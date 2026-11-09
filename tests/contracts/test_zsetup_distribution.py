#!/usr/bin/env python3
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "docs/architecture/kai-skills-zsetup-contract.json"


class ZsetupDistributionContractTest(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    def test_public_roots_and_local_publish_root_are_frozen(self):
        self.assertEqual(
            self.contract["sources"],
            {
                "primary": [
                    "https://dl.istoreos.com/binary/kai/kai-skills",
                    "https://fw.d4ctech.com/binary/kai/kai-skills",
                    "https://fw20.koolcenter.com/binary/kai/kai-skills",
                ],
                "fallback": "https://fw.koolcenter.com/binary/kai/kai-skills",
                "fallbackPublishRoot": "/mnt/sata3-1/istore-data/public_html/binary/kai/kai-skills",
            },
        )

    def test_one_application_dispatches_all_installable_units(self):
        self.assertEqual(self.contract["schemaVersion"], 3)
        self.assertEqual(self.contract["application"], "kai-skills")
        self.assertEqual(self.contract["minimumZsetupVersion"], "0.6.0")
        self.assertEqual(self.contract["selectors"]["skill"], "--skill")
        self.assertEqual(self.contract["selectors"]["system"], "--system")
        self.assertEqual(self.contract["selectors"]["defaultSystemMode"], "on-device")
        self.assertEqual(set(self.contract["systems"]), {"istoreos", "ubuntu"})

    def test_public_channel_hides_consumer_and_scope_by_default(self):
        channel = self.contract["channelInterface"]
        self.assertEqual(channel["singleSkill"], "SKILL_ID")
        self.assertEqual(channel["currentSystem"], "all")
        self.assertEqual(channel["defaultConsumer"], "codex")
        self.assertEqual(channel["defaultScope"], "user")
        self.assertEqual(channel["defaultDestination"], "~/.agents/skills")
        self.assertEqual(channel["autoDetectedSystems"], {
            "ubuntu": "ubuntu",
            "istoreos": "istoreos",
            "openwrt": "istoreos",
            "lede": "istoreos",
        })
        self.assertTrue(channel["helpBeforeBootstrap"])
        self.assertTrue(channel["advancedSelectorsRetained"])

    def test_consumer_scope_destinations_are_explicit(self):
        consumers = self.contract["consumers"]
        self.assertEqual(consumers["codex"]["user"], "~/.agents/skills")
        self.assertEqual(consumers["codex"]["project"], ".agents/skills")
        self.assertEqual(consumers["claude"]["user"], "~/.claude/skills")
        self.assertEqual(consumers["claude"]["project"], ".claude/skills")
        self.assertEqual(consumers["opencode"]["user"], "~/.config/opencode/skills")
        self.assertEqual(consumers["opencode"]["project"], ".opencode/skills")

    def test_public_system_names_map_to_detected_runtime_os(self):
        self.assertEqual(self.contract["runtimeSystemSelectors"], {
            "istoreos": "openwrt",
            "ubuntu": "ubuntu",
        })

    def test_runtime_dependency_boundary_is_machine_readable(self):
        dependencies = self.contract["runtimeDependencies"]
        self.assertEqual(dependencies["required"], ["zsetup", "/bin/sh", "jq", "basic-file-tools"])
        self.assertEqual(
            set(dependencies["forbidden"]),
            {
                "git", "github", "gh", "node", "npm", "npx", "ks-cli", "kspeeder",
                "curl", "wget", "tar", "gzip", "sha256sum", "shasum",
            },
        )
        self.assertEqual(
            dependencies["zsetupOwned"],
            ["https-download", "size-verification", "sha256-verification", "safe-archive-extraction"],
        )
        bootstrap = self.contract["bootstrapDependencies"]
        self.assertEqual(bootstrap["required"], ["/bin/sh", "curl-or-wget"])
        self.assertEqual(set(bootstrap["optionalIntegrity"]), {"sha256sum", "openssl"})
        self.assertFalse(bootstrap["modifiesShellProfile"])

    def test_release_paths_are_relative_and_immutable(self):
        layout = self.contract["releaseLayout"]
        self.assertEqual(layout["installer"], "releases/{release}/kai-skills-install.sh")
        self.assertEqual(layout["manifest"], "releases/{release}/release-manifest.json")
        self.assertEqual(layout["skill"], "releases/{release}/skills/{id}.{archiveExtension}")
        self.assertEqual(layout["system"], "releases/{release}/systems/{id}.{archiveExtension}")
        self.assertTrue(layout["immutableReleases"])
        for value in layout.values():
            if isinstance(value, str):
                self.assertFalse(value.startswith("/"))
                self.assertNotIn("..", Path(value).parts)

    def test_one_version_free_public_channel_entry_is_frozen(self):
        self.assertEqual(self.contract["releaseLayout"]["channelEntry"], "setup.sh")
        self.assertEqual(self.contract["releaseLayout"]["channelAliases"], ["install.sh"])


if __name__ == "__main__":
    unittest.main()
