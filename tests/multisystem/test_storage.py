import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
USAGE = ROOT / 'components/system-packs/common/skills/kai-storage-files/scripts/usage.sh'
DEV = ROOT / 'components/system-packs/common/skills/kai-dev-environment/scripts/dev-cli.sh'


class UsageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='kai usage 中文 ');self.addCleanup(self.temp.cleanup)
        self.work=Path(self.temp.name);self.scope=self.work/'范围 with spaces';self.scope.mkdir()
        self.scratch=self.work/'scratch';self.scratch.mkdir();self.calls=self.work/'calls.jsonl'
        self.linkspace=self.work/'linkspace';self.linkspace.write_text('#!'+sys.executable+'\n'
            'import json,os,sys\na=sys.argv[1:]\n'
            'with open(os.environ["TEST_CALLS"],"a") as f:f.write(json.dumps(a)+"\\n")\n'
            'if a==["version"]:print(json.dumps({"schemaVersion":1,"version":"v0.1.0"}));sys.exit()\n'
            'if os.environ.get("TEST_BAD_JSON"):print("not a result envelope");sys.exit()\n'
            'if "--help" in a and ("--" not in a or a.index("--help")<a.index("--")):print(json.dumps({"schemaVersion":1,"status":"succeeded","result":{"usage":"help"}}));sys.exit()\n'
            'code=int(os.environ.get("TEST_LINKSPACE_EXIT","0"))\n'
            'data={"root":a[a.index("--path")+1],"items":[],"topFiles":[],"complete":code==0}\n'
            'print(json.dumps({"schemaVersion":1,"status":"succeeded" if not code else "failed","result":data,"error":{"code":"partial","details":data}}))\n'
            'sys.exit(code)\n');self.linkspace.chmod(0o700)
        self.zsetup=self.work/'zsetup';self.zsetup.write_text('#!'+sys.executable+'\n'
            'import json,os,sys\nassert sys.argv[1]=="storage" and sys.argv[-1]=="--json"\n'
            'print(os.environ["TEST_STORAGE_FACTS"])\n');self.zsetup.chmod(0o700)
        self.env={**os.environ,'HOME':str(self.work),'KAI_PLATFORM':'ubuntu','TEST_CALLS':str(self.calls),
            'KAI_LINKSPACE_BIN':str(self.linkspace),'KAI_ZSETUP_BIN':str(self.zsetup),
            'KAI_USAGE_TEMP_DIR':str(self.scratch),'KAI_USAGE_PYTHON':sys.executable}

    def call(self,*args,**env):
        return subprocess.run(['bash',str(USAGE),*map(str,args)],env={**self.env,**env},cwd=self.work,
                              capture_output=True,text=True,timeout=10)

    def test_linkspace_literal_query_is_scoped_bounded_and_read_only(self):
        term='目标 $(touch HACKED); * " literal'
        result=self.call('search',self.scope,term,7,3)
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        receipt=json.loads(result.stdout);self.assertEqual(receipt['tool'],'linkspace')
        args=json.loads(self.calls.read_text().splitlines()[-1])
        self.assertEqual(args[0],'query');self.assertEqual(args.count(term),1);self.assertIn('--source',args)
        for flag,value in [('--path',str(self.scope)),('--limit','7'),('--timeout','3s'),('--temp-dir',str(self.scratch))]:
            self.assertEqual(args[args.index(flag)+1],value)
        self.assertFalse((self.work/'HACKED').exists());self.assertEqual(list(self.scope.iterdir()),[])

    def test_option_like_search_term_is_not_executed_as_native_help(self):
        (self.scope/'--help target.txt').write_text('known')
        for backend in ['linkspace','native']:
            with self.subTest(backend=backend):
                result=self.call('search',self.scope,'--help',3,3,KAI_USAGE_BACKEND=backend)
                self.assertEqual(result.returncode,0,result.stderr+result.stdout)
                self.assertEqual(json.loads(result.stdout)['data'].get('root'),str(self.scope))

    def test_unpublished_linkspace_architecture_uses_the_declared_native_fallback(self):
        (self.scope/'目标.txt').write_text('known')
        result=self.call('search',self.scope,'目标',3,3,KAI_TARGET_ARCH='mips')
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        self.assertEqual(json.loads(result.stdout)['tool'],'python-stdlib')

    def test_partial_observations_keep_native_exit_and_incomplete_status(self):
        result=self.call('space',self.scope,5,3,TEST_LINKSPACE_EXIT='11')
        self.assertEqual(result.returncode,11,result.stderr+result.stdout)
        receipt=json.loads(result.stdout);self.assertEqual(receipt['status'],'partial')
        self.assertFalse(receipt['data']['complete']);self.assertEqual(receipt['nativeExitCode'],11)
        result=self.call('space',self.scope,5,3,TEST_LINKSPACE_EXIT='37')
        self.assertEqual(result.returncode,37)

    def test_success_without_a_native_result_is_not_reported_as_complete(self):
        result=self.call('space',self.scope,5,3,TEST_BAD_JSON='1')
        self.assertEqual(result.returncode,4,result.stderr+result.stdout)
        self.assertEqual(json.loads(result.stdout)['category'],'result-unavailable')

    def test_invalid_or_unbounded_scope_never_executes_linkspace(self):
        for args in [('space','/'),('space',self.work/'absent'),('space',self.scope,0),('search',self.scope,'',3),('space',self.scope,1001)]:
            result=self.call(*args);self.assertNotEqual(result.returncode,0,args)
        self.assertFalse(self.calls.exists())

    def test_storage_facts_not_free_bytes_determine_install_eligibility(self):
        for kind,memory,classification,eligible in [('ext4',False,'persistent',True),('tmpfs',True,'temporary',False),
                ('overlay',None,'container-layer',False),('aufs',False,'container-layer',False),('unrecognized',None,'unknown',False)]:
            with self.subTest(kind=kind):
                facts={'schema_version':1,'probed_path':str(self.scope),'mount_point':'/data mount',
                    'filesystem_type':kind,'memory_backed':memory,'available_bytes':10**12,
                    'read_only':False,'noexec':False,'writable':True}
                result=self.call('storage',self.scope,1048576,TEST_STORAGE_FACTS=json.dumps(facts))
                self.assertEqual(result.returncode,0,result.stderr+result.stdout)
                receipt=json.loads(result.stdout);self.assertEqual(receipt['persistence'],classification)
                self.assertEqual(receipt['eligibleForInstall'],eligible);self.assertEqual(receipt['facts'],facts)
        self.assertEqual(list(self.scope.iterdir()),[])

    def test_native_fallback_scans_real_files_without_following_external_links(self):
        (self.scope/'大 file.bin').write_bytes(b'x'*16384)
        target=self.scope/'目标 $(touch HACKED).txt';target.write_text('known')
        protected=self.work/'outside marker';protected.write_text('preserved')
        (self.scope/'outside link').symlink_to(self.work,target_is_directory=True)
        result=self.call('space',self.scope,5,3,KAI_USAGE_BACKEND='native')
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        receipt=json.loads(result.stdout);self.assertEqual(receipt['tool'],'python-stdlib')
        self.assertEqual(receipt['data']['topFiles'][0]['path'],str(self.scope/'大 file.bin'))
        result=self.call('search',self.scope,'$(touch',5,3,KAI_USAGE_BACKEND='native')
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        self.assertEqual([r['path'] for r in json.loads(result.stdout)['data']['items']],[str(target)])
        self.assertEqual(protected.read_text(),'preserved');self.assertFalse((self.work/'HACKED').exists())

    def test_native_entry_budget_reports_partial_instead_of_complete(self):
        for n in range(5):(self.scope/str(n)).write_text('known')
        result=self.call('space',self.scope,5,3,KAI_USAGE_BACKEND='native',KAI_USAGE_MAX_ENTRIES='2')
        self.assertEqual(result.returncode,11,result.stderr+result.stdout)
        receipt=json.loads(result.stdout);self.assertFalse(receipt['data']['complete'])
        self.assertEqual(receipt['data']['stopReason'],'entry_limit')


class DeveloperCLITests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='kai developer cli 中文 ');self.addCleanup(self.temp.cleanup)
        self.work=Path(self.temp.name);self.root=self.work/'managed uv';self.root.mkdir()
        self.calls=self.work/'mise-calls.jsonl'
        self.uv=self.root/'uv';self.uv.write_text('#!'+sys.executable+'\nimport json,os,sys\n'
            'a=sys.argv[1:]\n'
            'if a==["--version"]:print("uv 0.8.22")\n'
            'elif a==["cache","dir"]:print(os.environ["UV_CACHE_DIR"])\n'
            'elif a==["fail"]:sys.exit(37)\n'
            'else:print(json.dumps(a,ensure_ascii=False))\n');self.uv.chmod(0o700)
        self.mise=self.work/'mise';self.mise.write_text('#!'+sys.executable+'\nimport json,os,sys,subprocess\n'
            'a=sys.argv[1:]\n'
            'with open(os.environ["TEST_CALLS"],"a") as f:f.write(json.dumps(a)+"\\n")\n'
            'if a[0]=="where":\n'
            ' if os.environ.get("TEST_MISSING"):sys.exit(4)\n'
            ' print(os.environ["TEST_ROOT"])\n'
            'elif a[0]=="which":print(os.environ["TEST_EXE"])\n'
            'elif a[0]=="install":sys.exit(int(os.environ.get("TEST_INSTALL_CODE","0")))\n'
            'elif a[0]=="exec":sys.exit(subprocess.run(a[a.index("--")+1:]).returncode)\n'
            'else:sys.exit(91)\n');self.mise.chmod(0o700)
        self.env={**os.environ,'HOME':str(self.work),'KAI_PLATFORM':'ubuntu','KAI_MISE_BIN':str(self.mise),
            'KAI_RUNTIME_ACCELERATION':'none','TEST_CALLS':str(self.calls),'TEST_ROOT':str(self.root),
            'TEST_EXE':str(self.uv),'UV_CACHE_DIR':str(self.work/'uv cache')}

    def call(self,*args,**env):
        return subprocess.run(['bash',str(DEV),*map(str,args)],env={**self.env,**env},capture_output=True,text=True,timeout=10)

    def test_exact_managed_cli_probe_and_real_subcommand(self):
        result=self.call('probe','uv','0.8.22');self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        receipt=json.loads(result.stdout);self.assertEqual(receipt['executable'],str(self.uv))
        result=self.call('exec','uv','0.8.22','--','cache','dir')
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout.strip(),self.env['UV_CACHE_DIR'])
        args=['中文 space','','$(touch nope)','a;b','\\native\\path']
        result=self.call('exec','uv','0.8.22','--',*args)
        self.assertEqual(json.loads(result.stdout),args)
        self.assertTrue(all(c[0]!='install' for c in map(json.loads,self.calls.read_text().splitlines())))

    def test_missing_probe_does_not_install_and_foreign_executable_is_rejected(self):
        result=self.call('probe','uv','0.8.22',TEST_MISSING='1');self.assertEqual(result.returncode,4)
        foreign=self.work/'foreign';foreign.write_text('#!/bin/sh\ntouch "'+str(self.work/'unexpected')+'"\n');foreign.chmod(0o700)
        result=self.call('probe','uv','0.8.22',TEST_EXE=str(foreign))
        self.assertEqual(result.returncode,4,result.stderr+result.stdout);self.assertFalse((self.work/'unexpected').exists())

    def test_explicit_install_and_native_failures_keep_scope_and_status(self):
        result=self.call('install','uv','0.8.22');self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        calls=list(map(json.loads,self.calls.read_text().splitlines()));self.assertIn(['install','uv@0.8.22'],calls)
        self.assertTrue(all(c[0]!='use' for c in calls))
        result=self.call('exec','uv','0.8.22','--','fail');self.assertEqual(result.returncode,37)
        result=self.call('install','uv','0.8.22',TEST_INSTALL_CODE='23');self.assertEqual(result.returncode,23)


if __name__=='__main__':unittest.main()
