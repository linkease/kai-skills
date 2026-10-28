"""Fresh native packaged user journeys, through local and pinned SSH execution."""
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def stage_tree(lab,instance,source,destination):
    payload=io.BytesIO()
    with tarfile.open(fileobj=payload,mode='w') as archive:
        archive.add(source,arcname='.',filter=lambda item:None if '__pycache__' in item.name or item.name.endswith('.pyc') else item)
    lab.exec(instance,'mkdir','-p',destination)
    lab.exec(instance,'tar','-xf','-','-C',destination,data=payload.getvalue())


class Journey:
    def __init__(self,lab,instance,mode,preset,folder):
        self.lab,self.instance,self.mode,self.folder=lab,instance,mode,folder
        self.env=['env','PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'KAI_PLATFORM='+instance['target'],'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
            'ZSETUP_ROOT=/workspace/zsetup','ZSETUP_CACHE_DIR=/workspace/zsetup-cache']
        self.captures={};self.transport=None
        if mode=='on-device':
            stage_tree(lab,instance,preset,'/workspace/preset')
            lab.exec(instance,'sh','/workspace/preset/install.sh','--target','/workspace/skills')
        else:
            controller=folder/'controller-skills'
            subprocess.run(['sh',str(preset/'install.sh'),'--target',str(controller)],check=True,capture_output=True)
            stage=folder/'target-system-skills';stage.mkdir()
            declaration=json.loads((ROOT/'components/composition.json').read_text())
            plan=declaration['presets'][instance['target']+'-remote-control']
            excluded={name for item in plan['transports'] for name in item['skills']}
            import shutil
            for item in controller.iterdir():
                if item.name.startswith('.') or item.name in excluded:continue
                shutil.copytree(item,stage/item.name)
            stage_tree(lab,instance,stage,'/workspace/skills')
            config=folder/'ssh.config'
            proxy=shlex.join([*lab.ssh[:-1],'-W','127.0.0.1:'+instance['port'],lab.host])
            config.write_text('Host '+instance['name']+'\n  HostName 127.0.0.1\n  HostKeyAlias '+instance['name']+
                '\n  ProxyCommand '+proxy+'\n')
            config.chmod(0o600)
            wrapper=folder/'ssh-wrapper'
            wrapper.write_text('#!/bin/sh\nexec ssh -F '+shlex.quote(str(config))+' "$@"\n');wrapper.chmod(0o700)
            self.transport=controller/'target-ssh-controller/scripts/target-ssh.sh'
            self.transport_env={**os.environ,'TARGET_ID':instance['name'],'TARGET_SSH_HOST':instance['name'],
                'TARGET_SSH_USER':'root','TARGET_SSH_PORT':'22','TARGET_SSH_KNOWN_HOSTS':instance['knownHosts'],
                'TARGET_SSH_IDENTITY':instance['key'],'TARGET_SSH_BIN':str(wrapper),
                'TARGET_TIMEOUT_SECONDS':'900','TARGET_CHANGE_APPROVED':'YES'}
        lab.exec(instance,'mkdir','-p','/workspace/logs')

    def capture(self,name,argv,*,env=None,timeout=900):
        environment=self.env if env is None else env
        if self.transport is None:
            value=self.lab.capture_program(self.instance,environment,argv,'/workspace/logs/'+name,timeout=timeout)
        else:
            command=shlex.join([*environment,*argv]);log='/workspace/logs/'+name
            script='set -eu\nlog='+shlex.quote(log)+'\n'+'''\
started=$(date +%s); code=0
'''+command+''' > "$log.stdout" 2> "$log" || code=$?
finished=$(date +%s); digest=$(sha256sum "$log"); digest=${digest%% *}
jq -cn --argjson code "$code" --argjson start "$started" --argjson finished "$finished" --arg digest "$digest" --rawfile stdout "$log.stdout" --rawfile stderr "$log" '{exitCode:$code,startedUnix:$start,finishedUnix:$finished,logSha256:$digest,stdout:$stdout,stderr:$stderr}'
'''
            result=subprocess.run(['sh',str(self.transport),'apply'],input=script,text=True,
                capture_output=True,env=self.transport_env,timeout=timeout+20)
            if result.returncode:raise RuntimeError('pinned target Transport failed: '+result.stderr[-2000:])
            value=json.loads(result.stdout)
        value['execution']='pinned-ssh-target-transport' if self.transport else 'on-device'
        (self.folder/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2))
        self.captures[name]={key:value[key] for key in ['exitCode','startedUnix','finishedUnix','logSha256','execution']}
        return value

    def success(self,name,argv,*,env=None):
        value=self.capture(name,argv,env=env)
        assert value['exitCode']==0,name+': '+value['stderr'][-2200:]+value['stdout'][-1500:]
        return value


def cycle(lab,target,lock,mode,tag,preset,folder):
    instance=lab.create(target,'ms10-'+tag,lock['image']);gateway=None
    receipt={'mode':mode,'cycle':tag,'status':'failed','freshContainer':True,'freshHome':True,
        'freshProject':True,'freshClientCache':True,'freshGatewayCache':True,'journeys':[]}
    receipt['bundle']=json.loads((preset/'preset.json').read_text())
    try:
        journey=Journey(lab,instance,mode,preset,folder)
        boot='/workspace/skills/kai-tool-bootstrap/scripts/tool.sh'
        software='/workspace/skills/kai-software/scripts/software.sh'
        runtime='/workspace/skills/kai-dev-environment/scripts/runtime.sh'
        dependencies='/workspace/skills/kai-project-dependencies/scripts/dependencies.sh'
        usage='/workspace/skills/kai-storage-files/scripts/usage.sh'
        print('JOURNEY '+target+' '+tag+' bootstrap and actual Transport',flush=True)
        journey.success('native-identity',['sh','-c','printf "kernel="; uname -s; printf "uid="; id -u; cat /etc/os-release'])
        journey.success('ensure-mise',['bash',boot,'ensure','mise'])
        journey.success('ensure-client',['bash',boot,'ensure','ks-cli'])
        candidate=lab.stage_client_candidate(instance)
        assert candidate,'MS10 requires the tested source-locked client candidate'
        journey.env+=['KAI_KSCLI_BIN='+candidate['executable'],
            'PATH=/workspace/candidate-bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
        receipt['clientCandidate']=candidate
        gateway=lab.start_gateway(instance)
        receipt['gatewayCandidate']=gateway.get('candidate');receipt['gatewayCapabilities']=gateway['capabilities']
        journey.env+=['KAI_RUNTIME_ACCELERATION=required','KAI_DEP_ACCELERATION=required','MISE_HTTP_TIMEOUT=180s',
                      'PIP_DISABLE_PIP_VERSION_CHECK=1','KAI_USAGE_TEMP_DIR=/workspace/scratch']
        if target=='istoreos':
            # Exercise core creation independently of the full-jq owner rescue cache.
            journey.success('ensure-independent-core',['bash',boot,'ensure','zsetup'])
            baseline=lab.exec(instance,'sha256sum','/etc/ssl/openssl.cnf')
            origin='https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64'
            remap=json.loads(lab.exec(instance,'curl','-fsS','-H','Content-Type: application/json','-d',
                json.dumps({'url':origin}),'http://127.0.0.1:5003/api/domainfold/remap'))
            assert remap['input']==origin and remap['output'].startswith('https://')
            journey.success('ensure-complete-jq',['bash',boot,'ensure','jq'],
                env=journey.env+['JQ_DOWNLOAD_BASE='+remap['output'].rsplit('/',1)[0]])
            journey.env+=['KAI_JQ_BIN=/root/.local/bin/jq']
            journey.success('configure-owned-runtime',['sh','-ec',
                'mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; '
                'touch /etc/config/istoreenhance; uci set istoreenhance.kai_lab=istoreenhance; '
                'uci set istoreenhance.kai_lab.enabled=0; uci set istoreenhance.kai_lab.port=5443; '
                'uci set istoreenhance.kai_lab.adminport=5003; uci commit istoreenhance'])
        else:journey.success('ensure-core',['bash',boot,'ensure','zsetup'])
        core=json.loads(journey.success('core-probe',['bash',boot,'probe','zsetup'])['stdout'])
        assert core['status'] in ['installed','reused']
        journey.env+=['KAI_ZSETUP_BIN='+core['path']];receipt['core']=core
        runtime_home='/workspace/runtime' if target=='istoreos' else '/root'
        journey.success('owned-fixtures',['sh','-ec',
            'mkdir -p /workspace/samples /workspace/external /workspace/scratch /workspace/project "$1/.config/mise" /root/.config/pip; '
            'printf "# preserve selection\\n" > "$1/.config/mise/config.toml"; '
            'printf "[global]\\ndisable-pip-version-check = true\\n" > /root/.config/pip/pip.conf; '
            'printf protected > /workspace/external/protected-marker; '
            'printf known > "/workspace/samples/目标 file.txt"; '
            'dd if=/dev/zero of="/workspace/samples/big file.bin" bs=1048576 count=2; '
            'ln -s /workspace/external /workspace/samples/external-link','owned-fixtures',runtime_home])
        guards=[runtime_home+'/.config/mise/config.toml','/root/.config/pip/pip.conf','/workspace/external/protected-marker']
        before=journey.success('guards-before',['sha256sum',*guards])['stdout']

        print('JOURNEY '+target+' '+tag+' software search/install/use',flush=True)
        journey.success('refresh-internal',['bash',software,'refresh','zsetup'])
        rows=json.loads(journey.success('find-software',['bash',software,'search','linkspace'],
            env=journey.env+['KAI_SOFTWARE_PROVIDER=zsetup'])['stdout'])
        assert len(rows)<=3 and any(row['id']=='zsetup:linkspace' for row in rows)
        installed=json.loads(journey.success('install-software',['bash',software,'install','zsetup:linkspace'])['stdout'])
        product=json.loads((ROOT/'tests/multisystem/usage-lock.json').read_text())['linkspace']
        assert installed['installedVersion']==product['version']
        program='/root/.local/bin/linkspace'
        digest=journey.success('verify-published-software',['sha256sum',program])['stdout'].split()[0]
        assert digest==product['artifacts']['x64']['sha256']
        response=json.loads(journey.success('use-installed-software',['bash',usage,'search','/workspace/samples','目标','3','10'])['stdout'])
        assert any(item['name']=='目标 file.txt' for item in response['data']['items'])
        receipt['journeys'].append({'task':'find-install-use-software','status':'passed','version':installed['installedVersion'],'sha256':digest})

        print('JOURNEY '+target+' '+tag+' SDK and real locked dependency project',flush=True)
        version=json.loads((ROOT/'tests/multisystem/sdk-lock.json').read_text())['python']
        fixture=ROOT/'tests/multisystem/fixtures/dependencies/pip'
        stage_tree(lab,instance,fixture,'/workspace/project')
        lock_before=journey.success('project-lock-before',['sha256sum','/workspace/project/requirements.txt'])['stdout']
        sdk=json.loads(journey.success('install-sdk',['bash',runtime,'install','python',version,'none'])['stdout'])
        assert sdk['runtimeValidation']=='passed' and sdk['scope']=='none'
        package=journey.success('install-project-dependencies',['bash',dependencies,'install','pip',version,'/workspace/project'])
        functional=journey.success('run-real-project',['bash',runtime,'exec','python',version,'--',
            '/workspace/project/.venv/bin/python','/workspace/project/check.py','/workspace/project/.venv'])
        assert 'idna:3.10:venv-functional' in functional['stdout']
        assert journey.success('project-lock-after',['sha256sum','/workspace/project/requirements.txt'])['stdout']==lock_before
        receipt['journeys'].append({'task':'install-sdk-and-run-dependency-project','status':'passed','sdk':sdk,
            'dependency':'idna==3.10','functionalOutput':functional['stdout'].strip(),'projectLockUnchanged':True})

        print('JOURNEY '+target+' '+tag+' bounded space and filename search',flush=True)
        space=json.loads(journey.success('analyze-space',['bash',usage,'space','/workspace/samples','3','10'])['stdout'])['data']
        assert space['complete'] and len(space['topFiles'])<=3 and space['topFiles'][0]['allocatedBytes']==2*1024**2
        assert space['topFiles'][0]['storagePath']=='/workspace/samples/big file.bin'
        search=json.loads(journey.success('search-files',['bash',usage,'search','/workspace/samples','目标','2','10'])['stdout'])['data']
        assert len(search['items'])==1 and search['items'][0]['name']=='目标 file.txt'
        persistence=json.loads(journey.success('storage-persistence',['bash',usage,'storage','/workspace/project','1048576'])['stdout'])
        assert persistence['persistence']=='persistent' and persistence['eligibleForInstall']
        assert journey.success('guards-after',['sha256sum',*guards])['stdout']==before
        receipt['journeys'].append({'task':'space-and-file-search','status':'passed','scope':'/workspace/samples',
            'topFile':space['topFiles'][0],'match':search['items'][0],'persistence':persistence['persistence']})
        logs=lab.remote('cat',gateway['helper']['work']+'/work/gateway.log');(folder/'gateway.log').write_text(logs)
        events=[json.loads(row.removeprefix('download observation ')) for row in logs.splitlines() if row.startswith('download observation ')]
        instances={row['instanceId'] for row in events};assert len(instances)==1
        frozen=json.loads((ROOT/'tests/multisystem/dependencies-lock.json').read_text())['packages']['python']
        def in_window(row):
            value=datetime.datetime.fromisoformat(row['finishedAt'].replace('Z','+00:00')).timestamp()
            return package['startedUnix']<=value<package['finishedUnix']+1
        passed=[row for row in events if in_window(row) and row['tls'] and row['listenPort']==5443 and row['status']==200 and row['transportCompleted']]
        wheels=[row for row in passed if row['sha256']==frozen['sha256'] and row['bytes']>0 and frozen['file'] in row['path']]
        metadata=[row for row in passed if row['host'].startswith('dl-pypi.linkease.net:') and '/simple/idna' in row['path']]
        assert wheels and metadata,'current-instance pip metadata/artifact traversal is missing'
        receipt['currentDependencyTraversal']={'status':'passed','instanceId':next(iter(instances)),
            'metadata':metadata,'artifact':wheels,'artifactSha256':frozen['sha256'],'nativeProjectPassed':True,
            'gatewayLogSha256':hashlib.sha256(logs.encode()).hexdigest(),'freshGatewayCache':True}
        if target=='istoreos':
            lab.exec(instance,'sh','-ec','sha256sum -c /usr/share/kai-lab/system-curl.sha256')
            assert lab.exec(instance,'sha256sum','/etc/ssl/openssl.cnf')==baseline
            receipt['systemCurlAndSSLUnchanged']=True
        receipt.update(status='passed',globalConfigurationAndProtectedMarkerUnchanged=True,captures=journey.captures)
        return receipt
    finally:
        try:
            if gateway:
                try:(folder/'gateway.log').write_text(lab.remote('cat',gateway['helper']['work']+'/work/gateway.log'))
                finally:lab.stop_gateway(gateway)
        finally:
            lab.cleanup(instance);receipt['cleanup']='passed'
            (folder/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2))


def run_distribution(lab,target,lock):
    lab.capacity(minimum=5*1024**3)
    record={'schemaVersion':1,'milestone':'MS10','target':target,'status':'failed','imageLock':lock,'cycles':[]}
    folder=lab.state/('MS10-evidence-'+target);folder.mkdir(mode=0o700,exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix='ms10-presets-',dir=lab.state) as temporary:
            output=Path(temporary)/'platforms'
            subprocess.run(['sh',str(ROOT/'tools/generate-platforms.sh'),str(output)],check=True,capture_output=True)
            for mode,tag in [('on-device','on-device'),('remote-control','remote-control'),('on-device','fresh-repeat')]:
                current=folder/tag;current.mkdir(mode=0o700)
                try:
                    cycle(lab,target,lock,mode,tag,output/target/mode,current)
                finally:
                    receipt=current/'receipt.json'
                    if receipt.is_file():record['cycles'].append(json.loads(receipt.read_text()))
        assert len(record['cycles'])==3 and all(len(c['journeys'])==3 for c in record['cycles'])
        ms7=ROOT/'docs/verification/multisystem-ms7-results.json';linked=json.loads(ms7.read_text())
        assert linked['status']=='passed'
        record['ms7ChannelEvidence']={'status':'linked-prior-validation','source':'multisystem-ms7-results.json',
            'sha256':hashlib.sha256(ms7.read_bytes()).hexdigest(),
            'meaning':'Prior ten-channel proof remains separate from this cycle current-instance Python/pip observations.',
            'currentGatewayCandidate':{key:lab.gateway_candidate[key] for key in ['sha256','sourceCommit']},
            'currentClientCandidate':{key:lab.client_candidate[key] for key in ['sha256','sourceCommit']}}
        record.update(status='passed',requiredJourneys=6,freshRepeatJourneys=3,cleanup='passed')
    finally:
        (lab.state/('MS10-'+target+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2))
    print(json.dumps({'target':target,'status':record['status'],'requiredJourneys':6,'freshRepeatJourneys':3}),flush=True)
