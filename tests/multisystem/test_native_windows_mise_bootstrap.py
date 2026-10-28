"""Exercise the public mise bootstrap on Windows, without a preinstalled mise."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'win32' and os.environ.get('KAI_NATIVE_MISE_BOOTSTRAP'),
                     'requires the native Windows mise bootstrap and trusted core')
class NativeWindowsMiseBootstrapTests(unittest.TestCase):
    def call(self, action, destination, extra=(), cache=True, engine='powershell.exe'):
        argv = [engine, '-NoProfile', '-NonInteractive', '-File',
                os.environ['KAI_NATIVE_MISE_BOOTSTRAP'], '-Action', action,
                '-Destination', str(destination), '-Core', os.environ['KAI_NATIVE_ZSETUP']]
        if cache and os.environ.get('KAI_NATIVE_MISE_ARCHIVE'):
            argv += ['-ArchiveCache', os.environ['KAI_NATIVE_MISE_ARCHIVE']]
        result = subprocess.run(argv + list(extra), capture_output=True, text=True,
                                encoding='utf-8', timeout=420)
        self.assertTrue(result.stdout.strip(), result.stderr)
        return result, json.loads(result.stdout)

    @unittest.skipUnless(os.environ.get('KAI_NATIVE_MISE_KSCLI'), 'requires an existing native ks-cli')
    def test_ks_cli_auto_downloads_and_installs_without_an_archive_cache(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            destination = Path(temporary) / 'online mise 中文 space' / 'mise.exe'
            result, receipt = self.call('Ensure', destination, cache=False,
                extra=('-KsCli', os.environ['KAI_NATIVE_MISE_KSCLI']))
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'installed')
            self.assertEqual(receipt['downloader'], 'ks-cli')
            self.assertEqual(receipt['download']['mode'], 'auto')
            self.assertEqual(receipt['download']['status'], 'ok')
            self.assertEqual(receipt['download']['bytes'], 33633582)
            self.assertIn(receipt['download']['selected'], ['origin', 'admin_proxy'])
            self.assertTrue((destination.parent / 'mise-shim.exe').is_file())
            version = subprocess.check_output([str(destination), '--version'], text=True).strip()
            self.assertTrue(version.startswith('2026.8.14 '), version)

    def test_plan_and_install_reuse_both_native_executables_in_unicode_directory(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            destination = Path(temporary) / 'mise 中文 space' / 'mise.exe'
            result, receipt = self.call('Plan', destination)
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'missing')
            self.assertFalse(destination.parent.exists())
            result, receipt = self.call('Ensure', destination)
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'installed')
            self.assertEqual(receipt['version'], '2026.8.14')
            self.assertTrue((destination.parent / 'mise-shim.exe').is_file())
            before = {f.name: hashlib.sha256(f.read_bytes()).hexdigest()
                      for f in destination.parent.iterdir() if f.is_file()}
            result, receipt = self.call('Ensure', destination, cache=False, engine='pwsh.exe',
                extra=('-KsCli', str(Path(temporary) / 'absent-ks-cli.exe')))
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'reused')
            self.assertEqual(before, {f.name: hashlib.sha256(f.read_bytes()).hexdigest()
                                     for f in destination.parent.iterdir() if f.is_file()})
            version = subprocess.check_output([str(destination), '--version'], text=True).strip()
            self.assertTrue(version.startswith('2026.8.14 '), version)
            shim = destination.with_name('mise-shim.exe')
            shim.write_bytes(b'changed owned companion')
            result, receipt = self.call('Ensure', destination)
            self.assertEqual(result.returncode, 17, receipt)
            self.assertEqual(shim.read_bytes(), b'changed owned companion')

    @unittest.skipUnless(os.environ.get('KAI_NATIVE_MISE_KSCLI'), 'requires an existing native ks-cli')
    def test_ks_cli_success_with_wrong_expected_hash_never_publishes_executables(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            helper = Path(os.environ['KAI_NATIVE_MISE_BOOTSTRAP'])
            lock = json.loads((helper.parent.parent / 'references/tools.lock.json').read_text())
            lock['mise']['artifacts']['windows-x64']['sha256'] = '0' * 64
            release_lock = Path(temporary) / 'wrong-sha.json'
            release_lock.write_text(json.dumps(lock), encoding='utf-8')
            destination = Path(temporary) / 'bin' / 'mise.exe'
            result, receipt = self.call('Ensure', destination, cache=False,
                extra=('-KsCli', os.environ['KAI_NATIVE_MISE_KSCLI'], '-ReleaseLock', str(release_lock)))
            self.assertEqual(result.returncode, 14, receipt)
            self.assertEqual(receipt['download']['status'], 'ok')
            self.assertFalse(destination.exists())
            self.assertEqual(list(destination.parent.iterdir()), [])

    def test_foreign_companion_is_preserved_before_downloading(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            destination = Path(temporary) / 'mise.exe'
            shim = destination.with_name('mise-shim.exe')
            shim.write_bytes(b'foreign companion: preserve me')
            result, receipt = self.call('Ensure', destination, cache=False)
            self.assertEqual(result.returncode, 17, receipt)
            self.assertEqual(shim.read_bytes(), b'foreign companion: preserve me')
            self.assertFalse(destination.exists())
            self.assertEqual(sorted(p.name for p in Path(temporary).iterdir()), ['mise-shim.exe'])

    def test_corrupt_archive_is_rejected_without_publishing_or_retaining_stage(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            archive = Path(temporary) / 'corrupt.zip'
            archive.write_bytes(b'invalid archive')
            destination = Path(temporary) / 'bin' / 'mise.exe'
            result, receipt = self.call('Ensure', destination, extra=('-ArchiveCache', str(archive)), cache=False)
            self.assertEqual(result.returncode, 14, receipt)
            self.assertFalse(destination.exists())
            self.assertEqual(list(destination.parent.iterdir()), [])

    def test_public_git_bash_entry_installs_and_reuses_without_global_path_changes(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as temporary:
            home = Path(temporary) / 'home 中文 space'
            home.mkdir()
            script = str(Path(os.environ['KAI_NATIVE_MISE_BOOTSTRAP']).with_name('tool.sh'))
            body = r'''set -eu
export HOME="$(cygpath -u "$1")" KAI_PLATFORM=windows
export KAI_JQ_BIN="$(cygpath -u "$2")" KAI_ZSETUP_BIN="$(cygpath -u "$3")"
system="$(cygpath -u "$SYSTEMROOT")"
export PATH="/usr/bin:/bin:$system/System32/WindowsPowerShell/v1.0:$system/System32"
unset KAI_TRUSTED_TOOL_PATH
exec bash "$(cygpath -u "$4")" "$5" mise
'''
            def call(action):
                env = {**os.environ}
                if env.get('KAI_NATIVE_MISE_ARCHIVE'):
                    env['KAI_MISE_ARCHIVE_CACHE'] = env['KAI_NATIVE_MISE_ARCHIVE']
                result = subprocess.run([os.environ['KAI_NATIVE_BASH'], '--noprofile', '--norc', '-c',
                    body, 'kai-native', str(home), os.environ['KAI_NATIVE_JQ'],
                    os.environ['KAI_NATIVE_ZSETUP'], script, action],
                    capture_output=True, text=True, encoding='utf-8', env=env, timeout=420)
                self.assertTrue(result.stdout.strip(), result.stderr)
                return result, json.loads(result.stdout)
            before_path = os.environ['PATH']
            result, receipt = call('plan')
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'missing')
            self.assertFalse((home / '.local').exists())
            result, receipt = call('ensure')
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'installed')
            self.assertTrue((home / '.local/bin/mise.exe').is_file())
            result, receipt = call('ensure')
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'reused')
            self.assertEqual(receipt['owner'], 'kai-bootstrap')
            self.assertEqual(os.environ['PATH'], before_path)
            shim = home / '.local/bin/mise-shim.exe'
            shim.write_bytes(b'changed owned companion')
            result, receipt = call('ensure')
            self.assertEqual(result.returncode, 17, receipt)
            self.assertEqual(receipt['status'], 'conflict')
            self.assertEqual(shim.read_bytes(), b'changed owned companion')


if __name__ == '__main__':
    unittest.main()
