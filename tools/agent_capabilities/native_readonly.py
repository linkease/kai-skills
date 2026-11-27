#!/usr/bin/env python3
"""Read-only acceptance on existing trusted native targets; stages only own temporary files."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

from contract import validate_result

ROOT = Path(__file__).resolve().parents[2]


def payload(platform, identity):
    if platform == 'windows':
        skill = 'windows-service-eventlog'
        command = "& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $temporary 'scripts/inspect.ps1') -TargetId '" + identity + "' -ServiceName EventLog -MaxEvents 1\n $code=$LASTEXITCODE"
        paths = ['scripts/inspect.ps1', 'resources/runtime/kai-system-information/scripts/lib/receipt.ps1']
        script = r'''$ErrorActionPreference='Stop'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('kai-readonly-KA3-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary)|Out-Null
$protected=Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$before=(Get-FileHash -LiteralPath $protected).Hash
try {
'''
        for path in paths:
            data=(ROOT/'skills'/skill/path).read_bytes()
            script += "$file=Join-Path $temporary '"+path+"'\n[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))|Out-Null\n[IO.File]::WriteAllBytes($file,[Convert]::FromBase64String('"+base64.b64encode(data).decode()+"'))\n"
        script += command + r'''
 if((Get-FileHash -LiteralPath $protected).Hash -ne $before){throw 'Protected file changed'}
 [Console]::Error.WriteLine('KA3_PRESERVATION=passed')
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force}
exit $code
'''
    else:
        skill='macos-launchd-logs' if platform=='macos' else 'istoreos-service-manager'
        paths=['scripts/inspect.sh', 'resources/runtime/kai-system-information/scripts/lib/receipt.sh', 'resources/runtime/kai-system-information/scripts/lib/probe.sh']
        if platform=='macos': paths.append('scripts/common.sh')
        else: paths.append('scripts/redact-json.jq')
        script='''set -eu
umask 077
temporary=$(mktemp -d "${TMPDIR:-/tmp}/kai-readonly-KA3.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
fingerprint() {
 for path in /etc/hosts /etc/config/dockerd /etc/init.d/dockerd /usr/lib/opkg/status /lib/apk/db/installed; do
  if [ -f "$path" ]; then
   if command -v sha256sum >/dev/null 2>&1; then sha256sum "$path"; else shasum -a 256 "$path"; fi
  else printf '%s:absent\\n' "$path"; fi
 done
}
before=$(fingerprint)
'''
        for path in paths:
            text=(ROOT/'skills'/skill/path).read_text()
            delimiter='KAI_READONLY_'+hashlib.sha256(text.encode()).hexdigest()
            script+='mkdir -p "$temporary/'+str(Path(path).parent)+'"\ncat > "$temporary/'+path+'" <<\''+delimiter+"'\n"+text+'\n'+delimiter+'\n'
        script+='export ZSETUP_TASK_TARGET_ID='+identity+'\ncode=0\n'
        command='system com.apple.logd startup' if platform=='macos' else '--target-id '+identity+' --service dockerd --sections init,config,runtime'
        script+='sh "$temporary/scripts/inspect.sh" '+command+' || code=$?\n'
        script+='[ "$(fingerprint)" = "$before" ] || exit 3\necho KA3_PRESERVATION=passed >&2\nexit "$code"\n'
    return script, {p:hashlib.sha256((ROOT/'skills'/skill/p).read_bytes()).hexdigest() for p in paths}


def run(platform, config, output):
    identity='ka3-native-'+platform
    if not re.fullmatch('[a-z0-9._-]+', identity): raise ValueError('invalid target identity')
    text, hashes=payload(platform, identity)
    kind='target-ssh-powershell-controller' if platform=='windows' else 'target-ssh-controller'
    entry='target-ssh-powershell.sh' if platform=='windows' else 'target-ssh.sh'
    transport=ROOT/'components/transports/ssh/skills'/kind/'scripts'/entry
    env={**os.environ,'TARGET_ID':identity,'TARGET_SSH_HOST':config['host'],'TARGET_SSH_USER':config['user'],
         'TARGET_SSH_KNOWN_HOSTS':config['knownHosts'],'TARGET_SSH_PORT':str(config.get('port',22)), 'TARGET_TIMEOUT_SECONDS':'30'}
    if config.get('existingIdentityFiles'): env['TARGET_SSH_IDENTITY']=config['existingIdentityFiles'][0]
    started=time.monotonic()
    p=subprocess.run(['sh',str(transport),'inspect'],input=text.encode(),capture_output=True,env=env,timeout=50)
    record={'platform':platform,'targetId':identity,'sourceFiles':hashes,'elapsedSeconds':round(time.monotonic()-started,3),
            'exitCode':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace'),
            'payloadSHA256':hashlib.sha256(text.encode()).hexdigest(),'status':'failed'}
    try:
        result=validate_result(p.stdout,expected_target=identity)
        if 'KA3_PRESERVATION=passed' not in record['stderr']: raise ValueError('preservation proof missing')
        if platform=='windows':
            if result['facts'].get('service',{}).get('name','').lower()!='eventlog': raise ValueError('native SCM identity missing')
            if not result['facts'].get('startup'): raise ValueError('native startup registration missing')
        elif platform=='macos':
            if not result['facts'].get('observation',{}).get('output'): raise ValueError('launchd startup observation missing')
        else:
            init=result['facts'].get('initScript')
            if not isinstance(init,dict) or not (init.get('content') or init.get('hasMore')):
                raise ValueError('native init source or explicit expansion metadata missing')
            if init.get('hasMore') and not any(e['code']=='FILE_WINDOW_LIMIT' for e in result['errors']):
                raise ValueError('native source limitation was hidden')
        # Preservation is independent of completeness: an explicitly partial
        # native observation must never become a complete-operation pass.
        record.update(preservationStatus='passed',result=result)
        record['status'] = 'passed' if p.returncode == 0 and result['operationStatus'] == 'succeeded' else 'partial'
    except (ValueError,AttributeError) as error: record['validationError']=str(error)
    path=output/(platform+'.json');path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');path.chmod(0o600)
    print(platform,record['status'],'native-exit='+str(p.returncode),flush=True)
    return record['status']=='passed'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--targets-file',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path);parser.add_argument('--platforms',default='macos,windows,istoreos-opkg,istoreos-apk')
    args=parser.parse_args();targets=json.loads(args.targets_file.read_text());args.output.mkdir(mode=0o700,parents=True,exist_ok=False)
    ok=True
    for platform in args.platforms.split(','): ok=run(platform,targets[platform],args.output) and ok
    return 0 if ok else 1


if __name__=='__main__': raise SystemExit(main())
