import json
import hashlib
import datetime
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'components/system-packs/common/skills/kai-download-acceleration/scripts/accelerate.sh'
EVIDENCE = CLI.with_name('evidence.sh')


class AccelerationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai acceleration 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.source = self.work / 'source'; self.source.write_bytes(b'hello\n')
        self.dest = self.work / 'download file'
        self.calls = self.work / 'calls.jsonl'
        self.native = self.work / 'ks-cli'
        self.native.write_text('#!' + sys.executable + '\n'
            'import json,os,sys\nfrom pathlib import Path\n'
            'args=sys.argv[1:]\n'
            'with open(os.environ["TEST_CALLS"],"a") as f:f.write(json.dumps(args)+"\\n")\n'
            'if os.environ.get("TEST_NATIVE_EXIT"):\n'
            ' if os.environ.get("TEST_STDOUT_FAILURE"):\n'
            '  print(json.dumps({"status":"failed","error_kind":"dns"}));print(json.dumps({"error":{"code":"DOWNLOAD_FAILED"}}))\n'
            ' sys.exit(int(os.environ["TEST_NATIVE_EXIT"]))\n'
            'if args[0]=="doctor":\n print(json.dumps({"schema_version":1,"tool":args[1] if args[1]!="--json" else "service","overall":"pass"}));sys.exit()\n'
            'if args[0]=="--explain":\n print(json.dumps({"schema_version":1,"command":args[2:],"environment":{}}));sys.exit()\n'
            'if args[0]=="--strict":\n assert args[1:3]==["docker","pull"];sys.exit()\n'
            'if args[0]=="git":\n'
            ' import subprocess\n'
            ' original=args[-2];target=args[-1];args[-2]=os.environ["TEST_GIT_SOURCE"]\n'
            ' result=subprocess.run(["git",*args[1:]])\n'
            ' if result.returncode==0:subprocess.run(["git","-C",target,"remote","set-url","origin",original],check=True)\n'
            ' sys.exit(result.returncode)\n'
            'assert args[0]=="download"\n'
            'Path(args[args.index("-O")+1]).write_bytes(Path(os.environ["TEST_SOURCE"]).read_bytes())\n'
            'print(json.dumps({"status":"ok","selected":os.environ.get("TEST_SELECTED","admin_proxy"),"strategy":"adaptive_race","mode":next(a.split("=",1)[1] for a in args if a.startswith("--mode=")),"attempts":[{"type":"origin","bytes":int(os.environ.get("TEST_ORIGIN_BYTES","0"))},{"type":"admin_proxy","bytes":6,"selected":True}]}))\n')
        self.native.chmod(0o700)
        self.env = {**os.environ, 'HOME': str(self.work), 'KAI_KSCLI_BIN': str(self.native),
                    'TEST_CALLS': str(self.calls), 'TEST_SOURCE': str(self.source)}
        self.sha = '5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03'
        self.url = 'https://github.com/example/project/releases/download/v1/file.bin?literal=$HOME;echo'

    def call(self, *args, **env):
        return subprocess.run(['bash', str(CLI), *map(str, args)], env={**self.env, **env},
                              capture_output=True, text=True, timeout=10)

    def test_file_is_verified_and_reused_without_global_changes(self):
        p = self.call('download', self.url, self.dest, self.sha)
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        receipt = json.loads(p.stdout)
        self.assertEqual(receipt['sha256'], self.sha)
        self.assertEqual(self.dest.read_bytes(), b'hello\n')
        calls = self.calls.read_text()
        args = json.loads(calls)
        self.assertIn('--allow-start=false', args)
        self.assertIn('--mode=auto', args)
        self.assertEqual(args[-1], self.url)
        again = self.call('download', self.url, self.dest, self.sha)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(json.loads(again.stdout)['status'], 'reused')
        self.assertEqual(self.calls.read_text(), calls)
        self.assertFalse(list(self.work.glob('.kai-download.*')))

    def test_bad_hash_never_activates_download(self):
        p = self.call('download', self.url, self.dest, '0' * 64)
        self.assertEqual(p.returncode, 4, p.stderr + p.stdout)
        self.assertEqual(json.loads(p.stdout)['category'], 'integrity')
        self.assertFalse(self.dest.exists())
        self.assertFalse(list(self.work.glob('.kai-download.*')))

    def test_explicit_route_mode_is_forwarded_and_invalid_mode_does_not_download(self):
        invalid = self.call('download', self.url, self.dest, self.sha, KAI_DOWNLOAD_MODE='typo')
        self.assertEqual(invalid.returncode, 2)
        self.assertFalse(self.calls.exists())
        for mode in ['direct', 'accelerated', 'race']:
            with self.subTest(mode=mode):
                target = self.work / mode
                result = self.call('download', self.url, target, self.sha, KAI_DOWNLOAD_MODE=mode)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('--mode=' + mode, json.loads(self.calls.read_text().splitlines()[-1]))
                self.assertEqual(target.read_bytes(), b'hello\n')

    def test_auto_direct_selection_passes_content_without_claiming_acceleration(self):
        result = self.call('download', self.url, self.dest, self.sha, TEST_SELECTED='origin')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['download']['mode'], 'auto')
        self.assertEqual(receipt['download']['selected'], 'origin')
        self.assertEqual(receipt['accelerationValidation'], 'direct-selected-no-acceleration-claim')
        self.assertEqual(receipt['contentValidation'], 'passed')

    def test_auto_keeps_origin_probe_bytes_separate_from_the_selected_gateway(self):
        result = self.call('download', self.url, self.dest, self.sha, TEST_ORIGIN_BYTES='131072')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['download']['selected'], 'admin_proxy')
        self.assertEqual(receipt['download']['attempts'][0]['type'], 'origin')
        self.assertEqual(receipt['download']['attempts'][0]['bytes'], 131072)
        self.assertEqual(receipt['download']['attempts'][1]['bytes'], 6)
        self.assertEqual(receipt['accelerationValidation'], 'pending-current-instance-evidence')

    def test_foreign_destination_and_credentials_are_preserved(self):
        self.dest.write_text('keep')
        p = self.call('download', self.url, self.dest, self.sha)
        self.assertEqual(p.returncode, 4)
        self.assertEqual(self.dest.read_text(), 'keep')
        self.assertFalse(self.calls.exists())
        p = self.call('download', 'https://secret@github.com/o/r/a', self.work/'new', self.sha)
        self.assertEqual(p.returncode, 2)
        self.assertFalse(self.calls.exists())

    def test_native_failure_code_is_preserved(self):
        p = self.call('download', self.url, self.dest, self.sha, TEST_NATIVE_EXIT='23')
        self.assertEqual(p.returncode, 23, p.stderr + p.stdout)
        self.assertEqual(json.loads(p.stdout)['nativeExitCode'], 23)
        self.assertFalse(self.dest.exists())

    def test_multiple_native_json_failure_records_keep_the_original_code(self):
        p=self.call('download',self.url,self.dest,self.sha,TEST_NATIVE_EXIT='23',TEST_STDOUT_FAILURE='1')
        self.assertEqual(p.returncode,23,p.stderr+p.stdout)
        receipt=json.loads(p.stdout)
        self.assertEqual(receipt['nativeResult'][0]['error_kind'],'dns')
        self.assertFalse(self.dest.exists())

    def test_doctor_and_explain_delegate_read_only_native_contracts(self):
        doctor = self.call('doctor', 'mise')
        self.assertEqual(doctor.returncode, 0, doctor.stderr + doctor.stdout)
        self.assertEqual(json.loads(doctor.stdout)['overall'], 'pass')
        explain = self.call('explain', 'git', '--', 'clone', 'https://github.com/o/r')
        self.assertEqual(explain.returncode, 0, explain.stderr + explain.stdout)
        self.assertEqual(json.loads(explain.stdout)['command'], ['git', 'clone', 'https://github.com/o/r'])
        self.assertEqual([json.loads(x) for x in self.calls.read_text().splitlines()],
                         [['doctor', 'mise', '--json'], ['--explain', '--json', 'git', 'clone', 'https://github.com/o/r']])

    def test_git_commit_and_global_configuration_are_preserved(self):
        source = self.work/'git source'; source.mkdir()
        (self.work/'.gitconfig').write_text('[user]\n name = preserved\n email = preserved@example.invalid\n')
        config = (self.work/'.gitconfig').read_bytes()
        for args in [['init','-q',str(source)], ['-C',str(source),'add','.'],
                     ['-C',str(source),'commit','-qm','fixture']]:
            if args[0]=='-C' and 'add' in args:
                (source/'known.txt').write_text('verified source\n')
            subprocess.run(['git',*args],env=self.env,check=True,capture_output=True)
        commit = subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],env=self.env,text=True).strip()
        target = self.work/'checked source 中文'
        p = self.call('git-clone','https://github.com/example/repository.git',target,commit,TEST_GIT_SOURCE=str(source))
        self.assertEqual(p.returncode,0,p.stderr+p.stdout)
        self.assertEqual(json.loads(p.stdout)['commit'],commit)
        self.assertEqual((target/'known.txt').read_text(),'verified source\n')
        calls = self.calls.read_text()
        again = self.call('git-clone','https://github.com/example/repository.git',target,commit,TEST_GIT_SOURCE=str(source))
        self.assertEqual(again.returncode,0,again.stderr+again.stdout)
        self.assertEqual(json.loads(again.stdout)['status'],'reused')
        self.assertEqual(self.calls.read_text(),calls)
        self.assertEqual((self.work/'.gitconfig').read_bytes(),config)
        bad = self.call('git-clone','https://github.com/example/repository.git',self.work/'bad commit','0'*40,TEST_GIT_SOURCE=str(source))
        self.assertEqual(bad.returncode,4,bad.stderr+bad.stdout)
        self.assertFalse((self.work/'bad commit').exists())

    def test_current_instance_metadata_and_artifact_evidence(self):
        client = self.work/'client.log'; client.write_text('native invocation and verified result\n')
        gateway = self.work/'gateway.log'; manifest = self.work/'manifest.json'
        epoch = datetime.datetime(2026,10,27,12,tzinfo=datetime.timezone.utc).timestamp()
        requests = [{'role':'metadata','method':'GET','host':'dl-pypi.linkease.net:5443','path':'/simple/idna/'},
                    {'role':'artifact','method':'GET','host':'dl-pypi-files.linkease.net:5443','path':'/idna.whl','sha256':self.sha}]
        template = {'schemaVersion':1,'channel':'pip','instanceId':'current-instance','tlsPort':5443,
                    'window':{'startUnix':epoch,'endUnix':epoch+10},'requireCold':True,'gatewayFresh':True,
                    'client':{'exitCode':0,'contentValidation':'passed','functionalValidation':'passed','cacheCold':True,
                              'directObserved':False,'logSha256':hashlib.sha256(client.read_bytes()).hexdigest()},
                    'requests':requests}
        events = [{**r,'schemaVersion':1,'instanceId':'current-instance','requestId':i+1,'listenPort':5443,'tls':True,
                   'startedAt':'2026-10-27T12:00:01.125Z','finishedAt':'2026-10-27T12:00:02.125Z',
                   'status':200,'bytes':6,'sha256':self.sha,'transportCompleted':True} for i,r in enumerate(requests)]
        for failure in ['none','instance','port','window','hash','direct','cached-client','missing-metadata']:
            with self.subTest(failure=failure):
                current=json.loads(json.dumps(template)); rows=json.loads(json.dumps(events))
                if failure=='instance':rows[1]['instanceId']='old-instance'
                if failure=='port':rows[1]['listenPort']=5444
                if failure=='window':current['window']['startUnix']+=100;current['window']['endUnix']+=100
                if failure=='hash':rows[1]['sha256']='0'*64
                if failure=='direct':current['client']['directObserved']=True
                if failure=='cached-client':current['client']['cacheCold']=False
                if failure=='missing-metadata':rows=rows[1:]
                manifest.write_text(json.dumps(current))
                gateway.write_text('\n'.join('download observation '+json.dumps(r) for r in rows)+'\n')
                p=subprocess.run(['bash',str(EVIDENCE),str(manifest),str(client),str(gateway)],env=self.env,
                                 capture_output=True,text=True,timeout=10)
                self.assertEqual(p.returncode,0 if failure=='none' else 4,p.stderr+p.stdout)
                if failure=='none':self.assertEqual(json.loads(p.stdout)['accelerationValidation'],'confirmed')

    def test_docker_preserves_the_digest_and_does_not_edit_daemon_config(self):
        bin = self.work/'bin';bin.mkdir()
        docker=bin/'docker'
        digest='sha256:'+'a'*64
        docker.write_text('#!'+sys.executable+'\nimport json,sys\n'
            'if sys.argv[1]=="info":print(json.dumps({"ID":"private-daemon","DockerRootDir":"/private/lab","Driver":"vfs","RegistryConfig":{"Mirrors":["https://registry.linkease.net:5443/"]}}))\n'
            'else:print(json.dumps(["hello-world@'+digest+'"]))\n')
        docker.chmod(0o700)
        config=self.work/'daemon.json';config.write_text('{"keep":true}')
        image='docker.io/library/hello-world@'+digest
        p=self.call('docker-pull',image,PATH=str(bin)+':'+os.environ['PATH'])
        self.assertEqual(p.returncode,0,p.stderr+p.stdout)
        receipt=json.loads(p.stdout)
        self.assertEqual(receipt['digest'],digest)
        self.assertEqual(receipt['daemon']['dataRoot'],'/private/lab')
        self.assertEqual(config.read_text(),'{"keep":true}')
        self.assertEqual([json.loads(x) for x in self.calls.read_text().splitlines()],
                         [['doctor','--json'],['--strict','docker','pull',image]])


if __name__ == '__main__':
    unittest.main()
