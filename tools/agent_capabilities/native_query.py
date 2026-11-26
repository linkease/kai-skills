#!/usr/bin/env python3
"""Run only the system observation on explicitly configured native test Targets.

Connection material stays in an external private JSON file. This validation
driver stages its own scripts in temporary directories and removes them; it
never installs dependencies, modifies service configuration, or starts engines.
"""
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

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'components/system-packs/common/skills/kai-system-information/scripts'


def payload(platform,target_id,sections='os,tools'):
    if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,95}',target_id):
        raise ValueError('Invalid native test target identity')
    if not all(s in {'os','tools','docker'} for s in sections.split(',')):
        raise ValueError('Invalid native query sections')
    if platform=='windows':
        encoded=base64.b64encode((SCRIPT/'inspect.ps1').read_bytes()).decode()
        receipt=base64.b64encode((SCRIPT/'lib/receipt.ps1').read_bytes()).decode()
        return r'''$ErrorActionPreference='Stop'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('kai-system-inspect-KA2-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary)|Out-Null
$code=255
function Query-Fingerprint {
 $records=New-Object System.Collections.ArrayList
 foreach($file in @((Join-Path $env:WINDIR 'System32\drivers\etc\hosts'),$PROFILE)) {
  if(Test-Path -LiteralPath $file){[void]$records.Add((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)}else{[void]$records.Add('absent')}
 }
 $state=(Get-ItemProperty 'HKCU:\Environment' | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider | ConvertTo-Json -Depth 8 -Compress)
 $sha=[Security.Cryptography.SHA256]::Create()
 try {[void]$records.Add([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($state))))}finally{$sha.Dispose()}
 return ($records -join '|')
}
try {
 $before=Query-Fingerprint
 $file=Join-Path $temporary 'inspect.ps1'
 [IO.Directory]::CreateDirectory((Join-Path $temporary 'lib'))|Out-Null
 [IO.File]::WriteAllBytes((Join-Path $temporary 'lib/receipt.ps1'),[Convert]::FromBase64String('__RECEIPT__'))
 [IO.File]::WriteAllBytes($file,[Convert]::FromBase64String('__SCRIPT__'))
 & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file -TargetId '__TARGET__' -Sections '__SECTIONS__'
 $code=$LASTEXITCODE
 if((Query-Fingerprint) -ne $before){throw 'Query changed a protected configuration fingerprint'}
 [Console]::Error.WriteLine('KA2_PRESERVATION=passed')
} finally {
 Remove-Item -LiteralPath $temporary -Recurse -Force
 if(Test-Path -LiteralPath $temporary){throw 'Own query materials were not cleaned'}
}
exit $code
'''.replace('__SCRIPT__',encoded).replace('__RECEIPT__',receipt).replace('__TARGET__',target_id).replace('__SECTIONS__',sections)
    script='''set -eu
umask 077
temporary=$(mktemp -d "${TMPDIR:-/tmp}/kai-system-inspect-KA2.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
mkdir "$temporary/lib"
query_fingerprint() {
 for file in /etc/hosts /etc/config/dockerd /etc/init.d/dockerd /usr/lib/opkg/status /lib/apk/db/installed; do
  if [ -f "$file" ]; then
   if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file"
   elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$file"
   else return 2; fi
  else printf '%s:absent\n' "$file"; fi
 done
}
before=$(query_fingerprint)
'''
    # Quoted heredocs need no base64/tar on minimal OpenWrt targets.
    for name in ('inspect.sh','lib/receipt.sh','lib/probe.sh'):
        body=(SCRIPT/name).read_text()
        delimiter='KAI_QUERY_'+hashlib.sha256(body.encode()).hexdigest()
        assert delimiter not in body.splitlines()
        script+='cat > "$temporary/'+name+'" <<\''+delimiter+"'\n"+body+'\n'+delimiter+'\n'
    return script+'''code=0
sh "$temporary/inspect.sh" --target-id '__TARGET__' --sections '__SECTIONS__' || code=$?
after=$(query_fingerprint)
[ "$before" = "$after" ] || { echo 'Query changed protected configurations or package databases' >&2; exit 3; }
echo 'KA2_PRESERVATION=passed' >&2
exit "$code"
'''.replace('__TARGET__',target_id).replace('__SECTIONS__',sections)


def run(platform,config,output,sections='os,tools'):
    target_id='ka2-native-'+platform
    kind='target-ssh-powershell-controller' if platform=='windows' else 'target-ssh-controller'
    name='target-ssh-powershell.sh' if platform=='windows' else 'target-ssh.sh'
    transport=ROOT/'components/transports/ssh/skills'/kind/'scripts'/name
    env={**os.environ,'TARGET_ID':target_id,'TARGET_SSH_HOST':config['host'],
         'TARGET_SSH_USER':config['user'],'TARGET_SSH_KNOWN_HOSTS':config['knownHosts'],
         'TARGET_SSH_PORT':str(config.get('port',22)),'TARGET_TIMEOUT_SECONDS':'30'}
    if config.get('existingIdentityFiles'):
        env['TARGET_SSH_IDENTITY']=config['existingIdentityFiles'][0]
    started=time.monotonic()
    script=payload(platform,target_id,sections).encode()
    process=subprocess.run(['sh',str(transport),'inspect'],env=env,input=script,
                           capture_output=True,timeout=50)
    receipt={'platform':platform,'targetId':target_id,'mode':'remote-control',
             'evidenceType':'native-target-execution','elapsedSeconds':round(time.monotonic()-started,3),
             'exitCode':process.returncode,'stdoutSHA256':hashlib.sha256(process.stdout).hexdigest(),
             'stderrSHA256':hashlib.sha256(process.stderr).hexdigest(),
             'stdout':process.stdout.decode('utf-8',errors='replace'),
             'stderr':process.stderr.decode('utf-8',errors='replace'),
             'sourceSHA256':hashlib.sha256((SCRIPT/('inspect.ps1' if platform=='windows' else 'inspect.sh')).read_bytes()).hexdigest()}
    files=['inspect.ps1','lib/receipt.ps1'] if platform=='windows' else ['inspect.sh','lib/receipt.sh','lib/probe.sh']
    receipt['sourceFiles']={name:hashlib.sha256((SCRIPT/name).read_bytes()).hexdigest() for name in files}
    receipt['payloadSHA256']=hashlib.sha256(script).hexdigest()
    receipt['driverSHA256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    try:
        value=validate_result(process.stdout,expected_target=target_id)
        if 'KA2_PRESERVATION=passed' not in receipt['stderr']:
            raise ValueError('Native query preservation proof is missing')
        if 'os' in sections.split(',') and 'tools' in sections.split(','):
            validate_identity(platform,value)
        receipt['result']=value
        receipt['status']='passed' if process.returncode==0 else 'failed'
    except ValueError as error:
        receipt.update(status='failed',contractError=str(error))
    path=output/(platform+'.json')
    path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');path.chmod(0o600)
    # Do not print connection material or raw native errors to shared logs.
    print(platform,receipt['status'],'exit='+str(process.returncode),flush=True)
    return receipt


def validate_identity(platform,result):
    """Assert native facts, not just successful JSON production."""
    facts=result['facts'];system=facts.get('os')
    if not isinstance(system,dict) or not system.get('version'):
        raise ValueError('Native operating-system identity is missing')
    expected={'ubuntu':('linux','ubuntu'),'debian':('linux','debian'),
              'fedora':('linux','fedora'),'macos':('darwin','macos'),
              'windows':('windows','windows'),
              'istoreos-opkg':('linux','istoreos'),'istoreos-apk':('linux','istoreos')}
    if platform in expected and (system.get('family'),system.get('distribution','').lower())!=expected[platform]:
        raise ValueError('Native OS identity does not match this configured test platform')
    for name in ('packageManagers','downloadTools','containerClients'):
        if not isinstance(facts.get(name),list) or not all(isinstance(item,dict) for item in facts[name]):
            raise ValueError('Tool discovery must preserve a flat record array')
    managers={p.get('name') for p in facts['packageManagers']}
    if managers & {'wget','curl','Invoke-WebRequest'}:
        raise ValueError('A downloader was misclassified as a package manager')
    required={'ubuntu':{'apt','apt-get'},'debian':{'apt','apt-get'},'fedora':{'yum','dnf'},
              'istoreos-opkg':{'opkg','is-opkg'},'istoreos-apk':{'apk'}}
    if platform in required and not managers & required[platform]:
        raise ValueError('Expected native package-manager program is not present')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets-file',type=Path,required=True)
    parser.add_argument('--platforms',default='macos,windows')
    parser.add_argument('--sections',default='os,tools')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    config=json.loads(args.targets_file.read_text())
    args.output.mkdir(parents=True,exist_ok=False);args.output.chmod(0o700)
    results=[]
    for platform in args.platforms.split(','):
        if platform not in config or not platform.replace('-','').isalnum():
            raise ValueError('Select an explicitly configured test platform')
        results.append(run(platform,config[platform],args.output,args.sections))
    return 0 if all(r['status']=='passed' for r in results) else 1


if __name__=='__main__':raise SystemExit(main())
