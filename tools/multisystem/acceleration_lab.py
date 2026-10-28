"""MS7 native acceptance. All execution uses public target programs and files."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = '/workspace/canonical/common/skills/kai-download-acceleration/scripts/accelerate.sh'
EVIDENCE = ROOT / 'components/system-packs/common/skills/kai-download-acceleration/scripts/evidence.sh'


class AccelerationAudit:
    def __init__(self, lab, target):
        self.lab, self.target = lab, target
        self.lock = json.loads((ROOT / 'tests/multisystem/acceleration-lock.json').read_text())
        self.packages = json.loads((ROOT / 'tests/multisystem/dependencies-lock.json').read_text())['packages']
        self.folder = lab.state / ('MS7-evidence-' + target)
        self.folder.mkdir(exist_ok=True, mode=0o700)
        self.records, self.negatives, self.failures = [], [], []
        self.channel = 'setup'
        self.env = None

    def bind(self, instance, gateway, env, runtime, dependencies, versions):
        self.instance, self.gateway, self.env = instance, gateway, env
        self.runtime, self.dependencies, self.versions = runtime, dependencies, versions
        self.ks = self.lab.exec(instance, *env, 'sh', '-ec',
            'command -v ks-cli || { test -x /root/.local/bin/ks-cli; echo /root/.local/bin/ks-cli; }')
        assert 'download-observation.v1' in gateway['capabilities']['capabilities']

    def save_gateway(self, gateway):
        text = self.lab.remote('cat', gateway['helper']['work'] + '/work/gateway.log')
        (self.folder / (self.channel + '-gateway.log')).write_text(text)

    def capture(self, argv, name, env=None):
        result = self.lab.capture_program(self.instance, env or self.env, argv, '/workspace/ms7-' + name + '.log')
        (self.folder / (name + '-client.json')).write_text(json.dumps(result, indent=2))
        return result

    def missing_service(self, instance, env):
        self.instance, self.env = instance, env
        ks = next((e.split('=',1)[1] for e in env if e.startswith('KAI_KSCLI_BIN=')),
                  '/usr/bin/ks-cli' if self.target == 'istoreos' else '/root/.local/bin/ks-cli')
        result = self.capture([ks, 'doctor', '--json'], 'missing-service')
        passed = result['exitCode'] != 0 and 'service_health' in result['stdout']
        self.negatives.append({'case':'missing-service','status':'passed' if passed else 'failed','nativeExitCode':result['exitCode'],'logSha256':result['logSha256']})
        if not passed: self.failures.append('missing-service')

    def events(self):
        self.save_gateway(self.gateway)
        path = self.folder / (self.channel + '-gateway.log')
        return path, [json.loads(row.removeprefix('download observation ')) for row in path.read_text().splitlines()
                      if row.startswith('download observation ')]

    def prove(self, channel, captures, requests, *, commit=None, direct=False, error=None):
        gateway_log, events = self.events()
        body = ''.join('stdout:\n'+r['stdout']+'\nstderr:\n'+r['stderr']+'\n' for r in captures)
        client_log = self.folder / (channel + '-client.log'); client_log.write_text(body)
        instances = {e['instanceId'] for e in events}
        manifest = {'schemaVersion':1,'channel':channel,'instanceId':next(iter(instances)) if len(instances)==1 else '',
                    'tlsPort':5443,'window':{'startUnix':min(r['startedUnix'] for r in captures),
                    'endUnix':max(r['finishedUnix'] for r in captures)+1},'requireCold':True,'gatewayFresh':True,
                    'client':{'exitCode':next((r['exitCode'] for r in captures if r['exitCode']),0),
                    'contentValidation':'passed','functionalValidation':'not-required' if channel=='file' else 'passed',
                    'cacheCold':True,'directObserved':direct,'logSha256':hashlib.sha256(body.encode()).hexdigest()},'requests':requests}
        if commit:
            manifest['expected']={'commit':commit};manifest['client']['commit']=commit
        path=self.folder/(channel+'-manifest.json');path.write_text(json.dumps(manifest,indent=2))
        result=subprocess.run(['bash',str(EVIDENCE),str(path),str(client_log),str(gateway_log)],capture_output=True,text=True)
        proof=json.loads(result.stdout) if result.stdout.strip() else {'status':'failed','error':result.stderr}
        record={'channel':channel,'status':'passed' if result.returncode==0 and not error else 'failed',
                'proof':proof,'gatewaySource':self.gateway.get('candidate'),'nativeLogSha256':[r['logSha256'] for r in captures]}
        if error: record['diagnosis']=error
        self.records.append(record)
        if record['status']!='passed': self.failures.append(channel)
        print('ACCELERATION '+self.target+' '+channel+' '+record['status'],flush=True)
        return manifest, gateway_log, client_log

    @staticmethod
    def request(role, host, path, sha=None, method='GET'):
        result={'role':role,'method':method,'host':host,'path':path}
        if sha:result['sha256']=sha
        return result

    def basic_lane(self, lane):
        if lane=='file':
            item=self.lock['file']
            result=self.capture(['bash',SCRIPT,'download',item['url'],'/workspace/ms7 verified file',item['sha256']],'file')
            assert result['exitCode']==0,result
            receipt=json.loads(result['stdout']);assert receipt['download']['selected']=='admin_proxy'
            self.file_proof=self.prove('file',[result],[self.request('artifact','gh.linkease.net',urlsplit(item['url']).path,item['sha256'])])
        elif lane=='git':
            item=self.lock['git']
            result=self.capture(['bash',SCRIPT,'git-clone',item['repository'],'/workspace/ms7 Git 中文',item['commit']],
                                'git',self.env+['GIT_TRACE_CURL=1','GIT_TRACE_CURL_NO_DATA=1'])
            assert result['exitCode']==0,result
            receipt=json.loads(result['stdout']);assert receipt['commit']==item['commit'] and receipt['tree']==item['tree']
            assert re.search(r'certificate verification ok|ssl certificate verify ok',result['stderr'],re.I) and 'gh.linkease.net' in result['stderr']
            self.prove('git',[result],[self.request('metadata','gh.linkease.net:5443','/octocat/Hello-World.git/info/refs'),
                self.request('artifact','gh.linkease.net:5443','/octocat/Hello-World.git/git-upload-pack',method='POST')],commit=item['commit'])
        else:
            self.docker_lane()

    def docker_lane(self):
        lab=self.lab;name=self.instance['name']+'-docker';started=False
        env=self.env+['PATH=/workspace/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'DOCKER_HOST=unix:///workspace/docker-lab/docker.sock','DOCKER_CONTEXT=','DOCKER_CONFIG=/workspace/docker-lab/client-config']
        try:
            lab.exec(self.instance,'mkdir','-p','/workspace/bin','/workspace/docker-lab/client-config')
            lab.remote('docker','cp','/rom/usr/bin/docker',self.instance['name']+':/workspace/bin/docker')
            assert lab.exec(self.instance,'sha256sum','/workspace/bin/docker').split()[0]=='a58da24ee613a92b898718575a56bf1ebf5d3d8a536e5b33dbaaa01abcba33cf'
            lab.exec(self.instance,'sh','-ec','umask 077; printf \'{"registry-mirrors":["https://registry.linkease.net:5443"]}\\n\' > /workspace/docker-lab/daemon.json')
            lab.remote('docker','run','-d','--name',name,*lab.label_args(),'--network','container:'+self.instance['name'],
                '--cap-add','SYS_ADMIN','--security-opt','apparmor=unconfined','--memory','768m','--memory-swap','768m','--cpus','1','--pids-limit','256',
                '--mount','type=bind,src='+self.instance['work']+'/work,dst=/workspace',lab.prepare('istoreos')['image'],
                'sh','-ec','mkdir -p /tmp/run /tmp/lock; exec /usr/bin/dockerd "$@" > /workspace/docker-lab/daemon.log 2>&1','private-daemon',
                '--host=unix:///workspace/docker-lab/docker.sock','--data-root=/workspace/docker-lab/data','--exec-root=/workspace/docker-lab/exec',
                '--pidfile=/workspace/docker-lab/pid','--config-file=/workspace/docker-lab/daemon.json','--storage-driver=vfs',
                '--iptables=false','--bridge=none','--ip-forward=false','--ip-masq=false','--debug')
            started=True
            for _ in range(30):
                try:
                    info=json.loads(lab.exec(self.instance,*env,'docker','info','--format','{{json .}}',timeout=10))
                    assert info['DockerRootDir']=='/workspace/docker-lab/data' and info['Driver']=='vfs' and info['Images']==0
                    break
                except (RuntimeError,ValueError,AssertionError):time.sleep(1)
            else:raise RuntimeError('private Docker daemon readiness failed')
            item=self.lock['docker'];result=self.capture(['bash',SCRIPT,'docker-pull',item['image']],'docker',env)
            assert result['exitCode']==0,result
            logs=lab.exec(self.instance,'cat','/workspace/docker-lab/daemon.log')
            assert re.search(r'Trying to pull hello-world from https://registry\.linkease\.net:5443/',logs)
            direct=bool(re.search(r'Trying to pull hello-world from https://(?!registry\.linkease\.net:5443/)',logs))
            prefix='/v2/library/hello-world/'
            self.prove('docker',[result],[self.request(role,'registry.linkease.net:5443',prefix+part+'sha256:'+item[key],item[key])
                for role,part,key in [('metadata','manifests/','manifestSha256'),('artifact','blobs/','configSha256'),('artifact','blobs/','layerSha256')]],direct=direct)
        finally:
            if started:
                try:(self.folder/'docker-daemon.log').write_text(lab.exec(self.instance,'cat','/workspace/docker-lab/daemon.log'))
                finally:lab.inspect_owned('container',name);lab.remote('docker','rm','-f',name)

    def hashes(self, directory, pattern):
        code='''import base64,hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);out=[]
for p in sorted(root.glob(sys.argv[2])):
 if p.is_symlink() or not p.is_file():continue
 if p.stat().st_size>256*1024**2:raise ValueError("archive hash inspection bound")
 with p.open("rb") as f:a=hashlib.file_digest(f,"sha256").hexdigest()
 with p.open("rb") as f:b=base64.b64encode(hashlib.file_digest(f,"sha512").digest()).decode()
 out.append({"file":p.name,"sha256":a,"sha512":"sha512-"+b,"bytes":p.stat().st_size})
print(json.dumps(out))'''
        return json.loads(self.lab.exec(self.instance,*self.env,'KAI_RUNTIME_ACCELERATION=none','bash',self.runtime,'exec',
            'python',self.versions['python'],'--','python','-c',code,directory,pattern,timeout=120))

    def sdk(self, sdk, captured):
        home='/workspace/runtime' if self.target=='istoreos' else '/root'
        archives=self.hashes(home+'/.local/share/mise/downloads/'+sdk+'/'+self.versions[sdk],'*.tar.*')
        _,events=self.events();requests=[];diagnosis=[]
        host={'python':'dl-github.linkease.net:5443','node':('dl-node-unofficial.linkease.net:5443' if self.target=='istoreos' else 'dl-nodejs-org.linkease.net:5443'),'go':'dl-go-sdk.linkease.net:5443'}[sdk]
        urls=re.findall(r'DEBUG (?:GET|HEAD) (https?://[^\s]+)',captured['stderr'])
        wire=[]
        for url in urls:
            parsed=urlsplit(url)
            if parsed.hostname=='127.0.0.1' and re.match(r'^/[0-9]+/',parsed.path):
                wire.append('/'+parsed.path.split('/',2)[2])
        for archive in archives:
            paths=[p for p in wire if p.endswith('/'+archive['file'])]
            if not paths:
                # A canonical download URL remains independent of gateway observations.
                paths=[urlsplit(u).path for u in re.findall(r'https://[^\s]+',captured['stderr']) if urlsplit(u).path.endswith('/'+archive['file'])]
            if paths:requests.append(self.request('artifact',host,paths[0],archive['sha256']))
        metadata=[p for p in wire if p.endswith(('.json','.txt','.sha256')) or p.startswith('/tools/python-precompiled-')]
        if metadata:
            metadata_host='dl-mise-versions.linkease.net:5443' if metadata[0].startswith('/tools/') else host
            requests.append(self.request('metadata',metadata_host,metadata[0]))
        else:
            diagnosis.append('No supported SDK metadata request observed at the gateway; do not infer API coverage from the archive wrapper.')
        if not archives:diagnosis.append('No independently client-verified retained SDK archive available.')
        self.prove('sdk-'+sdk,[captured],requests,error='; '.join(diagnosis) or None)

    def package(self, manager, project, env, installed, functional, metadata):
        captures=([metadata] if metadata else [])+[installed,functional]
        if manager=='npm':
            packed=self.capture(['bash',self.dependencies,'run','npm',self.versions['node'],project,'--','pack','is-number@7.0.0','--pack-destination',project,'--json'],'npm-pack',env)
            assert packed['exitCode']==0,packed
            captures.append(packed)
            files=self.hashes(project,'is-number-7.0.0.tgz');assert len(files)==1 and files[0]['sha512']==self.packages['npm']['integrity']
            requests=[self.request('metadata','dl-npm.linkease.net:5443','/is-number'),self.request('artifact','dl-npm.linkease.net:5443','/is-number/-/is-number-7.0.0.tgz',files[0]['sha256'])]
        elif manager in ['pip','uv']:
            item=self.packages['python']
            requests=[self.request('metadata','dl-pypi.linkease.net:5443','/simple/idna/'),self.request('artifact','dl-pypi-files.linkease.net:5443',urlsplit(item['url']).path,item['sha256'])]
        else:
            files=self.hashes(project+'/.cache/go-mod/cache/download/github.com/google/uuid/@v','v1.6.0.zip');assert len(files)==1
            requests=[self.request('metadata','dl-golang.linkease.net:5443','/github.com/google/uuid/@v/v1.6.0.mod'),
                      self.request('artifact','dl-golang.linkease.net:5443','/github.com/google/uuid/@v/v1.6.0.zip',files[0]['sha256'])]
        self.prove('go-modules' if manager=='go' else manager,captures,requests)

    def negative_cases(self):
        m,gateway,client=self.file_proof
        for case,change in [('wrong-window',lambda x:x['window'].update(startUnix=x['window']['startUnix']+86400,endUnix=x['window']['endUnix']+86400)),
                            ('wrong-port',lambda x:x.update(tlsPort=5444)),('client-direct',lambda x:x['client'].update(directObserved=True))]:
            negative=json.loads(json.dumps(m));change(negative)
            path=self.folder/(case+'.json');path.write_text(json.dumps(negative))
            result=subprocess.run(['bash',str(EVIDENCE),str(path),str(client),str(gateway)],capture_output=True,text=True)
            passed=result.returncode==4
            self.negatives.append({'case':case,'status':'passed' if passed else 'failed'})
            if not passed:self.failures.append(case)
        result=self.capture(['bash',SCRIPT,'download',self.lock['file']['url'],'/workspace/ms7-invalid-file','0'*64],'hash-mismatch')
        assert result['exitCode']==4 and not self.lab.exec(self.instance,'sh','-c','test ! -e /workspace/ms7-invalid-file || echo exists')
        self.negatives.append({'case':'hash-mismatch','status':'passed','nativeExitCode':json.loads(result['stdout'])['nativeExitCode']})
        result=self.capture([self.ks,'download','--mode=direct','--allow-start=false','--retry=0','--connect-timeout=2s','--read-timeout=2s',
            '-O','/workspace/ms7-dns-file','https://kai-does-not-exist.invalid/file'],'dns-failure')
        assert result['exitCode']!=0 and any(word in (result['stdout']+result['stderr']).lower() for word in ['dns','lookup','no such host']),result
        self.negatives.append({'case':'dns-failure','status':'passed','nativeExitCode':result['exitCode']})
        result=self.capture(['bash',self.runtime,'exec','node',self.versions['node'],'--',self.ks,'npm',
            'view','is-number@7.0.0','--json'],'wrong-port-native',
            self.env+['KSPEEDER_PORT=9','npm_config_fetch_retries=0','npm_config_fetch_timeout=2000',
                      'npm_config_cache=/workspace/ms7-wrong-port-cache'])
        assert result['exitCode']!=0 and any(word in (result['stdout']+result['stderr']).lower()
            for word in ['econnrefused','connection refused','gateway','service']),result
        self.negatives.append({'case':'wrong-port-native','status':'passed','nativeExitCode':result['exitCode'],'logSha256':result['logSha256']})
        self.capability_and_tls_fixture()

    def capability_and_tls_fixture(self):
        fixture=self.lab.config.get('capabilityFixture')
        if not fixture:
            self.failures.append('capability/TLS native fixture not configured');return
        payload=Path(fixture['path']).read_bytes();assert hashlib.sha256(payload).hexdigest()==fixture['sha256']
        child=self.lab.create(self.target,'ms7-capability-fixture',self.lab.prepare(self.target)['image'])
        try:
            self.lab.exec(child,'sh','-ec','cat > /workspace/service-fixture; chmod 700 /workspace/service-fixture',data=payload)
            copied=self.instance['work']+'/work/capability-client'
            self.lab.remote('docker','cp','-L',self.instance['name']+':'+self.ks,copied)
            self.lab.remote('docker','cp',copied,child['name']+':/workspace/ks-cli')
            self.lab.exec(child,'sh','-ec','mkdir -p /workspace/bin; printf \'#!/bin/sh\\necho unexpected > /workspace/tool-executed\\nexit 99\\n\' > /workspace/bin/npm; chmod 700 /workspace/bin/npm')
            if self.target=='istoreos':
                self.lab.exec(child,'sh','-ec','touch /etc/config/istoreenhance; uci set istoreenhance.kai_lab=istoreenhance; uci set istoreenhance.kai_lab.port=5443; uci set istoreenhance.kai_lab.adminport=5003; uci commit istoreenhance')
            self.lab.remote('docker','exec','-d',child['name'],'sh','-c','exec /workspace/service-fixture > /workspace/service.log 2>&1')
            for _ in range(20):
                try:self.lab.exec(child,'curl','-fsS','--max-time','1','http://127.0.0.1:5003/api/summary');break
                except RuntimeError:time.sleep(.2)
            env=['env','PATH=/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
            result=self.lab.capture_program(child,env,['/workspace/ks-cli','doctor','npm','--json'],'/workspace/caps.log')
            (self.folder/'missing-capability-client.json').write_text(json.dumps(result,indent=2))
            assert result['exitCode']!=0 and 'service_capabilities' in result['stdout'],result
            assert not self.lab.exec(child,'sh','-c','test ! -e /workspace/tool-executed || echo executed')
            self.negatives.append({'case':'missing-capability','status':'passed','nativeExitCode':result['exitCode'],'logSha256':result['logSha256']})
            # A standalone loopback HTTP origin tests native direct classification
            # independently of public WAN availability. It is not a TLS fallback.
            direct=self.lab.capture_program(child,env,['/workspace/ks-cli','download','--mode=direct',
                '--allow-start=false','--json','--retry=0','-O','/workspace/native-direct-file',
                'http://127.0.0.1:5003/direct-content'],'/workspace/direct.log')
            (self.folder/'client-direct-native-client.json').write_text(json.dumps(direct,indent=2))
            assert direct['exitCode']==0 and json.loads(direct['stdout'])['strategy']=='direct',direct
            digest=self.lab.exec(child,'sha256sum','/workspace/native-direct-file').split()[0]
            assert digest==hashlib.sha256(b'kai native direct origin fixture\n').hexdigest()
            self.negatives.append({'case':'client-direct-native','status':'passed','contentValidation':'passed',
                'accelerationValidation':'direct','source':'independent-loopback-HTTP-origin',
                'sha256':digest,'logSha256':direct['logSha256']})
            tls=self.lab.capture_program(child,env,['/workspace/ks-cli','download','--mode=direct','--allow-start=false','--retry=0',
                '-O','/workspace/no-trust','https://localhost:5443/file'],'/workspace/tls.log')
            (self.folder/'tls-failure-client.json').write_text(json.dumps(tls,indent=2))
            assert tls['exitCode']!=0 and any(word in (tls['stdout']+tls['stderr']).lower() for word in ['x509','certificate','tls']),tls
            self.negatives.append({'case':'tls-failure','status':'passed','nativeExitCode':tls['exitCode'],'logSha256':tls['logSha256']})
        finally:self.lab.cleanup(child)

    def result(self):
        required={'file','git','docker','sdk-python','sdk-node','sdk-go','npm','pip','uv','go-modules'}
        required_negative={'missing-service','missing-capability','wrong-port','wrong-port-native','dns-failure','tls-failure','hash-mismatch','client-direct','client-direct-native','wrong-window'}
        missing=required-{x['channel'] for x in self.records}
        missing_negative=required_negative-{x['case'] for x in self.negatives if x['status']=='passed'}
        return {'status':'passed' if not (self.failures or missing or missing_negative) else 'failed',
                'channels':self.records,'negative':self.negatives,'missingChannels':sorted(missing),
                'missingNegative':sorted(missing_negative),'failures':self.failures}
