import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'components/system-packs/common/skills/kai-dev-environment/scripts/runtime.sh'
DIAGNOSE = CLI.with_name('diagnose.sh')


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai runtime 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / 'bin'; self.bin.mkdir()
        self.log = self.work / 'calls'
        self.env = {**os.environ, 'HOME': str(self.work), 'KAI_PLATFORM': 'ubuntu',
                    'PATH': str(self.bin) + ':' + os.environ['PATH'], 'TEST_LOG': str(self.log)}
        mise = self.bin / 'mise'
        mise.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
where) exit 4 ;;
latest) echo 3.13.7 ;;
install) exit 15 ;;
*) exit 29 ;;
esac
'''); mise.chmod(0o700)

    def call(self, *args, **env):
        return subprocess.run(['bash', str(CLI), *args], env={**self.env, **env},
                              capture_output=True, text=True, timeout=10)

    def test_missing_probe_does_not_install_or_select(self):
        p = self.call('probe', 'python', '3.13.7')
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'runtime-not-installed')
        self.assertEqual(self.log.read_text().splitlines(), ['where python@3.13.7'])

    def test_versioned_python_entry_inside_selected_sdk_is_usable_without_aliases(self):
        sdk=self.work/'SDK';(sdk/'bin').mkdir(parents=True)
        version=sys.version.split()[0];entry=sdk/'bin'/('python'+'.'.join(version.split('.')[:2]))
        shutil.copy2(Path(sys.executable).resolve(),entry)
        (sdk/'lib').symlink_to(Path(sys.base_prefix)/'lib',target_is_directory=True)
        mise=self.bin/'mise'
        mise.write_text('#!/bin/bash\ncase "$1" in where) printf "%s\\n" "$TEST_SDK";; exec) shift 3;exec "$@";; *) exit 29;; esac\n')
        p=self.call('verify','python',version,TEST_SDK=str(sdk))
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        p=self.call('exec','python',version,'--','python','-c','import sys;print(sys.executable)',TEST_SDK=str(sdk))
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(Path(p.stdout.strip()).resolve(),entry)

    def test_resolution_is_read_only_and_returns_a_complete_version(self):
        p = self.call('resolve', 'python', '3.13')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['resolvedVersion'], '3.13.7')
        self.assertEqual(self.log.read_text().splitlines(), ['latest python@3.13'])

    def test_explicit_acceleration_uses_the_client_and_preserves_failure(self):
        client = self.bin / 'ks-cli'
        client.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_LOG"\nexit 37\n'); client.chmod(0o700)
        p = self.call('install', 'python', '3.13.7', KAI_RUNTIME_ACCELERATION='required')
        self.assertEqual(p.returncode, 37, p.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ['mise install python@3.13.7'])

    def test_public_go_git_metadata_uses_read_only_client_plan_without_global_git_changes(self):
        config = self.work / '.gitconfig'; config.write_text('# keep-global\n')
        client = self.bin / 'ks-cli'
        client.write_text('''#!/bin/bash
case "$1" in
doctor) echo '{"schema_version":1,"tool":"git","overall":"pass"}' ;;
--explain) echo '{"schema_version":1,"command":["git","ls-remote"],"environment":{"GIT_CONFIG_COUNT":"1","GIT_CONFIG_KEY_0":"url.https://gateway.invalid/.insteadOf","GIT_CONFIG_VALUE_0":"https://github.com/"}}' ;;
mise) printf '%s\\n' "${GIT_CONFIG_COUNT:-missing}" "${GIT_CONFIG_KEY_0:-missing}" >> "$TEST_LOG"; exit 37 ;;
*) exit 29 ;;
esac
'''); client.chmod(0o700)
        p = self.call('install','go','1.24.1',KAI_RUNTIME_ACCELERATION='required',KAI_GO_GIT_METADATA='required')
        self.assertEqual(p.returncode,37,p.stderr)
        self.assertEqual(self.log.read_text().splitlines(),['1','url.https://gateway.invalid/.insteadOf'])
        self.assertEqual(config.read_text(),'# keep-global\n')

    def test_install_failure_keeps_exit_code_and_does_not_select_version(self):
        p = self.call('install', 'python', '3.13.7')
        self.assertEqual(p.returncode, 15, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'installation-failed')
        self.assertEqual(self.log.read_text().splitlines(), ['install python@3.13.7'])

    def test_invalid_version_or_scope_never_calls_mise(self):
        for args in [('install', 'python', 'latest'), ('install', 'node', '22.14.0', 'everything'),
                     ('install', 'go', '1.24.1; touch nope')]:
            p = self.call(*args)
            self.assertEqual(p.returncode, 2, p.stderr)
        self.assertFalse(self.log.exists())

    def test_verification_rejects_system_python_outside_selected_sdk(self):
        sdk = self.work / 'sdk'; sdk.mkdir()
        mise = self.bin / 'mise'
        mise.write_text('''#!/bin/bash
set -eu
case "$1" in
where) printf '%s\\n' "$TEST_SDK" ;;
exec) shift 3; exec "$@" ;;
*) exit 29 ;;
esac
''')
        p = self.call('verify', 'python', '3.13.7', TEST_SDK=str(sdk))
        self.assertEqual(p.returncode, 11, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'runtime-verification-failed')

    def test_failed_verification_does_not_change_global_selection(self):
        sdk = self.work / 'sdk'; sdk.mkdir()
        (self.bin / 'mise').write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
install) exit 0 ;;
where) printf '%s\\n' "$TEST_SDK" ;;
exec) shift 3; exec "$@" ;;
use) exit 29 ;;
*) exit 29 ;;
esac
''')
        p = self.call('install', 'python', '3.13.7', 'global', TEST_SDK=str(sdk))
        self.assertEqual(p.returncode, 11, p.stderr)
        self.assertFalse(any(line.startswith('use ') for line in self.log.read_text().splitlines()))

    def test_each_istore_call_enters_the_real_adapter_with_scoped_home(self):
        system = self.work / 'system'; (system / 'etc').mkdir(parents=True)
        (system / 'etc/openwrt_release').touch()
        runtime_home = self.work / 'runtime'; runtime_home.mkdir()
        uci = self.bin / 'uci'
        uci.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_RUNTIME_HOME"\n'); uci.chmod(0o700)
        integration = self.bin / 'mise-exec'
        integration.write_text('''#!/bin/sh
printf 'entry\\n' >> "$TEST_ENTRY_LOG"
export HOME="$TEST_RUNTIME_HOME"
export PATH="$HOME/.local/share/mise/shims:$PATH"
exec sh
'''); integration.chmod(0o700)
        entries = self.work / 'entries'
        for _ in range(2):
            p = self.call('probe', 'node', '22.14.0', KAI_PLATFORM='istoreos',
                          ISTORE_SYSTEM_ROOT=str(system), TEST_RUNTIME_HOME=str(runtime_home), TEST_ENTRY_LOG=str(entries))
            self.assertEqual(p.returncode, 4, p.stderr)
            self.assertEqual(json.loads(p.stdout)['category'], 'runtime-not-installed')
        self.assertEqual(entries.read_text().splitlines(), ['entry', 'entry'])

    def test_missing_istore_integration_reports_environment_failure_without_install(self):
        system = self.work / 'system'; (system / 'etc').mkdir(parents=True)
        (system / 'etc/openwrt_release').touch()
        for name in ['uci', 'mise-exec']:
            path = self.bin / name; path.write_text('#!/bin/sh\nexit 1\n'); path.chmod(0o700)
        p = self.call('probe', 'python', '3.13.7', KAI_PLATFORM='istoreos', ISTORE_SYSTEM_ROOT=str(system))
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertTrue(p.stdout.strip(), p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'environment-inactive')
        self.assertFalse(self.log.exists())

    def test_failure_evidence_distinguishes_integrity_without_losing_original_code(self):
        log = self.work / 'failure.log'; log.write_text('mise ERROR checksum mismatch')
        p = subprocess.run(['bash', str(DIAGNOSE), str(log), '11'], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(p.stdout)
        self.assertEqual(result['category'], 'integrity-failed')
        self.assertEqual(result['originalExitCode'], 11)

    def test_diagnostics_distinguish_network_tls_prebuilt_environment_and_version(self):
        examples = [
            ('TLS certificate verification failed', 'tls-failed'),
            ('download timed out', 'download-failed'),
            ('no compatible precompiled Python available', 'precompiled-unavailable'),
            ('no acceptable C compiler found', 'source-build-rejected'),
            ('incorrect integration HOME', 'environment-inactive'),
            ('version not found', 'version-selection'),
        ]
        for message, expected in examples:
            with self.subTest(expected=expected):
                log = self.work / 'failure.log'; log.write_text(message)
                p = subprocess.run(['bash', str(DIAGNOSE), str(log), '1'], capture_output=True, text=True)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertEqual(json.loads(p.stdout)['category'], expected)

    def test_python_uses_a_scoped_copy_of_known_empty_engine_config(self):
        system = self.work / 'system'; (system / 'etc/ssl').mkdir(parents=True)
        source = system / 'etc/ssl/openssl.cnf'
        source.write_bytes((ROOT / 'tests/multisystem/fixtures/istoreos-openssl-default.cnf').read_bytes())
        before = source.read_bytes()
        modules = system / 'etc/ssl/modules.cnf.d'; modules.mkdir()
        legacy = modules / 'legacy.cnf'
        legacy.write_bytes(b'[legacy_sect]\nactivate = 1\n\n')
        legacy_before = legacy.read_bytes()
        sdk = self.work / 'sdk'; sdk.mkdir()
        (self.bin / 'mise').write_text('''#!/bin/bash
set -eu
case "$1" in
where) printf '%s\\n' "$TEST_SDK" ;;
exec) shift 3; exec "$@" ;;
*) exit 29 ;;
esac
''')
        p = self.call('exec', 'python', '3.13.7', '--', 'bash', '-c', 'printf "%s" "${OPENSSL_CONF:-}"',
                      KAI_PLATFORM='istoreos', ISTORE_RUNTIME_ENTERED='1', ISTORE_SYSTEM_ROOT=str(system), TEST_SDK=str(sdk))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(p.stdout, 'a Python-only compatibility path should be selected')
        selected = Path(p.stdout)
        self.assertNotEqual(selected, source)
        self.assertEqual(source.read_bytes(), before)
        self.assertEqual(legacy.read_bytes(), legacy_before)
        self.assertIn(b'config_diagnostics = 1', selected.read_bytes())
        self.assertIn(b'providers = provider_sect', selected.read_bytes())
        self.assertNotIn(b'\nengines = engines_sect\n', selected.read_bytes())
        lock = json.loads((CLI.parent.parent / 'references/python-openssl.lock.json').read_text())
        self.assertEqual(hashlib.sha256(selected.read_bytes()).hexdigest(), lock['pythonSha256'])
        extensions = system / 'var/etc/ssl'; extensions.mkdir(parents=True)
        for name, policy in [('engines.cnf', 'hardware = hardware_engine\n'),
                             ('providers.cnf', 'legacy = legacy_sect\n')]:
            with self.subTest(policy=name):
                extension = extensions / name; extension.write_text(policy)
                p = self.call('exec', 'python', '3.13.7', '--', 'true', KAI_PLATFORM='istoreos',
                              ISTORE_RUNTIME_ENTERED='1', ISTORE_SYSTEM_ROOT=str(system), TEST_SDK=str(sdk))
                self.assertEqual(p.returncode, 4, p.stderr)
                self.assertEqual(json.loads(p.stdout)['category'], 'openssl-config-conflict')
                self.assertEqual(extension.read_text(), policy)
                extension.unlink()
        legacy.write_bytes(b'[legacy_sect]\nactivate = 0\n')
        p = self.call('exec', 'python', '3.13.7', '--', 'true', KAI_PLATFORM='istoreos',
                      ISTORE_RUNTIME_ENTERED='1', ISTORE_SYSTEM_ROOT=str(system), TEST_SDK=str(sdk))
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'openssl-config-conflict')
        p = self.call('exec', 'python', '3.13.7', '--', 'bash', '-c', 'printf "%s" "$OPENSSL_CONF"',
                      KAI_PLATFORM='istoreos', ISTORE_RUNTIME_ENTERED='1', ISTORE_SYSTEM_ROOT=str(system),
                      TEST_SDK=str(sdk), OPENSSL_CONF='/explicit/policy.cnf')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, '/explicit/policy.cnf')
        self.assertEqual(source.read_bytes(), before)

    def test_tls_validator_rejects_untrusted_certificates_and_wrong_hostnames(self):
        cert = self.work / 'cert.pem'; key = self.work / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                        '-nodes', '-days', '1', '-keyout', str(key), '-out', str(cert),
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ca_directory = self.work / 'hashed CA'; ca_directory.mkdir()
        subject_hash = subprocess.check_output(['openssl', 'x509', '-in', str(cert), '-noout', '-hash'], text=True).strip()
        (ca_directory / (subject_hash + '.0')).symlink_to(cert)
        empty_directory = self.work / 'empty CA'; empty_directory.mkdir()
        p = subprocess.run(['python3', str(CLI.with_name('check-tls.py')), str(cert), str(key),
                            '--capath', str(ca_directory)],
                           env={**os.environ, 'SSL_CERT_FILE': str(self.work / 'absent.pem'),
                                'SSL_CERT_DIR': str(empty_directory)},
                           capture_output=True, text=True, timeout=15)
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(p.stdout)
        self.assertTrue(result['untrustedRejected'])
        self.assertTrue(result['hostnameMismatchRejected'])
        self.assertEqual(result['trustedHandshake'], 'passed')
        self.assertEqual(result['capath']['loadedBefore'], 0)
        self.assertGreater(result['capath']['loadedAfter'], 0)
        self.assertEqual(result['capath']['trustedHandshake'], 'passed')

    def test_python_module_check_accepts_lazy_certificate_directory(self):
        ca_directory = self.work / 'CA directory'; ca_directory.mkdir()
        cert = ca_directory / 'root.pem'; key = self.work / 'root.key'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                        '-nodes', '-days', '1', '-keyout', str(key), '-out', str(cert),
                        '-subj', '/CN=fixture CA'], check=True, capture_output=True)
        subject_hash = subprocess.check_output(['openssl', 'x509', '-in', str(cert), '-noout', '-hash'], text=True).strip()
        (ca_directory / (subject_hash + '.0')).symlink_to(cert.name)
        p = subprocess.run([sys.executable, str(CLI.with_name('check-python.py')),
                            str(Path(sys.executable).resolve().parent.parent), sys.version.split()[0]],
                           env={**os.environ, 'SSL_CERT_FILE': str(self.work / 'absent.pem'),
                                'SSL_CERT_DIR': str(ca_directory)}, capture_output=True, text=True, timeout=15)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['modules'], 'passed')


if __name__ == '__main__':
    unittest.main()
