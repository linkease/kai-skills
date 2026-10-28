"""Native MS8 acceptance against published products and owned filesystem samples."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
BOOT='/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
SOFTWARE='/workspace/canonical/common/skills/kai-software/scripts/software.sh'
USAGE='/workspace/canonical/common/skills/kai-storage-files/scripts/usage.sh'
DEV='/workspace/canonical/common/skills/kai-dev-environment/scripts/dev-cli.sh'


def run_usage(lab,target,image_lock):
    lab.capacity(minimum=2*1024**3)
    product=json.loads((ROOT/'tests/multisystem/usage-lock.json').read_text())
    instance=lab.create(target,'ms8-usage',image_lock['image']);gateway=None
    folder=lab.state/('MS8-evidence-'+target);folder.mkdir(exist_ok=True,mode=0o700)
    receipt={'schemaVersion':1,'milestone':'MS8','target':target,'status':'failed',
             'imageLock':image_lock,'positive':[],'negative':[],'captures':{}}
    env=['env','PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
         'KAI_PLATFORM='+target,'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
         'ZSETUP_ROOT=/workspace/zsetup','ZSETUP_CACHE_DIR=/workspace/zsetup-cache']

    def capture(name,args,environment=None,user=None):
        value=lab.capture_program(instance,environment or env,args,'/workspace/logs/'+name+'.log',user=user)
        (folder/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2))
        receipt['captures'][name]={'exitCode':value['exitCode'],'logSha256':value['logSha256'],
            'startedUnix':value['startedUnix'],'finishedUnix':value['finishedUnix']}
        return value

    try:
        lab.stage_skills(instance)
        lab.exec(instance,'sh','-ec','mkdir /workspace/logs; chown 65534:65534 /workspace/logs; chmod 700 /workspace/logs')
        print('USAGE '+target+' prepare published programs',flush=True)
        lab.exec(instance,*env,'bash',BOOT,'ensure','mise',timeout=480)
        lab.exec(instance,*env,'bash',BOOT,'ensure','ks-cli',timeout=480)
        candidate=lab.stage_client_candidate(instance)
        if candidate:
            env+=['KAI_KSCLI_BIN='+candidate['executable'],
                  'PATH=/workspace/candidate-bin:/root/.local/bin:'+lab.exec(instance,'sh','-c','printf %s "$PATH"')]
            receipt['clientCandidate']=candidate
        gateway=lab.start_gateway(instance)
        env+=['KAI_RUNTIME_ACCELERATION=required','MISE_HTTP_TIMEOUT=180s']
        if target=='istoreos':
            original=lab.exec(instance,'sha256sum','/etc/ssl/openssl.cnf')
            origin='https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64'
            remap=json.loads(lab.exec(instance,'curl','-fsS','-H','Content-Type: application/json',
                '-d',json.dumps({'url':origin}),'http://127.0.0.1:5003/api/domainfold/remap'))
            assert remap['input']==origin and remap['output'].startswith('https://')
            value=capture('prepare-jq',['bash',BOOT,'ensure','jq'],
                          env+['JQ_DOWNLOAD_BASE='+remap['output'].rsplit('/',1)[0]])
            assert value['exitCode']==0,value
            env+=['KAI_JQ_BIN=/root/.local/bin/jq']
            lab.exec(instance,'sh','-ec','mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; '
                'touch /etc/config/istoreenhance; uci set istoreenhance.kai_lab=istoreenhance; '
                'uci set istoreenhance.kai_lab.enabled=0; uci set istoreenhance.kai_lab.port=5443; '
                'uci set istoreenhance.kai_lab.adminport=5003; uci commit istoreenhance')
        else:
            lab.exec(instance,*env,'bash',BOOT,'ensure','zsetup',timeout=480)
        core_probe=json.loads(lab.exec(instance,*env,'bash',BOOT,'probe','zsetup'))
        assert core_probe['status'] in ['reused','installed'],core_probe
        core=core_probe['path'];receipt['bootstrapCore']=core_probe
        env+=['KAI_ZSETUP_BIN='+core]
        result=capture('refresh-catalog',['bash',SOFTWARE,'refresh','zsetup']);assert result['exitCode']==0,result
        result=capture('install-linkspace',['bash',SOFTWARE,'install','zsetup:linkspace']);assert result['exitCode']==0,result
        installation=json.loads(result['stdout']);assert installation['installedVersion']==product['linkspace']['version'],installation
        binary='/root/.local/bin/linkspace'
        digest=lab.exec(instance,'sha256sum',binary).split()[0]
        assert digest==product['linkspace']['artifacts']['x64']['sha256']
        version=json.loads(lab.exec(instance,binary,'version'));assert version['version']==product['linkspace']['version']
        receipt['linkspace']={'installation':installation,'version':version,'sha256':digest,'publishedMetadata':product['linkspace']}
        print('USAGE '+target+' published Linkspace installed and verified',flush=True)

        # Run scans as an actual unprivileged UID. chmod 000 must not be tested
        # through root's permission bypass. These paths belong only to this run.
        lab.exec(instance,*env,'sh','-ec','chmod 711 /workspace; mkdir -p /workspace/bin /workspace/unprivileged-home /workspace/scratch /workspace/readable /workspace/external; '
            'cp -L "$1" /workspace/bin/linkspace; cp -L "$2" /workspace/bin/zsetup; '
            'jq_path="${KAI_JQ_BIN:-$(command -v jq)}"; cp -L "$jq_path" /workspace/bin/jq; '
            'chmod 755 /workspace/bin /workspace/bin/*; '
            'chown 65534:65534 /workspace/unprivileged-home /workspace/scratch /workspace/readable; '
            'chmod 700 /workspace/unprivileged-home /workspace/scratch; chmod 755 /workspace/readable /workspace/external; '
            'dd if=/dev/zero of="/workspace/readable/big file.bin" bs=1048576 count=2; '
            'printf known > "/workspace/readable/目标 file.txt"; printf literal > "/workspace/readable/--help target.txt"; '
            'dd if=/dev/zero of="/workspace/readable/sparse file.bin" bs=1 count=1 seek=67108863; '
            'dd if=/dev/zero of=/workspace/external/outside-big.bin bs=1048576 count=8; '
            'printf preserved > /workspace/external/protected-marker; '
            'ln -s /workspace/external /workspace/readable/external-link; '
            'chmod 644 "/workspace/readable/big file.bin" "/workspace/readable/目标 file.txt" "/workspace/readable/--help target.txt" "/workspace/readable/sparse file.bin" /workspace/external/*',
            'fixture',binary,core,timeout=60)
        assert lab.exec(instance,'sha256sum','/workspace/bin/linkspace').split()[0]==digest
        protected=lab.exec(instance,'sha256sum','/workspace/external/protected-marker','/workspace/external/outside-big.bin')
        source_paths=['/workspace/readable/'+name for name in ['big file.bin','目标 file.txt','--help target.txt','sparse file.bin']]
        source_before=lab.exec(instance,'sha256sum',*source_paths)
        unpriv=['env','HOME=/workspace/unprivileged-home','PATH=/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'KAI_PLATFORM='+target,'KAI_LINKSPACE_BIN=/workspace/bin/linkspace','KAI_ZSETUP_BIN=/workspace/bin/zsetup',
            'KAI_JQ_BIN=/workspace/bin/jq','KAI_USAGE_TEMP_DIR=/workspace/scratch']
        assert lab.exec(instance,*unpriv,'id','-u',user='65534:65534')=='65534'
        result=capture('space-readable',['bash',USAGE,'space','/workspace/readable','3','10'],unpriv,'65534:65534')
        assert result['exitCode']==0,result
        data=json.loads(result['stdout'])['data'];assert data['complete'] and len(data['topFiles'])<=3,data
        assert data['topFiles'][0]['storagePath']=='/workspace/readable/big file.bin',data
        assert data['topFiles'][0]['allocatedBytes']==2*1024**2,data
        receipt['positive'].append({'case':'published-space-known-size','status':'passed','uid':65534,'result':data})
        for name,term,expected in [('unicode-search','目标','目标 file.txt'),('literal-option','--help','--help target.txt')]:
            result=capture(name,['bash',USAGE,'search','/workspace/readable',term,'2','10'],unpriv,'65534:65534')
            assert result['exitCode']==0,result
            data=json.loads(result['stdout'])['data'];assert any(i['name']==expected for i in data['items']),data
            assert len(data['items'])<=2
            receipt['positive'].append({'case':name,'status':'passed','result':data})
        result=capture('no-external-follow',['bash',USAGE,'search','/workspace/readable','protected-marker','2','10'],unpriv,'65534:65534')
        assert result['exitCode']==0 and json.loads(result['stdout'])['data']['items']==[],result
        assert lab.exec(instance,'sha256sum','/workspace/external/protected-marker','/workspace/external/outside-big.bin')==protected
        receipt['negative'].append({'case':'external-link-and-protected-marker','status':'passed'})
        lab.exec(instance,'sh','-ec','mkdir /workspace/readable/blocked; printf unreadable > /workspace/readable/blocked/hidden; chmod 000 /workspace/readable/blocked')
        for action in ['space','search']:
            args=['bash',USAGE,action,'/workspace/readable']+(['目标'] if action=='search' else [])+['3','10']
            result=capture('unreadable-'+action,args,unpriv,'65534:65534')
            response=json.loads(result['stdout'])
            assert result['exitCode']==11 and response['status']=='partial' and response['data']['complete'] is False,result
            assert response['data']['unavailableRanges'],response
            receipt['negative'].append({'case':'unreadable-'+action,'status':'passed','nativeExitCode':11,'result':response['data']})
        print('USAGE '+target+' real scans, Unicode, limits and permissions passed',flush=True)
        for path,expected,eligible in [('/workspace/readable','persistent',True),('/','container-layer',False),
                                      ('/dev/shm','temporary',False),('/proc','unknown',False)]:
            result=capture('storage-'+expected,['bash',USAGE,'storage',path,'1048576'],unpriv,'65534:65534')
            assert result['exitCode']==0,result
            response=json.loads(result['stdout']);assert response['persistence']==expected and response['eligibleForInstall']==eligible,response
            receipt['positive'].append({'case':'storage-'+expected,'status':'passed','result':response})
        result=capture('reject-root-scan',['bash',USAGE,'space','/','3','10'],unpriv,'65534:65534')
        assert result['exitCode']==2,result
        receipt['negative'].append({'case':'whole-root-scan-rejected','status':'passed','nativeExitCode':2})

        print('USAGE '+target+' exact mise development CLI',flush=True)
        selected=product['developerCLI'];version=selected['version']
        runtime_home='/workspace/runtime' if target=='istoreos' else '/root'
        global_config=runtime_home+'/.config/mise/config.toml'
        lab.exec(instance,'sh','-ec','mkdir -p "$1/.config/mise"; printf "# kai-preserve-global-selection\\n" > "$1/.config/mise/config.toml"','scope-fixture',runtime_home)
        global_before=lab.exec(instance,'sha256sum',global_config)
        result=capture('install-dev-cli',['bash',DEV,'install','uv',version]);assert result['exitCode']==0,result
        probe=json.loads(result['stdout']);receipt['developerCLI']=probe
        lab.exec(instance,'sh','-ec','mkdir -p /workspace/foreign-bin; printf \'#!/bin/sh\\necho wrong > /workspace/foreign-executed\\nexit 99\\n\' > /workspace/foreign-bin/uv; chmod 755 /workspace/foreign-bin/uv')
        cli_env=env+['UV_CACHE_DIR=/workspace/uv cache 中文','PATH=/workspace/foreign-bin:/workspace/candidate-bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
        result=capture('dev-help',['bash',USAGE,'cli','exec','uv',version,'--','--help'],cli_env)
        assert result['exitCode']==0 and 'cache' in result['stdout'] and 'uv' in result['stdout'],result
        result=capture('dev-subcommand',['bash',USAGE,'cli','exec','uv',version,'--','cache','dir'],cli_env)
        assert result['exitCode']==0 and result['stdout'].strip()=='/workspace/uv cache 中文',result
        assert not lab.exec(instance,'sh','-c','test ! -e /workspace/foreign-executed || echo executed')
        receipt['positive'].append({'case':'exact-cli-help-and-cache-dir','status':'passed','version':version,'executable':probe['executable']})
        result=capture('missing-cli-probe',['bash',DEV,'probe','uv','99.0.0'])
        assert result['exitCode']==4,result
        receipt['negative'].append({'case':'missing-cli-probe-no-install','status':'passed','nativeExitCode':4})
        if target=='istoreos':
            lab.exec(instance,'sh','-ec','sha256sum -c /usr/share/kai-lab/system-curl.sha256')
            assert lab.exec(instance,'sha256sum','/etc/ssl/openssl.cnf')==original
            receipt['systemCurlAndSSLUnchanged']=True
        marker_after=lab.exec(instance,'sha256sum','/workspace/external/protected-marker','/workspace/external/outside-big.bin')
        source_after=lab.exec(instance,'sha256sum',*source_paths)
        global_after=lab.exec(instance,'sha256sum',global_config)
        files=lab.exec(instance,'find','/workspace/unprivileged-home','-type','f').splitlines()
        locks=[]
        for path in files:
            size=int(lab.exec(instance,'sh','-c','wc -c < "$1"','inspect-file',path))
            locks.append({'path':path,'bytes':size,'coordinationOnly':bool(re.fullmatch(
                r'/workspace/unprivileged-home/\.config/fssearch-cli/storage-locks/[a-f0-9]+-scratch\.lock',path)) and size==0})
        receipt['guardEvidence']={'protectedMarker':{'before':protected,'after':marker_after},
            'sourceFiles':{'before':source_before,'after':source_after},
            'globalSelection':{'before':global_before,'after':global_after},'retainedHomeFiles':locks}
        assert marker_after==protected,'external protected files changed'
        assert source_after==source_before,'source file bytes changed'
        assert global_after==global_before,'global mise selection changed'
        assert all(row['coordinationOnly'] for row in locks),'unexpected persistent HOME files: '+str(locks)
        receipt['sourceFilesUnchanged']=True
        receipt['globalSelectionUnchanged']=True
        receipt['noPersistentSearchIndexOrConfig']=True
        receipt['protectedMarkerUnchanged']=True
        receipt['status']='passed'
    finally:
        try:
            if gateway:
                try:(folder/'gateway.log').write_text(lab.remote('cat',gateway['helper']['work']+'/work/gateway.log'))
                finally:lab.stop_gateway(gateway)
        finally:
            lab.cleanup(instance)
            receipt['cleanup']='passed'
            (lab.state/('MS8-'+target+'.json')).write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
    print(json.dumps(receipt,ensure_ascii=False),flush=True)
