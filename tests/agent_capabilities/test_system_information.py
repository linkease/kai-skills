import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'components/system-packs/common/skills/kai-system-information/scripts/inspect.sh'
spec=importlib.util.spec_from_file_location('query_contract',ROOT/'tools/agent_capabilities/contract.py')
contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)

DOCKER_FIXTURE='''#!/bin/sh
printf '%s\\n' "$*" >> "$PROBE_CALLS"
case "$*" in
 'context show') printf '%s\\n' "${PROBE_CONTEXT:-default}" ;;
 'context inspect '*) printf '%s\\n' "${PROBE_ENDPOINT:-unix:///var/run/docker.sock}" ;;
 *'version --format '*)
  case "${PROBE_MODE:-healthy}" in
   healthy) echo 27.3.1 ;;
   stopped) echo 'Cannot connect to the Docker daemon' >&2;exit 1 ;;
   denied) echo 'permission denied for Docker socket' >&2;exit 1 ;;
   timeout) sleep 30 ;;
   ignore-termination) trap '' TERM ALRM; sleep 30 ;;
   oversized) head -c 5000 /dev/zero | tr '\\000' x ;;
   other) echo 'Unexpected protocol response' >&2;exit 1 ;;
  esac ;;
 *) exit 71 ;;
esac
'''


class SystemInformationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='kai-query-中文-')
        self.addCleanup(self.temp.cleanup)
        self.work=Path(self.temp.name);self.bin=self.work/'bin';self.bin.mkdir()
        self.calls=self.work/'calls';self.marker=self.work/'unexpected-write'
        self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],
                  'TMPDIR':str(self.work),'PROBE_CALLS':str(self.calls),'WRITE_MARKER':str(self.marker)}
        for key in ('DOCKER_HOST','DOCKER_CONTEXT'):self.env.pop(key,None)

    def executable(self,name,body):
        path=self.bin/name;path.write_text(body);path.chmod(0o700);return path

    def call(self,*args,env=None):
        result=subprocess.run(['sh',str(SCRIPT),'--target-id','fixture-target',*args],
                              env={**self.env,**(env or {})},capture_output=True,timeout=12)
        value=contract.validate_result(result.stdout,expected_target='fixture-target')
        self.assertFalse(self.marker.exists(),'Read-only discovery executed an installer or provider.')
        self.assertFalse(list(self.work.glob('kai-system-inspect.*')),'Own probe materials were not cleaned.')
        return result,value

    def test_native_system_facts_and_utf8_without_json_or_python_dependencies(self):
        result,value=self.call('--sections','os')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn(value['facts']['os']['family'],('linux','darwin'))
        self.assertTrue(value['facts']['architecture'])
        self.assertEqual(value['effects']['completed'],[])

    def test_multiple_managers_scripts_symlinks_and_downloaders_are_not_chosen_or_run(self):
        for name in ('apt','apk','opkg','yum','dnf','scoop','winget','wget'):
            self.executable(name,'#!/bin/sh\ntouch "$WRITE_MARKER"\nexit 89\n')
        (self.bin/'is-opkg').symlink_to(self.bin/'opkg')
        _,value=self.call('--sections','tools')
        providers={p['name']:p for p in value['facts']['packageManagers']}
        self.assertTrue({'apt','apk','opkg','is-opkg','yum','dnf','scoop','winget'}<=providers.keys())
        self.assertNotIn('wget',providers)
        self.assertEqual(providers['is-opkg']['commandType'],'symlink')
        self.assertEqual(providers['opkg']['commandType'],'script')
        self.assertIn('wget',{p['name'] for p in value['facts']['downloadTools']})
        self.assertFalse(any('recommended' in p or 'default' in p for p in providers.values()))

    def test_docker_client_and_actual_engine_readiness_are_distinct(self):
        self.executable('docker',DOCKER_FIXTURE)
        result,value=self.call('--sections','docker')
        self.assertEqual(result.returncode,0)
        self.assertTrue(value['facts']['dockerClientAvailable'])
        self.assertTrue(value['facts']['dockerApiReachable'])
        self.assertEqual(value['facts']['dockerServerVersion'],'27.3.1')
        result,value=self.call('--sections','docker',env={'PROBE_MODE':'stopped'})
        self.assertEqual(result.returncode,0)
        self.assertFalse(value['facts']['dockerApiReachable'])
        self.assertEqual(value['operationStatus'],'succeeded')

    def test_denial_unknown_and_deadline_are_not_reported_as_absence(self):
        self.executable('docker',DOCKER_FIXTURE)
        for mode,status in [('denied','denied'),('other','unknown'),('timeout','timeout')]:
            with self.subTest(mode=mode):
                started=time.monotonic()
                result,value=self.call('--sections','docker','--deadline-seconds','2',env={'PROBE_MODE':mode})
                self.assertNotEqual(result.returncode,0)
                self.assertIsNone(value['facts']['dockerApiReachable'])
                evidence=next(e for e in value['evidence'] if '/facts/dockerApiReachable' in e['factPaths'])
                self.assertEqual(evidence['status'],status)
                self.assertLess(time.monotonic()-started,4)

    def test_remote_context_is_only_metadata_until_explicitly_selected_and_secrets_are_redacted(self):
        self.executable('docker',DOCKER_FIXTURE)
        env={'PROBE_CONTEXT':'remote-fixture','PROBE_ENDPOINT':'ssh://user:secret@engine/?token=private'}
        _,value=self.call('--sections','docker',env=env)
        self.assertIsNone(value['facts']['dockerApiReachable'])
        self.assertNotIn('version --format',self.calls.read_text())
        encoded=json.dumps(value);self.assertNotIn('secret',encoded);self.assertNotIn('private',encoded)
        self.calls.unlink()
        _,value=self.call('--sections','docker','--engine-context','remote-fixture',env=env)
        self.assertTrue(value['facts']['dockerApiReachable'])
        self.assertIn('--context remote-fixture version',self.calls.read_text())

    def test_docker_host_override_is_not_mistaken_for_local_context(self):
        self.executable('docker',DOCKER_FIXTURE)
        _,value=self.call('--sections','docker',env={'DOCKER_HOST':'ssh://user:password@another-engine'})
        self.assertIsNone(value['facts']['dockerApiReachable'])
        self.assertNotIn('version --format',self.calls.read_text())
        self.assertNotIn('password',json.dumps(value))

    def test_scope_and_literal_target_arguments_do_not_become_shell_programs(self):
        result=subprocess.run(['sh',str(SCRIPT),'--target-id','中文 " \\ $(touch '+str(self.marker)+')',
                               '--sections','tools'],env=self.env,capture_output=True,timeout=10)
        value=contract.validate_result(result.stdout)
        self.assertIn('$(touch ',value['targetId'])
        self.assertFalse(self.marker.exists())
        for args in [('--sections','repair'),('--deadline-seconds','0'),('--sections','os,,tools')]:
            with self.subTest(args=args):
                result,value=self.call(*args)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(value['operationStatus'],'failed')

    def test_unknown_distribution_is_not_inferred_from_installed_package_managers(self):
        real_awk=shutil.which('awk')
        fixture=self.work/'os-release'
        self.executable('awk','''#!/bin/bash
args=("$@")
if [[ "${args[${#args[@]}-1]}" == /etc/os-release ]]; then args[${#args[@]}-1]="$FIXTURE_OS_RELEASE"; fi
exec "$FIXTURE_REAL_AWK" "${args[@]}"
''')
        fixture.write_text('ID=""\nVERSION_ID=""\nPRETTY_NAME="$(touch '+str(self.marker)+')"\n')
        result,value=self.call('--sections','os,tools',env={'FIXTURE_OS_RELEASE':str(fixture),'FIXTURE_REAL_AWK':real_awk})
        self.assertNotEqual(result.returncode,0)
        self.assertIsNone(value['facts']['os']['distribution'])
        self.assertIsNone(value['facts']['os']['version'])
        self.assertIn('$(touch ',value['facts']['os']['name'])
        self.assertFalse(self.marker.exists())

    def test_json_string_encoder_preserves_control_characters_and_trailing_newlines(self):
        target='中文 " \\ \t\r\n\n'
        result=subprocess.run(['sh',str(SCRIPT),'--target-id',target,'--sections','tools'],
                              env=self.env,capture_output=True,timeout=10)
        value=contract.validate_result(result.stdout,expected_target=target)
        self.assertEqual(value['targetId'],target)

    def sparse_path(self,include_awk=False):
        directory=self.work/('minimal-awk' if include_awk else 'minimal');directory.mkdir()
        for command in ('sh','date','dirname','uname','mkdir','mktemp','rm','head','wc','tr','dd','sed','cat'):
            source=shutil.which(command)
            if source:(directory/command).symlink_to(source)
        if include_awk:(directory/'awk').symlink_to(shutil.which('awk'))
        return directory

    def test_minimal_unix_queries_work_without_bash_python_jq_or_awk(self):
        path=self.sparse_path()
        result,value=self.call('--sections','os,tools',env={'PATH':str(path)})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(value['facts']['os']['family'],'linux')
        target='中文 " \\ \t\r\n\n'
        result=subprocess.run(['sh',str(SCRIPT),'--target-id',target,'--sections','tools'],
                              env={**self.env,'PATH':str(path)},capture_output=True,timeout=10)
        contract.validate_result(result.stdout,expected_target=target)

    def test_minimal_docker_probe_reports_missing_bounded_executor_as_unsupported(self):
        path=self.sparse_path(include_awk=True)
        docker=path/'docker';docker.write_text(DOCKER_FIXTURE);docker.chmod(0o700)
        result,value=self.call('--sections','docker',env={'PATH':str(path)})
        self.assertNotEqual(result.returncode,0)
        self.assertIsNone(value['facts']['dockerContext'])
        evidence=next(e for e in value['evidence'] if '/facts/dockerContext' in e['factPaths'])
        self.assertEqual(evidence['status'],'unsupported')
        self.assertFalse(self.calls.exists(),'A probe ran without a bounded executor.')

    def test_probe_output_limit_is_not_silently_truncated_into_a_success(self):
        self.executable('docker',DOCKER_FIXTURE)
        result,value=self.call('--sections','docker',env={'PROBE_MODE':'oversized'})
        self.assertNotEqual(result.returncode,0)
        self.assertIsNone(value['facts']['dockerApiReachable'])
        self.assertIn('PROBE_OUTPUT_LIMIT',{e['code'] for e in value['errors']})

    def test_wsl_kernel_marker_does_not_invent_the_outer_host_distribution(self):
        self.executable('uname','''#!/bin/sh
case "$1" in -s) echo Linux;; -m) echo x86_64;; -r) echo 5.15.153.1-microsoft-standard-WSL2;; esac
''')
        _,value=self.call('--sections','os')
        self.assertTrue(value['facts']['environment']['wslKernelMarker'])
        self.assertIsNone(value['facts']['environment']['hostDistribution'])
        self.assertEqual(value['facts']['kernel']['scope'],'target-execution-environment')

    def test_deadline_also_terminates_a_probe_that_ignores_term(self):
        self.executable('docker',DOCKER_FIXTURE)
        started=time.monotonic()
        result,value=self.call('--sections','docker','--deadline-seconds','2',env={'PROBE_MODE':'ignore-termination'})
        self.assertNotEqual(result.returncode,0)
        self.assertIsNone(value['facts']['dockerApiReachable'])
        self.assertIn('DOCKER_TIMEOUT',{e['code'] for e in value['errors']})
        self.assertLess(time.monotonic()-started,5)


if __name__=='__main__':unittest.main()
