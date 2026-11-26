import hashlib
import json
from pathlib import Path
import unittest
from test_writes import WriteFixture, ROOT


class ExplicitOperationTests(WriteFixture, unittest.TestCase):
    def operation(self, name, **parameters):
        self.index += 1
        path = self.root / ('explicit-%d.json' % self.index)
        path.write_text(json.dumps({'schemaVersion': 1, 'operation': name, 'targetId': 'test-target',
            'parameters': {'operationId': 'explicit-%d' % self.index, 'timeoutSeconds': 2, **parameters}}))
        return path

    def artifact(self, content='printf "%s" "$1" > "$2"\n', **parameters):
        self.script = ROOT / 'components/system-packs/istoreos/skills/istoreos-run-executable/scripts/run.sh'
        path = self.root / 'reviewed.sh'; path.write_text(content)
        return self.operation('artifact.execute', path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            runner='sh', arguments=['literal;$(echo bad)', str(self.root / 'result')], workingDirectory=str(self.root), **parameters)

    def test_artifact_exact_args_owned_copy_no_source_chmod_or_replay(self):
        request = self.artifact(); source = self.root / 'reviewed.sh'; before = source.stat().st_mode
        p, result = self.apply(request)
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual((self.root / 'result').read_text(), 'literal;$(echo bad)')
        self.assertEqual(source.stat().st_mode, before)
        self.assertNotEqual(result['facts']['artifact']['executedCopy'], str(source))
        (self.root / 'result').unlink()
        p, again = self.apply(request); self.assertEqual(result, again)
        self.assertFalse((self.root / 'result').exists())

    def test_artifact_stale_hash_native_nonexecutable_and_failed_exit(self):
        request = self.artifact(); (self.root / 'reviewed.sh').write_text('exit 0\n')
        p, result = self.apply(request); self.assertEqual(result['errors'][0]['code'], 'PRECONDITION_CHANGED')
        request = self.artifact(); value=json.loads(request.read_text());value['parameters']['runner']='native';request.write_text(json.dumps(value))
        p, result = self.apply(request); self.assertNotEqual(p.returncode, 0);self.assertFalse(result['effects']['completed'])
        p, result = self.apply(self.artifact('exit 23\n'))
        self.assertNotEqual(p.returncode, 0); self.assertTrue(result['effects']['unknown'])

    def setup_provider(self):
        self.fake('changeguard', '''import json,os,sys
args=sys.argv[1:];cmd=args[0]
with open(os.environ['TEST_CALLS'],'a') as log:log.write(cmd+'\\n')
def flag(name):return args[args.index(name)+1]
if cmd=='capabilities':r={'module':'changeguard','protocolVersion':1,'implemented':['backup','restore-start','restore-job']}
elif cmd=='backup':r={'id':'checkpoint-new','requestID':flag('--request-id'),'template':{'id':flag('--template')},'state':os.environ.get('TEST_CHECKPOINT_STATE','complete'),'roots':[]}
elif cmd=='restore-start':r={'id':flag('--request-id'),'state':'running'}
else:r={'id':flag('--id'),'checkpointID':os.environ.get('TEST_CHECKPOINT_ID','checkpoint-one'),'diffID':'diff-one','state':os.environ.get('TEST_RESTORE_STATE','completed'),'run':{'checkpointID':'checkpoint-one','state':'completed','filesRestored':True,'servicesRestored':os.environ.get('TEST_SERVICES','yes')=='yes','externalReachability':'not_tested'}}
print(json.dumps({'schemaVersion':1,'status':'succeeded','result':r}))
''')

    def test_backup_exact_template_and_incomplete_record_is_not_success(self):
        self.setup_provider();self.script=ROOT/'components/system-packs/istoreos/skills/istoreos-backup-restore/scripts/backup_system.sh'
        p, result=self.apply(self.operation('recovery.backup',templateId='selected-template'))
        self.assertEqual(p.returncode,0,result);self.assertEqual(result['facts']['checkpoint']['templateId'],'selected-template')
        p,result=self.apply(self.operation('recovery.backup',templateId='selected-template'),TEST_CHECKPOINT_STATE='pending')
        self.assertNotEqual(p.returncode,0);self.assertNotEqual(result['operationStatus'],'succeeded')

    def test_restore_acceptance_phase_scope_and_exact_identity(self):
        self.setup_provider();self.script=ROOT/'components/system-packs/istoreos/skills/istoreos-backup-restore/scripts/restore_system.sh'
        def req(scope='files-and-services'):return self.operation('recovery.restore',checkpointId='checkpoint-one',diffId='diff-one',verificationScope=scope)
        for env in ({'TEST_RESTORE_STATE':'running'},{'TEST_SERVICES':'no'},{'TEST_CHECKPOINT_ID':'other'}):
            request=req();p,result=self.apply(request,**env);self.assertNotEqual(p.returncode,0,result)
            before=self.calls.read_text();p,again=self.apply(request);self.assertEqual(before,self.calls.read_text());self.assertEqual(result,again)
        p,result=self.apply(req('files'),TEST_SERVICES='no');self.assertEqual(p.returncode,0,result)
        self.assertEqual(result['facts']['providerJob']['run']['externalReachability'],'not_tested')

    def test_reinstall_single_verified_local_package_no_refresh_restart_or_fallback(self):
        self.script=ROOT/'components/system-packs/istoreos/skills/istoreos-luci-recovery/scripts/reinstall_core.sh'
        artifact=self.root/'selected.ipk';artifact.write_bytes(b'fixture-package')
        self.fake('opkg', '''import os,sys
args=sys.argv[1:]
with open(os.environ['TEST_CALLS'],'a') as log:log.write(' '.join(args)+'\\n')
if args[0]=='install':sys.exit(int(os.environ.get('TEST_INSTALL_EXIT','0')))
version=os.environ.get('TEST_STATUS_VERSION','1.2.3') if args[0]=='status' else '1.2.3'
print('Package: selected\\nVersion: '+version+'\\nStatus: install ok installed\\n')
''')
        def req():return self.operation('package.reinstall',manager='opkg',package='selected',version='1.2.3',artifact=str(artifact),sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())
        p,result=self.apply(req());self.assertEqual(p.returncode,0,result)
        self.assertNotIn('update',self.calls.read_text());self.assertNotIn('service:',self.calls.read_text())
        p,result=self.apply(req(),TEST_INSTALL_EXIT='17');self.assertNotEqual(p.returncode,0);self.assertTrue(result['effects']['unknown'])
        self.calls.write_text('')
        p,result=self.apply(req(),TEST_STATUS_VERSION='9.0');self.assertNotEqual(p.returncode,0)
        self.assertEqual(result['errors'][0]['code'],'PRECONDITION_CHANGED');self.assertNotIn('install --force-reinstall',self.calls.read_text())


class LaunchdOperationTests(WriteFixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.fake('launchctl', r'''import os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['TEST_CALLS'],'a') as f:f.write(' '.join(a)+'\n')
running=Path(os.environ['TEST_RUNNING'])
if a[0]=='print':print('state = '+('running' if running.exists() else 'not running'))
elif os.environ.get('TEST_CONTROL_FAIL'):sys.exit(17)
elif a[0]=='kickstart':
 if not os.environ.get('TEST_FAST_EXIT'):running.touch()
elif a[0]=='kill':running.unlink(missing_ok=True)
''')

    def launch(self, action='kickstart', before='stopped', **env):
        import subprocess
        path=ROOT/'components/system-packs/macos/skills/macos-launchd-logs/scripts/apply.sh'
        p=subprocess.run(['sh',str(path),'system','org.example.fixture',action,before],env={**self.env,'TARGET_CHANGE_APPROVED':'YES',**env},capture_output=True,text=True,timeout=10)
        from test_writes import contract
        return p,contract.validate_result(p.stdout,expected_target='test-target')

    def test_registered_but_stopped_is_not_running_and_fast_exit_fails(self):
        p,result=self.launch(TEST_FAST_EXIT='1');self.assertNotEqual(p.returncode,0)
        self.assertEqual(result['facts']['actualState'],'stopped');self.assertEqual(result['verification']['status'],'failed')
        p,result=self.launch();self.assertEqual(p.returncode,0,result)
        p,result=self.launch('stop','running');self.assertEqual(p.returncode,0,result);self.assertFalse(self.running.exists())

    def test_stale_state_and_native_error_keep_effects_distinct(self):
        p,result=self.launch(before='running');self.assertNotEqual(p.returncode,0);self.assertNotIn('kickstart',self.calls.read_text())
        p,result=self.launch(TEST_CONTROL_FAIL='1');self.assertNotEqual(p.returncode,0);self.assertTrue(result['effects']['unknown'])
        self.assertNotEqual(result['operationStatus'],'succeeded')


if __name__=='__main__':unittest.main()
