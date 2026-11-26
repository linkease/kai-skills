#!/usr/bin/env python3
"""Run the existing Windows query tests with native PowerShell and an existing Python."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--targets-file',required=True,type=Path);parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();config=json.loads(args.targets_file.read_text())['windows']
    files=[ROOT/'tests/business/test_software_query.py']+sorted((ROOT/'components/system-packs/common/skills/kai-software/scripts').rglob('*.ps1'))
    files += sorted((ROOT/'components/system-packs/windows/skills').rglob('*.ps1'))
    files=[p for p in files if p.is_file()]
    script=r'''$ErrorActionPreference='Stop'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('kai-query-tests-KA3-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary)|Out-Null
try {
'''
    for p in files:
        relative=p.relative_to(ROOT).as_posix()
        script+="$file=Join-Path $temporary '"+relative+"'\n[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))|Out-Null\n[IO.File]::WriteAllBytes($file,[Convert]::FromBase64String('"+base64.b64encode(p.read_bytes()).decode()+"'))\n"
    runner='''import importlib.util,io,json,os,sys,unittest
from pathlib import Path
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('query',root/'tests/business/test_software_query.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
log=io.StringIO();result=unittest.TextTestRunner(stream=log,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(module.NativeWindowsQueryTests))
print(json.dumps({'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),'status':'passed' if result.wasSuccessful() and not result.skipped else 'failed','log':log.getvalue()},ensure_ascii=False))
sys.exit(0 if result.wasSuccessful() and not result.skipped else 1)
'''
    script+=r"""
 $parseCount=0
 foreach($source in @(Get-ChildItem -LiteralPath $temporary -Filter '*.ps1' -Recurse -File)) {
  $tokens=$null;$parseErrors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($source.FullName,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count){throw ('Native PowerShell syntax error in '+$source.Name)}
  $parseCount++
 }
 $nativeDiagnostic=Join-Path $temporary 'components/system-packs/windows/skills/windows-system-diagnostics/scripts/inspect.ps1'
 $diagnostic=((& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $nativeDiagnostic -MaxEvents 1)|Out-String)|ConvertFrom-Json
 if($LASTEXITCODE -ne 0 -or !$diagnostic.readOnly -or !$diagnostic.os.version){throw 'Native system diagnostics did not preserve OS facts'}
"""
    script+="$runner=Join-Path $temporary 'run.py'\n[IO.File]::WriteAllBytes($runner,[Convert]::FromBase64String('"+base64.b64encode(runner.encode()).decode()+"'))\n"
    script+="$env:KAI_DESKTOP_PWSH=Join-Path $PSHOME 'powershell.exe'\n$env:PYTHONUTF8='1'\n$env:PYTHONIOENCODING='utf-8'\n& '"+config['pythonExistingPath'].replace("'","''")+"' $runner $temporary\n$code=$LASTEXITCODE\n} finally {Remove-Item -LiteralPath $temporary -Recurse -Force}\nexit $code\n"
    env={**os.environ,'TARGET_ID':'ka3-windows-queries','TARGET_SSH_HOST':config['host'],'TARGET_SSH_USER':config['user'],'TARGET_SSH_KNOWN_HOSTS':config['knownHosts'],'TARGET_TIMEOUT_SECONDS':'90'}
    if config.get('existingIdentityFiles'):env['TARGET_SSH_IDENTITY']=config['existingIdentityFiles'][0]
    p=subprocess.run(['sh',str(ROOT/'components/transports/ssh/skills/target-ssh-powershell-controller/scripts/target-ssh-powershell.sh'),'inspect'],input=script.encode(),env=env,capture_output=True,timeout=110)
    record={'exitCode':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace'),'sourceFiles':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}}
    try:record['result']=json.loads(record['stdout'])
    except ValueError:record['result']={'status':'failed'}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');args.output.chmod(0o600)
    print(json.dumps({k:v for k,v in record['result'].items() if k!='log'}))
    return 0 if p.returncode==0 and record['result']['status']=='passed' else 1


if __name__=='__main__':raise SystemExit(main())
