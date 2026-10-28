"""Native public software entry, with a task-prepared official SDK and CONNECT endpoint."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from urllib.parse import urlsplit, urlunsplit


@unittest.skipUnless(sys.platform == 'win32' and os.environ.get('KAI_NATIVE_WINGET_ACCEL'),
                     'requires native Windows, pinned SDK and a trusted KSpeeder CONNECT endpoint')
class NativeWinGetAccelerationTests(unittest.TestCase):
    def test_invalid_proxy_auth_returns_a_structured_failure(self):
        helper = (Path(os.environ['KAI_NATIVE_PRESET']) / 'skills/kai-software/scripts/software.sh').as_posix()
        proxy = urlsplit(os.environ['KSPEEDER_WINGET_PROXY'])
        invalid = urlunsplit((proxy.scheme, 'invalid:invalid-test-password@' + proxy.netloc.split('@')[-1],
                              proxy.path, proxy.query, proxy.fragment))
        result = subprocess.run([os.environ['KAI_NATIVE_BASH'], '--noprofile', '--norc', '-c',
            'exec bash "$@"', 'kai-winget-native', helper, 'info', 'winget:Git.Git'],
            env={**os.environ, 'KAI_PLATFORM':'windows', 'KAI_WINGET_ACCELERATION':'required',
                 'KSPEEDER_WINGET_PROXY':invalid}, capture_output=True, text=True, encoding='utf-8', timeout=40)
        self.assertNotEqual(result.returncode, 0)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(receipt['category'], 'acceleration-unavailable')
        self.assertNotIn('availableVersion', receipt)

    def test_official_catalog_returns_real_versions_via_kspeeder(self):
        helper = (Path(os.environ['KAI_NATIVE_PRESET']) / 'skills/kai-software/scripts/software.sh').as_posix()
        package = os.environ.get('KAI_NATIVE_WINGET_ID', 'Git.Git')
        result = subprocess.run([os.environ['KAI_NATIVE_BASH'], '--noprofile', '--norc', '-c',
            'exec bash "$@"', 'kai-winget-native', helper, 'info', 'winget:' + package],
            env={**os.environ, 'KAI_PLATFORM':'windows', 'KAI_WINGET_ACCELERATION':'required'},
            capture_output=True, text=True, encoding='utf-8', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['id'], 'winget:' + package)
        self.assertEqual(receipt['source'], 'winget')
        self.assertTrue(receipt['availableVersions'])
        self.assertIn(receipt['availableVersion'], receipt['availableVersions'])
        self.assertEqual(receipt['acceleration']['transport'], 'kspeeder-connect')
        self.assertFalse(receipt['acceleration']['systemProxyChanged'])


if __name__ == '__main__':
    unittest.main()
