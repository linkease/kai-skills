import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'components/system-packs/common/skills/kai-project-dependencies/scripts/dependencies.sh'


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai dependency 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / 'bin'; self.bin.mkdir()
        self.sdk = self.work / 'sdk'; self.sdk.mkdir()
        self.project = self.work / 'project 中文'; self.project.mkdir()
        (self.project / 'package.json').write_text('{"name":"fixture","version":"1.0.0","private":true}')
        (self.project / 'package-lock.json').write_text('{"name":"fixture","lockfileVersion":3,"packages":{}}')
        self.log = self.work / 'native.calls'
        self.env = {**os.environ, 'HOME': str(self.work), 'KAI_PLATFORM': 'ubuntu',
                    'PATH': str(self.bin) + ':' + os.environ['PATH'],
                    'TEST_SDK': str(self.sdk), 'TEST_CALLS': str(self.log)}
        self.script('mise', '''case "$1" in
where) [ "${TEST_MISSING:-0}" = 0 ] || exit 4
case "$2" in uv@*) [ "${TEST_MISSING_UV:-0}" = 0 ] || exit 4 ;; esac
printf '%s\\n' "$TEST_SDK" ;;
exec) shift 3; exec "$@" ;;
*) exit 29 ;;
esac''')
        self.script('npm', '''printf '%s\\n' "$*" >> "$TEST_CALLS"
case "$1" in config) printf true ;; *) exit "${TEST_FAILURE:-0}" ;; esac''')

    def script(self, name, body):
        p = self.bin / name; p.write_text('#!/bin/bash\nset -eu\n' + body + '\n'); p.chmod(0o700)

    def call(self, *args, **env):
        return subprocess.run(['bash', str(CLI), *args], env={**self.env, **env},
                              capture_output=True, text=True, timeout=15)

    def test_missing_runtime_never_installs_or_mutates_project(self):
        before = {p.name:p.read_bytes() for p in self.project.iterdir()}
        p = self.call('install', 'npm', '22.14.0', str(self.project), TEST_MISSING='1')
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'runtime-not-installed')
        self.assertFalse(self.log.exists())
        self.assertEqual({p.name:p.read_bytes() for p in self.project.iterdir()}, before)

    def test_locked_npm_project_uses_ci_and_keeps_native_failure_and_lock(self):
        lock = self.project / 'package-lock.json'; before = lock.read_bytes()
        p = self.call('install', 'npm', '22.14.0', str(self.project), TEST_FAILURE='37')
        self.assertEqual(p.returncode, 37, p.stderr)
        self.assertEqual(json.loads(p.stdout)['exitCode'], 37)
        self.assertIn('ci', self.log.read_text().splitlines())
        self.assertEqual(lock.read_bytes(), before)

    def test_npm_install_never_converts_another_manager_or_creates_a_lock(self):
        (self.project / 'package.json').write_text('{"name":"fixture","packageManager":"pnpm@10.0.0"}')
        p = self.call('install', 'npm', '22.14.0', str(self.project))
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'manager-mismatch')
        self.assertFalse(self.log.exists())

    def test_npm_explicit_add_and_native_run_preserve_literal_arguments(self):
        p = self.call('add', 'npm', '22.14.0', str(self.project), '--', 'is-number@6.0.0')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('install --save-exact is-number@6.0.0', self.log.read_text().splitlines())
        p = self.call('run', 'npm', '22.14.0', str(self.project), '--', 'run', 'fixture;touch injected')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((self.project / 'injected').exists())
        self.assertIn('run fixture;touch injected', self.log.read_text().splitlines())

    def test_explicit_dependency_acceleration_uses_existing_client_and_does_not_start_service(self):
        self.script('ks-cli', '''printf "client:%s\\n" "$*" >> "$TEST_CALLS"
if [ "$1" = doctor ]; then printf '{"schema_version":1,"overall":"pass","tool":"npm"}'; else exit 43; fi''')
        p = self.call('install', 'npm', '22.14.0', str(self.project), KAI_DEP_ACCELERATION='required')
        self.assertEqual(p.returncode, 43, p.stderr)
        calls = self.log.read_text().splitlines()
        self.assertIn('client:npm ci', calls)
        self.assertIn('client:doctor npm --json', calls)
        self.assertFalse(any('service' in c for c in calls))

    def test_pip_creates_and_reenters_the_project_venv_without_global_installation(self):
        (self.bin / 'python').symlink_to(sys.executable)
        (self.project / 'requirements.txt').write_text('# empty offline scope fixture\n')
        env = {'TEST_SDK': str(Path(sys.executable).resolve().parent.parent),
               'PIP_CONFIG_FILE': os.devnull, 'PIP_TRUSTED_HOST': '', 'PIP_DISABLE_PIP_VERSION_CHECK':'1'}
        version = sys.version.split()[0]
        p = self.call('install', 'pip', version, str(self.project), **env)
        self.assertEqual(p.returncode, 0, p.stderr)
        p = self.call('run', 'pip', version, str(self.project), '--', '--version', **env)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn(str(self.project / '.venv'), p.stdout)
        self.assertTrue((self.project / '.venv/pyvenv.cfg').is_file())

    def test_isolated_windows_mise_does_not_probe_foreign_rustc_shims(self):
        (self.bin / 'python').symlink_to(sys.executable)
        self.script('cygpath', 'printf "%s\\n" "$2"')
        (self.project / 'requirements.txt').write_text('# offline pure Python project\n')
        shims = self.work / 'foreign' / 'mise' / 'shims'; shims.mkdir(parents=True)
        marker = self.work / 'foreign-rustc-invoked'
        rustc = shims / 'rustc'
        rustc.write_text('#!/bin/sh\nprintf called > "$TEST_FOREIGN_RUSTC"\necho "rustc 1.0.0"\n')
        rustc.chmod(0o700)
        p = self.call('install', 'pip', sys.version.split()[0], str(self.project),
            KAI_PLATFORM='windows', TEST_SDK=sys.base_prefix,
            MISE_DATA_DIR=str(self.work / 'isolated-mise'),
            PATH=str(self.bin)+':'+str(shims)+':'+os.environ['PATH'],
            TEST_FOREIGN_RUSTC=str(marker), PIP_CONFIG_FILE=os.devnull,
            PIP_TRUSTED_HOST='', PIP_DISABLE_PIP_VERSION_CHECK='1')
        self.assertEqual(p.returncode, 0, p.stdout+p.stderr)
        self.assertFalse(marker.exists(), 'pip inspected an unselected foreign mise shim')

    def test_uv_is_an_explicit_installed_tool_and_never_bootstraps_itself(self):
        (self.project / 'requirements.txt').write_text('idna==3.10\n')
        p = self.call('install', 'uv', '3.13.7', str(self.project), KAI_UV_VERSION='0.8.22', TEST_MISSING_UV='1')
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'tool-not-installed')
        self.assertFalse((self.project / '.venv').exists())
        self.assertFalse(self.log.exists())

    def test_uv_selects_python_and_uv_together_for_project_operations(self):
        (self.bin / 'python').symlink_to(sys.executable)
        (self.project / 'requirements.txt').write_text('# offline protocol fixture\n')
        uv_root = self.work / 'uv-sdk'; (uv_root / 'bin').mkdir(parents=True)
        uv = uv_root / 'bin/uv'
        uv.write_text('''#!/bin/sh
if [ "$1" = --version ]; then echo 'uv 0.8.22'; exit; fi
[ "$UV_PYTHON_DOWNLOADS" = never ] || exit 38
printf '%s\\n' "$*" >> "$TEST_CALLS"
'''); uv.chmod(0o700)
        self.script('mise', '''case "$1" in
where) case "$2" in uv@*) printf '%s\\n' "$TEST_UV_ROOT" ;; *) printf '%s\\n' "$TEST_SDK" ;; esac ;;
exec)
 shift; python_selected=0; uv_selected=0
 while [ "$1" != -- ]; do
  case "$1" in python@*) python_selected=1 ;; uv@*) uv_selected=1 ;; esac; shift
 done
 shift
 if [ "$uv_selected" = 1 ]; then
  [ "$python_selected" = 1 ] || { echo 'tool-only exec deactivates the Python SDK' >&2; exit 44; }
  export PATH="$TEST_UV_ROOT/bin:$PATH"
 fi
 exec "$@" ;;
*) exit 29 ;;
esac''')
        p = self.call('install', 'uv', sys.version.split()[0], str(self.project),
                      KAI_UV_VERSION='0.8.22', TEST_UV_ROOT=str(uv_root),
                      TEST_SDK=str(Path(sys.executable).resolve().parent.parent))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.project / '.venv/pyvenv.cfg').is_file())
        self.assertIn('pip install --python ', self.log.read_text())

    def test_system_uv_with_matching_version_cannot_replace_the_selected_mise_tool(self):
        (self.bin / 'python').symlink_to(sys.executable)
        self.script('uv', 'printf "uv 0.8.22\\n"')
        (self.project / 'requirements.txt').write_text('idna==3.10\n')
        p = self.call('install', 'uv', '3.13.7', str(self.project), KAI_UV_VERSION='0.8.22')
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'tool-provenance-mismatch')
        self.assertFalse((self.project / '.venv').exists())

    def test_go_keeps_sumdb_and_preserves_native_failure_and_existing_sum(self):
        (self.project / 'go.mod').write_text('module example.invalid/fixture\n\ngo 1.20\n')
        go_sum = self.project / 'go.sum'; go_sum.write_text('# frozen fixture\n')
        self.script('go', '''if [ "$1" = env ]; then
case "$2" in GOSUMDB) printf '%s' "${GOSUMDB:-sum.golang.org}" ;; GOINSECURE) printf '%s' "${GOINSECURE:-}" ;; esac
else printf '%s\\n' "$*" >> "$TEST_CALLS"; exit 47; fi''')
        p = self.call('install', 'go', '1.24.1', str(self.project))
        self.assertEqual(p.returncode, 47, p.stderr)
        self.assertEqual(json.loads(p.stdout)['exitCode'], 47)
        self.assertEqual(go_sum.read_text(), '# frozen fixture\n')
        self.assertIn('mod download', self.log.read_text().splitlines())
        self.log.unlink()
        p = self.call('install', 'go', '1.24.1', str(self.project), GOSUMDB='off')
        self.assertEqual(p.returncode, 4, p.stderr)
        self.assertEqual(json.loads(p.stdout)['category'], 'integrity-disabled')
        self.assertFalse(self.log.exists())

    def test_source_inspection_distinguishes_git_urls_and_registry_without_execution(self):
        (self.project / 'package.json').write_text(json.dumps({'dependencies': {
            'normal':'7.0.0', 'vcs':'git+https://github.com/example/repo.git#abc',
            'external':'https://cdn.example.invalid/package.tgz', 'local':'file:../other'}}))
        p = self.call('sources', 'npm', '22.14.0', str(self.project))
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(p.stdout)
        self.assertEqual({r['name']:r['type'] for r in result['sources']},
                         {'normal':'registry','vcs':'git','external':'url','local':'local'})
        self.assertEqual(result['accelerationValidation'], 'not-tested')
        self.assertFalse(self.log.exists())

    def test_source_inspection_reads_large_locks_without_shell_argument_limits(self):
        (self.project / 'package.json').write_text('{"dependencies":{"normal":"7.0.0"}}')
        (self.project / 'package-lock.json').write_text(json.dumps({'packages': {
            'node_modules/normal': {'resolved':'https://cdn.example.invalid/normal.tgz'}},
            'metadata': 'x' * 200000}))
        p = self.call('sources', 'npm', '22.14.0', str(self.project))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['sources'], [{'name':'normal','type':'url'}])

    def test_python_and_go_source_hints_do_not_promise_registry_coverage(self):
        (self.project / 'requirements.txt').write_text('idna==3.10\ngit+https://github.com/example/repo\nhttps://cdn.example.invalid/demo.whl\n')
        p = self.call('sources', 'pip', '3.13.7', str(self.project), TEST_MISSING='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(p.stdout)
        self.assertEqual({r['type'] for r in result['sources']}, {'registry','git','url'})
        self.assertTrue(result['requiresSourceReview'])
        (self.project / 'go.mod').write_text('module example.invalid/demo\nrequire github.com/google/uuid v1.6.0\nreplace example.invalid/private => ../private\n')
        p = self.call('sources', 'go', '1.24.1', str(self.project), TEST_MISSING='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('local', {r['type'] for r in json.loads(p.stdout)['sources']})


if __name__ == '__main__':
    unittest.main()
