#!/usr/bin/env python3
"""Native parser/SCM adapter mocks and real UCI private-candidate tests; no live service changes."""
import argparse,base64,hashlib,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]


def run(platform,cfg):
    if platform=='windows':
        paths=['components/system-packs/windows/skills/windows-service-eventlog/scripts/apply.ps1','components/system-packs/common/skills/kai-system-information/scripts/lib/receipt.ps1']
        script=r'''$ErrorActionPreference='Stop'
$t=Join-Path ([IO.Path]::GetTempPath()) ('kai-write-contract-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($t)|Out-Null
try {
'''
        for path in paths:
            script+="$p=Join-Path $t '"+path+"'\n[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null\n[IO.File]::WriteAllBytes($p,[Convert]::FromBase64String('"+base64.b64encode((ROOT/path).read_bytes()).decode()+"'))\n"
        wrapper=r'''param($Apply,$Scenario)
Add-Type -AssemblyName System.ServiceProcess
$env:ZSETUP_TASK_TARGET_ID='native-fixture';$env:TARGET_CHANGE_APPROVED='YES'
$global:fixture=[pscustomobject]@{Status='Stopped'}
$global:fixture|Add-Member ScriptMethod WaitForStatus {param($state,$timeout) if($env:TEST_CASE -eq 'timeout'){throw 'native timeout'}}
$global:fixture|Add-Member ScriptMethod Refresh {}
function Get-Service {param($Name,$ErrorAction) return $global:fixture}
function Start-Service {param($InputObject,$ErrorAction) if($env:TEST_CASE -eq 'failure'){throw 'native failed'};if($env:TEST_CASE -ne 'fast-exit'){$global:fixture.Status='Running'}}
$env:TEST_CASE=$Scenario
$before=if($Scenario -eq 'stale'){'Running'}else{'Stopped'}
& $Apply -ServiceName fixture -Action Start -ExpectedStatus $before -TargetId native-fixture
'''
        script+="$wrapper=Join-Path $t 'wrapper.ps1'\n[IO.File]::WriteAllBytes($wrapper,[Convert]::FromBase64String('"+base64.b64encode(wrapper.encode()).decode()+"'))\n"
        script+=r'''
$apply=Join-Path $t 'components/system-packs/windows/skills/windows-service-eventlog/scripts/apply.ps1'
foreach($p in @(Get-ChildItem $t -Recurse -Filter '*.ps1')){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($p.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'Native parse failure'}
}
$cases=@()
foreach($scenario in @('success','stale','fast-exit','failure','timeout')){
 $raw=(& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper $apply $scenario)|Out-String
 $r=$raw|ConvertFrom-Json
 if($scenario -eq 'success') {if($r.operationStatus -ne 'succeeded' -or $r.verification.status -ne 'passed'){throw ('Successful SCM postcondition lost: '+$raw)}}
 elseif($r.operationStatus -eq 'succeeded'){throw ('False success: '+$scenario)}
 if($scenario -eq 'stale' -and $r.effects.completed.Count){throw 'Stale precondition wrote'}
 if($scenario -eq 'failure' -and !$r.effects.unknown.Count){throw 'Native failure discarded pending effect'}
 $cases+=@{scenario=$scenario;receipt=$r}
}
@{status='passed';platform='windows';tests=$cases.Count;cases=$cases}|ConvertTo-Json -Depth 24 -Compress
}finally{Remove-Item -LiteralPath $t -Recurse -Force}
'''
        name='target-ssh-powershell-controller';entry='target-ssh-powershell.sh'
    else:
        paths=[]
        script=r'''set -eu
umask 077
t=$(mktemp -d /tmp/kai-uci-contract.XXXXXX)
trap 'rm -rf -- "$t"' EXIT
mkdir "$t/config" "$t/delta"
package=kai_contract_$$
printf "config example main\n option enabled '0'\n option keep 'unchanged'\n" > "$t/config/$package"
uci -q -c "$t/config" -t "$t/delta" set "$package.main.enabled=1"
uci -q -c "$t/config" -t "$t/delta" commit "$package"
[ "$(uci -q -c "$t/config" -t "$t/delta" get "$package.main.enabled")" = 1 ]
[ "$(uci -q -c "$t/config" -t "$t/delta" get "$package.main.keep")" = unchanged ]
[ ! -e "/etc/config/$package" ]
printf '{"status":"passed","tests":1,"scope":"real native UCI private candidate, no system config activation"}\n'
'''
        name='target-ssh-controller';entry='target-ssh.sh'
    env={**os.environ,'TARGET_ID':'ka4-native-'+platform,'TARGET_SSH_HOST':cfg['host'],'TARGET_SSH_USER':cfg['user'],'TARGET_SSH_KNOWN_HOSTS':cfg['knownHosts'],'TARGET_TIMEOUT_SECONDS':'90'}
    if cfg.get('existingIdentityFiles'):env['TARGET_SSH_IDENTITY']=cfg['existingIdentityFiles'][0]
    p=subprocess.run(['sh',str(ROOT/'components/transports/ssh/skills'/name/'scripts'/entry),'inspect'],input=script.encode(),env=env,capture_output=True,timeout=110)
    rec={'platform':platform,'exitCode':p.returncode,'stderr':p.stderr.decode(errors='replace'),'sourceSHA256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in paths}}
    try:rec['result']=json.loads(p.stdout)
    except ValueError:rec['result']={'status':'failed','output':p.stdout.decode(errors='replace')}
    return rec


def main():
    p=argparse.ArgumentParser();p.add_argument('--targets-file',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    cfg=json.loads(a.targets_file.read_text());records=[run(s,cfg[s]) for s in ['windows','istoreos-opkg','istoreos-apk']]
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n');a.output.chmod(0o600)
    for r in records:print(r['platform'],r['exitCode'],r['result'].get('status'))
    return 0 if all(r['exitCode']==0 and r['result'].get('status')=='passed' for r in records) else 1
if __name__=='__main__':raise SystemExit(main())
