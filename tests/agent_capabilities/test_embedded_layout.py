"""Execute capabilities from KaiPlus layers, distinct from flattened packages."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / 'components/system-packs'

class EmbeddedLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.defaults = self.root / 'kaiplus-defaults'
        shutil.copytree(PACKS / 'common/skills', self.defaults / 'system-packs/common/skills')
        for platform in ('istoreos', 'macos', 'windows'):
            shutil.copytree(PACKS / platform / 'skills', self.defaults / 'profiles' / platform / 'skills')

    def test_all_cross_layer_dependencies_resolve_in_embedded_layout(self):
        count = 0
        for platform in ('istoreos', 'macos', 'windows'):
            for source in (PACKS / platform / 'skills').rglob('*'):
                if source.suffix not in ('.sh', '.ps1') or not source.is_file():
                    continue
                text = source.read_text()
                if '../../../../common/' not in text:
                    continue
                installed = self.defaults / 'profiles' / platform / 'skills' / source.relative_to(PACKS / platform / 'skills')
                relatives = re.findall(r'((?:\.\./){2,}[^"\'\s;}]+)', text)
                candidates = [(installed.parent / relative).resolve() for relative in relatives]
                self.assertTrue(any(path.exists() for path in candidates), str(source.relative_to(ROOT)))
                count += 1
        self.assertEqual(count, 16)

    def test_embedded_service_query_uses_shared_library(self):
        target = self.root / 'target'
        init = target / 'etc/init.d/example'
        init.parent.mkdir(parents=True)
        init.write_text('#!/bin/sh\nexec /usr/bin/unfamiliar-wrapper\n')
        script = self.defaults / 'profiles/istoreos/skills/istoreos-service-manager/scripts/inspect.sh'
        before = init.read_bytes()
        result = subprocess.run(['sh', str(script), '--target-id', 'embedded-fixture', '--service', 'example', '--sections', 'init'],
                                env={**os.environ, 'ISTOREOS_ROOT': str(target)}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value['operationStatus'], 'succeeded')
        self.assertEqual(value['targetId'], 'embedded-fixture')
        self.assertTrue(value['readOnly'])
        self.assertIn('unfamiliar-wrapper', value['facts']['initScript']['content'])
        self.assertEqual(init.read_bytes(), before)

    def test_embedded_storage_returns_observation_without_selecting_path(self):
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        df = bin_dir / 'df'
        df.write_text('#!/bin/sh\nprintf "Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/example 100 20 80 20%% /mnt/example\\n"\n')
        df.chmod(0o700)
        script = self.defaults / 'profiles/istoreos/skills/istoreos-storage-path/scripts/detect.sh'
        result = subprocess.run(['sh', str(script)], env={**os.environ, 'ZSETUP_TASK_TARGET_ID': 'embedded-fixture', 'PATH': str(bin_dir)+os.pathsep+os.environ['PATH']},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value['operationStatus'], 'succeeded')
        self.assertEqual(value['targetId'], 'embedded-fixture')
        self.assertTrue(value['readOnly'])
        self.assertEqual(value['facts']['observation']['source'], 'filesystems')
        self.assertIn('/mnt/example', value['facts']['observation']['output'])
        self.assertNotIn('recommendedPath', value['facts'])
