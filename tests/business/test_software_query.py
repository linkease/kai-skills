import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'components/system-packs/common/skills'

class QueryTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.bin=self.root/'bin';self.bin.mkdir()
        for name in ('kai-software','kai-tool-bootstrap'):shutil.copytree(SOURCE/name,self.root/name)
        self.scripts=self.root/'kai-software/scripts';self.request=self.root/'request.json'
        self.log=self.root/'calls';self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'KAI_PLATFORM':'ubuntu','ZSETUP_TASK_TARGET_ID':'local','KAI_QUERY_LOG':str(self.log)}
        self.fake('apt-cache',"""printf '%s\\n' "$*" >> "$KAI_QUERY_LOG"
case "$1" in search) for i in $(seq 1 10000);do printf 'tool-%s - tool\\n' "$i";done; printf 'tool - exact\\n' ;;
policy) printf '  Candidate: 1.2\\n' ;; *) exit 99 ;; esac""")
        self.fake('dpkg-query',"printf 'install ok installed\\t1.0\\n'")
        self.fake('apt-get',"echo WRITER >> \"$KAI_QUERY_LOG\";exit 99")
    def fake(self,name,body):
        p=self.bin/name;p.write_text('#!/bin/sh\nset -eu\n'+body+'\n');p.chmod(0o700)
    def call(self,action='search',**request):
        self.request.write_text(json.dumps({'targetId':'local',**request}))
        p=subprocess.run(['sh',str(self.scripts/'query-entry.sh'),action,str(self.request)],capture_output=True,text=True,env=self.env,timeout=25)
        self.assertTrue(p.stdout.strip(),p.stderr);result=json.loads(p.stdout)
        self.assertLessEqual(len(p.stdout.encode()),8192);self.assertEqual(result['effects'],[])
        return p,result
    def test_large_native_catalog_exact_and_partial(self):
        p,r=self.call(query='tool');self.assertEqual(p.returncode,0,r)
        self.assertEqual(r['items'][0]['id'],'apt:tool');self.assertEqual(len(r['items']),1)
        p,r=self.call(query='directory');self.assertEqual(p.returncode,0,r)
        self.assertEqual(len(r['items']),3);self.assertTrue(r['hasMore'])
        self.assertNotIn('WRITER',self.log.read_text())
    def test_opkg_search_stays_a_search_instead_of_inspecting_a_null_identity(self):
        self.env['KAI_PLATFORM']='openwrt'
        self.fake('opkg',"""printf '%s\\n' "$*" >> "$KAI_QUERY_LOG"
case "$1" in list) printf 'tool - 1 - helper\\nother-tool - 1 - helper\\n' ;;
info) printf 'Version: 1\\n' ;; status) printf 'Version: 1\\nStatus: install ok installed\\n' ;; *) exit 99 ;; esac""")
        p,r=self.call(query='helper',provider='opkg');self.assertEqual(p.returncode,0,r)
        self.assertTrue(r['items']);self.assertIn('list',self.log.read_text())

    def test_bash_32_query_runs_the_same_contract(self):
        bash=os.environ.get('KAI_DESKTOP_BASH32')
        if not bash:self.skipTest('Bash 3.2 required')
        self.env['KAI_BASH_BIN']=bash
        p,r=self.call(query='tool');self.assertEqual(p.returncode,0,r);self.assertEqual(r['protocol'],'software-query/v1')

    def test_apk_names_are_filtered_locally_without_network_or_versions_guessed(self):
        self.env['KAI_PLATFORM']='openwrt'
        self.fake('apk',"printf '%s\\n' \"$*\" >> \"$KAI_QUERY_LOG\";printf 'jq-extra\\njq\\n'")
        p,r=self.call(query='jq',provider='apk');self.assertEqual(p.returncode,0,r)
        self.assertEqual(r['items'][0]['id'],'apk:jq');self.assertNotIn('candidateVersion',r['items'][0])
        self.assertIn('--no-network search',self.log.read_text())

    def test_detail_and_invalid_requests(self):
        p,r=self.call('detail',id='apt:tool');self.assertEqual(p.returncode,0,r)
        self.assertEqual(r['items'][0]['installedVersion'],'1.0')
        for req in ({'query':'tool','limit':11},{'query':'tool','targetId':'other'},{'query':'-all'},{'query':'tool','limit':True},{'query':'tool','limit':False}):
            p,r=self.call(**req);self.assertNotEqual(p.returncode,0,r)
    def test_docker_local_scope_and_no_credentials(self):
        self.env['KAI_PLATFORM']='linux'
        self.fake('docker',"""printf '%s\\n' "$*" >> "$KAI_QUERY_LOG"
case "$*" in
*'context inspect'*) printf '%s\\n' '[{"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}]' ;;
*'image ls'*) printf '%s\\n' '{"ID":"sha256:abcd","Repository":"example/web","Tag":"latest","Digest":"sha256:123","Env":["PASSWORD=never-send"]}' ;;
*'container ls'*) printf '%s\\n' '{"ID":"abc123","Names":"web","Image":"example/web:latest","State":"running","Env":["PASSWORD=never-send"]}' ;;
*) exit 99 ;; esac""")
        p,r=self.call(query='web',provider='docker');self.assertEqual(p.returncode,0,r)
        self.assertEqual({x['kind'] for x in r['items']},{'image','container'})
        self.assertNotIn('never-send',json.dumps(r));self.assertTrue(all(x['scope'].startswith('local-') for x in r['items']))
        p,r=self.call('inspect',id='docker-container:abc123',provider='docker');self.assertEqual(len(r['items']),1,r)
        self.assertNotIn('pull',self.log.read_text())
    def test_brew_cask_native_fields_without_manifest(self):
        self.env['KAI_PLATFORM']='macos'
        self.fake('brew',"""printf '%s\\n' "$*" >> "$KAI_QUERY_LOG"
case "$1" in search) echo viewer ;;
info) printf '%s\\n' '{"casks":[{"token":"viewer","tap":"homebrew/cask","name":["Viewer"],"desc":"A viewer","version":"2","installed":"1","artifacts":{"secret":"never-send"}}]}' ;;
*) exit 99 ;; esac""")
        p,r=self.call(query='viewer',provider='brew-cask');self.assertEqual(p.returncode,0,r)
        self.assertEqual(r['items'][0]['id'],'brew-cask:homebrew/cask/viewer')
        self.assertNotIn('never-send',json.dumps(r))
    def test_brew_core_short_full_name_keeps_complete_identity(self):
        self.env['KAI_PLATFORM']='macos'
        self.fake('brew',"printf '%s\\n' '{\"formulae\":[{\"name\":\"tree\",\"full_name\":\"tree\",\"tap\":\"homebrew/core\",\"versions\":{\"stable\":\"1\"},\"installed\":[]}]}'")
        p,r=self.call('detail',id='brew:homebrew/core/tree');self.assertEqual(p.returncode,0,r)
        self.assertEqual(r['items'][0]['id'],'brew:homebrew/core/tree')

    def test_inspect_uses_existing_owner_and_marks_runtime_unknown(self):
        p,r=self.call('inspect',software='bash');self.assertEqual(p.returncode,0,r)
        self.assertNotIn('decision',r['items'][0]);self.assertNotIn('runtimeVersion',r['items'][0])
    def test_istore_fuzzy_query_keeps_catalog_private_and_exact_name_first(self):
        for name in ('istoreos-app-search','istoreos-app-diagnostics'):
            shutil.copytree(ROOT/'components/system-packs/istoreos/skills'/name,self.root/name)
        self.env['KAI_PLATFORM']='istoreos'
        fixture=self.root/'store.json'
        apps=[{'name':'a%dviewer'%i,'title':'Viewer','description':'private description '*500} for i in range(8)]
        apps.append({'name':'viewer','title':'Viewer','description':'exact'})
        fixture.write_text(json.dumps({'result':{'apps':apps}}));self.env['ISTORE_STORE_RESPONSE_FILE']=str(fixture)
        p,r=self.call(query='viewer',provider='istore');self.assertEqual(p.returncode,0,r)
        self.assertEqual(len(r['items']),3);self.assertTrue(r['hasMore']);self.assertEqual(r['items'][0]['id'],'istore:viewer')
        self.assertNotIn('private description',p.stdout)

    def test_provider_identity_and_whole_json_are_never_silently_cut(self):
        self.env['KAI_PLATFORM']='macos'
        for field,value in [('full_name','homebrew/core/'+'x'*300),('version','v'*9000)]:
            data={'formulae':[{'name':'tool','full_name':'homebrew/core/tool','versions':{'stable':'1'},'installed':[]}]}
            if field=='version':data['formulae'][0]['versions']['stable']=value
            else:data['formulae'][0][field]=value
            self.fake('brew',"printf '%s\\n' '"+json.dumps(data)+"'")
            p,r=self.call('detail',id='brew:homebrew/core/tool')
            self.assertNotEqual(p.returncode,0,r);self.assertEqual(r['items'],[])

    def test_independent_package_query_runs_without_sibling_checkout(self):
        import sys
        sys.path.insert(0,str(ROOT/'tools/business'))
        from model import Distribution
        from package import build_package
        directory=self.root/'single'/'kai-software'
        build_package(Distribution(),'kai-software',directory)
        self.request.write_text(json.dumps({'targetId':'local','query':'tool'}))
        p=subprocess.run(['sh',str(directory/'scripts/query-entry.sh'),'search',str(self.request)],env=self.env,text=True,capture_output=True,timeout=25)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(json.loads(p.stdout)['items'][0]['id'],'apt:tool')

    def test_projection_bounds_long_unicode_and_rejects_oversized_identity(self):
        row={'id':'apt:tool','name':'tool','description':'树'*10000,'rawManifest':'never-send'}
        p=subprocess.run(['jq','-c','--arg','action','search','--arg','target','local','--arg','query','tool','--arg','status','success','--arg','reason','','--argjson','native','null','--argjson','limit','3','-f',str(self.scripts/'query/result.jq')],input=json.dumps([row]),text=True,capture_output=True)
        self.assertEqual(p.returncode,0,p.stderr);r=json.loads(p.stdout)
        self.assertEqual(len(r['items'][0]['description']),240);self.assertNotIn('never-send',p.stdout)

class NativeWindowsQueryTests(unittest.TestCase):
    def setUp(self):
        self.pwsh=os.environ.get('KAI_DESKTOP_PWSH') or shutil.which('pwsh')
        if not self.pwsh:self.skipTest('native PowerShell required')
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.scripts=self.root/'scripts'
        shutil.copytree(SOURCE/'kai-software/scripts',self.scripts)
        self.request=self.root/'request.json'
        self.env={**os.environ,'ZSETUP_TASK_TARGET_ID':'local','PATH':'/no-bash-or-jq-here'}
        fake=r'''$ErrorActionPreference='Stop'
$request=[Console]::In.ReadToEnd()|ConvertFrom-Json
if($request.action -notin @('search','info')){throw 'writer called'}
$source=[IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$items=@()
for($i=0;$i -lt 40;$i++){$items+=@{id=($source+':main/tool'+$i);name=('tool'+$i);description=('树'*2000);source=$source;type='package';rawManifest='never-send'}}
$items+=@{id=($source+':main/tool');name='tool';description='exact';source=$source;type='package';rawManifest='never-send'}
ConvertTo-Json -InputObject $items -Depth 5 -Compress
'''
        for name in ('scoop','winget'):(self.scripts/(name+'.ps1')).write_text(fake, encoding='utf-8-sig')
    def call(self,**req):
        self.request.write_text(json.dumps({'targetId':'local','query':'tool',**req}))
        p=subprocess.run([self.pwsh,'-NoProfile','-NonInteractive','-File',str(self.scripts/'query-entry.ps1'),'-Operation','search','-RequestFile',str(self.request)],env=self.env,text=True,capture_output=True,timeout=25)
        self.assertTrue(p.stdout.strip(),p.stderr);r=json.loads(p.stdout);self.assertLessEqual(len(p.stdout.encode()),8192)
        return p,r
    def test_without_bash_or_jq_preserves_sources_exact_first_and_budget(self):
        p,r=self.call();self.assertEqual(p.returncode,0,r)
        self.assertEqual(len(r['items']),3);self.assertTrue(r['hasMore'])
        self.assertEqual({i['source'] for i in r['items'][:2]},{'scoop','winget'})
        self.assertTrue(all(i['name']=='tool' for i in r['items'][:2]));self.assertNotIn('never-send',p.stdout)
        self.assertTrue(all(len(i.get('description',''))<=240 for i in r['items']))
    def test_native_query_overrides_ascii_pipeline_and_preserves_unicode_subject(self):
        # Emulate Windows PowerShell's ASCII pipeline default using real pwsh.
        for name in ('scoop','winget'):
            path=self.scripts/(name+'.ps1')
            path.write_text(path.read_text(encoding='utf-8-sig').replace("$source=[IO.Path]", "[IO.File]::WriteAllText($env:QUERY_NATIVE_SUBJECT,[string]$request.subject)\n$source=[IO.Path]"),encoding='utf-8-sig')
        marker=self.root/'subject.txt';self.env['QUERY_NATIVE_SUBJECT']=str(marker)
        self.request.write_text(json.dumps({'targetId':'local','query':'工具','provider':'scoop'}))
        entry=str(self.scripts/'query-entry.ps1').replace("'","''");request=str(self.request).replace("'","''")
        command="$OutputEncoding=[Text.Encoding]::ASCII;& '"+entry+"' -Operation search -RequestFile '"+request+"'"
        p=subprocess.run([self.pwsh,'-NoProfile','-NonInteractive','-Command',command],env=self.env,text=True,capture_output=True,timeout=25)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr);self.assertEqual(marker.read_text(),'工具')

    def test_actual_scoop_search_module_finds_exact_names_across_buckets(self):
        for bucket in ('a-first','z-last'):
            directory=self.root/'scoop/buckets'/bucket/'bucket';directory.mkdir(parents=True)
            for i in range(35):(directory/('tool%d.json'%i)).write_text(json.dumps({'version':'1','description':'tool'}))
            if bucket=='z-last':(directory/'tool.json').write_text(json.dumps({'version':'1'}))
        module=SOURCE/'kai-software/scripts/scoop/search.ps1'
        script=self.root/'search-test.ps1'
        script.write_text(". '"+str(module)+"'\nfunction Property($value,$name){return $value.$name}\nfunction Scoop-Info($root,$bucket,$name){return @{id=('scoop:'+$bucket+'/'+$name);name=$name}}\n$rows=@(Scoop-Search '"+str(self.root/'scoop')+"' 'tool' 4);ConvertTo-Json -InputObject $rows -Compress\n")
        p=subprocess.run([self.pwsh,'-NoProfile','-NonInteractive','-File',str(script)],text=True,capture_output=True,timeout=25)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual([x['id'] for x in json.loads(p.stdout)],['scoop:z-last/tool'])

    def test_validation_is_native_and_does_not_start_providers(self):
        for req in ({'limit':11},{'targetId':'wrong'},{'limit':True},{'command':'install'}):
            p,r=self.call(**req);self.assertNotEqual(p.returncode,0,r);self.assertEqual(r['items'],[])

if __name__=='__main__':unittest.main()
