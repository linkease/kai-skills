import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / 'components/system-packs/istoreos/skills/istoreos-service-manager/scripts/apply.sh'
spec = importlib.util.spec_from_file_location('write_contract', ROOT / 'tools/agent_capabilities/contract.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class WriteFixture:
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kai-write-中文-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.system = self.root / 'system'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'operations'
        self.state.mkdir(mode=0o700)
        self.init = self.system / 'etc/init.d/example'
        self.init.parent.mkdir(parents=True)
        self.config = self.system / 'etc/config/example'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(json.dumps({'main': {'enabled': '0', 'untouched': 'keep'}}))
        self.calls = self.root / 'calls'
        self.running = self.root / 'running'
        self.init.write_text('''#!/bin/sh
printf 'service:%s\n' "$1" >> "$TEST_CALLS"
if [ "${TEST_FAIL_ACTION:-}" = "$1" ]; then exit 17; fi
if [ "${TEST_SLEEP_ACTION:-}" = "$1" ]; then touch "$TEST_RUNNING"; exec sleep 20; fi
case "$1" in start|restart) touch "$TEST_RUNNING";; stop) rm -f "$TEST_RUNNING";; enable) touch "$TEST_RUNNING.enabled";; disable) rm -f "$TEST_RUNNING.enabled";; enabled) test -f "$TEST_RUNNING.enabled";; esac
''')
        self.init.chmod(0o700)
        self.env = {**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH'],
                    'ISTOREOS_ROOT': str(self.system), 'KAI_OPERATION_STATE_DIR': str(self.state),
                    'ZSETUP_TASK_TARGET_ID': 'test-target', 'KAIPLUS_CONFIRMED': '1',
                    'TEST_CALLS': str(self.calls), 'TEST_RUNNING': str(self.running)}
        self.fake('ubus', '''import json,os
from pathlib import Path
service=json.loads(__import__('sys').argv[-1])['name']
print(json.dumps({service:{'instances':{'one':{'running':Path(os.environ['TEST_RUNNING']).exists()}}}}))
''')
        self.fake('docker', '''import json,os,sys
if os.environ.get('TEST_API_FAIL'):sys.exit(19)
print(json.dumps({'ID':os.environ.get('TEST_ENGINE_ID','engine-one'),'DockerRootDir':os.environ.get('TEST_DOCKER_ROOT','/chosen/docker'),'ServerVersion':'27.0'}))
''')
        self.fake('uci', r'''import json,os,sys
from pathlib import Path
args=sys.argv[1:];root=None;saved=None;no_commit=False
while args and args[0].startswith('-'):
 option=args.pop(0)
 if option=='-q':continue
 if option in ('-c','-t','-P'):
  value=args.pop(0)
  if option=='-c':root=Path(value)
  else:saved=Path(value);no_commit=(option=='-P')
 else:sys.exit(90)
action=args[0];subject=args[1]
with open(os.environ['TEST_CALLS'],'a') as log:log.write('uci:'+action+'\n')
if os.environ.get('TEST_FAIL_UCI')==action:sys.exit(18)
package=subject.split('.',1)[0];path=root/package;delta=saved/(package+'.json')
data=json.loads(delta.read_text() if delta.exists() else path.read_text())
if action=='get':
 _,section,key=subject.split('.',2);print(data[section][key])
elif action=='set':
 key,value=subject.split('=',1);_,section,key=key.split('.',2);data[section][key]=value
 delta.write_text(json.dumps(data))
elif action=='commit':
 if not no_commit:path.write_text(json.dumps(data));delta.unlink(missing_ok=True)
else:sys.exit(91)
''')
        self.index = 0
        self.script = SERVICE

    def fake(self, name, body):
        import sys
        p = self.bin / name
        p.write_text('#!' + sys.executable + '\n' + body)
        p.chmod(0o700)

    def request(self, **parameters):
        self.index += 1
        p = self.root / ('request-' + str(self.index) + '.json')
        value = {'schemaVersion': 1, 'operation': 'service.apply', 'targetId': 'test-target', 'parameters': {
            'operationId': 'job-' + str(self.index), 'service': 'example', 'action': 'start',
            'configName': 'example', 'expectedInitSHA256': hashlib.sha256(self.init.read_bytes()).hexdigest(),
            'expectedConfigSHA256': hashlib.sha256(self.config.read_bytes()).hexdigest(),
            'verification': {'kind': 'procd-running'}, 'timeoutSeconds': 2, **parameters}}
        p.write_text(json.dumps(value))
        return p

    def apply(self, request=None, **env):
        p = subprocess.run(['bash', str(self.script), str(request or self.request())], env={**self.env, **env},
                           text=True, capture_output=True, timeout=10)
        self.assertTrue(p.stdout, p.stderr)
        result = contract.validate_result(p.stdout, expected_target='test-target')
        self.assertFalse(result['readOnly'])
        return p, result


class ServiceWriteTests(WriteFixture, unittest.TestCase):
    def test_explicit_start_is_verified_and_same_id_is_never_replayed(self):
        request = self.request()
        before = self.init.read_bytes()
        p, result = self.apply(request)
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual(result['operationStatus'], 'succeeded')
        self.assertEqual(result['verification']['status'], 'passed')
        self.assertEqual(self.calls.read_text(), 'service:start\n')
        p, repeated = self.apply(request)
        self.assertEqual(repeated, result)
        self.assertEqual(self.calls.read_text(), 'service:start\n')
        self.assertEqual(before, self.init.read_bytes())

    def test_stale_configuration_and_missing_parameters_do_not_start_service(self):
        request = self.request()
        self.config.write_text('{"main":{"enabled":"user-change"}}')
        p, result = self.apply(request)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'PRECONDITION_CHANGED')
        self.assertFalse(self.calls.exists())
        request = self.request()
        data = json.loads(request.read_text());del data['parameters']['action'];request.write_text(json.dumps(data))
        p, result = self.apply(request)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'INVALID_ARGUMENT')
        self.assertFalse(self.calls.exists())

    def test_authorization_marker_and_target_are_independent_preconditions(self):
        p, result = self.apply(self.request(), KAIPLUS_CONFIRMED='0')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'AUTHORIZATION_REQUIRED')
        p = subprocess.run(['bash', str(SERVICE), str(self.request())], env={**self.env, 'ZSETUP_TASK_TARGET_ID': 'other-target'}, capture_output=True, text=True)
        result = contract.validate_result(p.stdout, expected_target='test-target')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'TARGET_MISMATCH')
        self.assertFalse(self.calls.exists())

    def test_stop_failure_is_unknown_and_does_not_attempt_another_action(self):
        request = self.request(action='stop', verification={'kind': 'procd-stopped'})
        p, result = self.apply(request, TEST_FAIL_ACTION='stop')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['operationStatus'], 'unknown')
        self.assertEqual([e['id'] for e in result['effects']['unknown']], ['service-command'])
        self.assertEqual(self.calls.read_text(), 'service:stop\n')
        p, repeated = self.apply(request)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(repeated, result)
        self.assertEqual(self.calls.read_text(), 'service:stop\n')

    def test_configure_uses_explicit_key_and_preserves_unrelated_values(self):
        request = self.request(action='none', verification={'kind': 'uci-value'},
                               uci={'key': 'example.main.enabled', 'expectedValue': '0', 'value': '1'})
        p, result = self.apply(request)
        self.assertEqual(p.returncode, 0, result)
        value = json.loads(self.config.read_text())
        self.assertEqual(value['main'], {'enabled': '1', 'untouched': 'keep'})
        self.assertNotIn('service:', self.calls.read_text())
        self.assertEqual(list(self.config.parent.glob('.kai-operation.*')), [])

    def test_commit_failure_preserves_original_configuration_and_partial_receipt(self):
        before = self.config.read_bytes()
        request = self.request(action='none', verification={'kind': 'uci-value'},
                               uci={'key': 'example.main.enabled', 'expectedValue': '0', 'value': '1'})
        p, result = self.apply(request, TEST_FAIL_UCI='commit')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual([e['id'] for e in result['effects']['completed']], ['config-stage'])
        self.assertEqual([e['id'] for e in result['effects']['unknown']], ['config-commit'])
        self.assertIn('config-activate', [e['id'] for e in result['effects']['remaining']])

    def test_process_state_does_not_replace_selected_docker_api_verification(self):
        docker_init = self.init.with_name('dockerd');docker_init.write_bytes(self.init.read_bytes());docker_init.chmod(0o700)
        request = self.request(service='dockerd', verification={'kind': 'docker-api', 'endpoint': 'unix:///var/run/docker.sock',
                               'expectedEngineId': 'engine-one', 'expectedDataRoot': '/chosen/docker'})
        for env in [{'TEST_API_FAIL': '1'}, {'TEST_ENGINE_ID': 'other'}, {'TEST_DOCKER_ROOT': '/other/docker'}]:
            data = json.loads(request.read_text());data['parameters']['operationId'] += '-case';request.write_text(json.dumps(data))
            p, result = self.apply(request, **env)
            self.assertNotEqual(p.returncode, 0)
            self.assertNotEqual(result['operationStatus'], 'succeeded')
            self.assertTrue(self.running.exists())
        p, result = self.apply(self.request(service='dockerd'))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'INVALID_ARGUMENT')

    def docker_request(self, **values):
        docker_init = self.init.with_name('dockerd')
        docker_init.write_bytes(self.init.read_bytes());docker_init.chmod(0o700)
        return self.request(service='dockerd', verification={'kind': 'docker-api', 'endpoint': 'unix:///unrelated/docker.sock',
                            'expectedEngineId': 'engine-one', 'expectedDataRoot': '/chosen/docker'}, **values)

    def test_unrelated_api_does_not_hide_selected_service_exit(self):
        self.fake('ubus', "print('{\"dockerd\":{\"instances\":{\"one\":{\"running\":false}}}}')\n")
        p, result = self.apply(self.docker_request())
        self.assertNotEqual(p.returncode, 0, result)
        self.assertNotEqual(result['operationStatus'], 'succeeded')

    def test_unrelated_api_does_not_validate_another_running_process(self):
        sleeper = subprocess.Popen(['sleep', '20'])
        self.addCleanup(lambda: (sleeper.terminate(), sleeper.wait()))
        self.fake('ubus', 'print(\'{"dockerd":{"instances":{"one":{"running":true,"pid":' + str(sleeper.pid) + '}}}}\')\n')
        short = tempfile.TemporaryDirectory(prefix='kai-sock-', dir='/tmp')
        self.addCleanup(short.cleanup)
        endpoint = Path(short.name) / 'real-unrelated.sock'
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(listener.close);listener.bind(str(endpoint));listener.listen(1)
        request = self.docker_request()
        data = json.loads(request.read_text());data['parameters']['verification']['endpoint']='unix://'+str(endpoint);request.write_text(json.dumps(data))
        p, result = self.apply(request)
        self.assertNotEqual(p.returncode, 0, result)
        self.assertNotEqual(result['operationStatus'], 'succeeded')

    def test_cancellation_keeps_pending_effect_and_does_not_replay(self):
        request = self.request(timeoutSeconds=1)
        p = subprocess.Popen(['bash', str(SERVICE), str(request)], env={**self.env, 'TEST_SLEEP_ACTION': 'start'}, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while not self.running.exists() and p.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(self.running.exists())
        p.send_signal(signal.SIGTERM)
        out, err = p.communicate(timeout=5)
        result = contract.validate_result(out, expected_target='test-target')
        self.assertNotEqual(result['operationStatus'], 'succeeded')
        self.assertEqual(len(result['effects']['unknown']), 1)
        before = self.calls.read_bytes()
        run, repeat = self.apply(request)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(self.calls.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
