#!/usr/bin/env python3
"""Verify the host journal on native Windows, with pinned SSH and owned artifacts."""
import argparse,gzip,hashlib,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--targets-file',type=Path,required=True);p.add_argument('--windows-test-binary',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 cfg=json.loads(a.targets_file.read_text())['windows'];data=a.windows_test_binary.read_bytes();digest=hashlib.sha256(data).hexdigest()
 env={**os.environ,'TARGET_ID':'ka7-native-windows','TARGET_SSH_HOST':cfg['host'],'TARGET_SSH_USER':cfg['user'],'TARGET_SSH_KNOWN_HOSTS':cfg['knownHosts'],'TARGET_TIMEOUT_SECONDS':'90'}
 if cfg.get('existingIdentityFiles'):env['TARGET_SSH_IDENTITY']=cfg['existingIdentityFiles'][0]
 transport=ROOT/'components/transports/ssh/skills/target-ssh-powershell-controller/scripts/target-ssh-powershell.sh'
 def ps(script):return subprocess.run(['sh',str(transport),'inspect'],input=script.encode(),env=env,capture_output=True,timeout=115)
 record={'platform':'windows-native','binarySHA256':digest,'scope':'owned test journal only; no live services','steps':[]};remote=None
 try:
  created=ps("$ErrorActionPreference='Stop';$t=Join-Path ([IO.Path]::GetTempPath()) ('kai-host-boundary-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($t)|Out-Null;@{path=$t}|ConvertTo-Json -Compress")
  if created.returncode:raise RuntimeError('remote temporary directory could not be created')
  remote=json.loads(created.stdout)['path'].replace('\\','/')
  with tempfile.TemporaryDirectory(prefix='ka7-upload-',dir=a.output.parent) as own:
   artifact=Path(own)/'probe.gz';artifact.write_bytes(gzip.compress(data,mtime=0))
   args=['sftp','-q','-b','-','-oBatchMode=yes','-oIdentitiesOnly=yes','-oStrictHostKeyChecking=yes','-oUserKnownHostsFile='+cfg['knownHosts'],'-oConnectTimeout=20']
   if cfg.get('existingIdentityFiles'):args+=['-i',cfg['existingIdentityFiles'][0]]
   if cfg.get('port'):args+=['-P',str(cfg['port'])]
   args += [cfg['user']+'@'+cfg['host']]
   quote=lambda s:'"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
   uploaded=subprocess.run(args,input=('put '+quote(artifact)+' '+quote(('/' if len(remote)>2 and remote[1]==':' else '')+remote+'/probe.gz')+'\n').encode(),capture_output=True,timeout=80)
   record['steps'].append({'step':'sftp','exitCode':uploaded.returncode,'stdout':uploaded.stdout.decode(errors='replace'),'stderr':uploaded.stderr.decode(errors='replace')})
   if uploaded.returncode:raise RuntimeError('pinned artifact upload failed')
  literal=remote.replace("'","''")
  script="$ErrorActionPreference='Stop';$t='"+literal+"';$p=Join-Path $t 'probe.test.exe';$input=[IO.File]::OpenRead((Join-Path $t 'probe.gz'));$gzip=New-Object IO.Compression.GzipStream($input,[IO.Compression.CompressionMode]::Decompress);$file=[IO.File]::Create($p);try{$gzip.CopyTo($file)}finally{$file.Dispose();$gzip.Dispose();$input.Dispose()};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() -cne '"+digest+"'){throw 'test binary digest mismatch'};& $p @('-test.run=^TestOperationContext(IsExplicit|RejectsBroadWindows|RejectsWindowsJunction)','-test.v');if($LASTEXITCODE -ne 0){throw 'native boundary tests failed'}"
  out=ps(script);record.update(exitCode=out.returncode,stdout=out.stdout.decode(errors='replace'),stderr=out.stderr.decode(errors='replace'))
 except Exception as error:record.update(exitCode=1,errorType=type(error).__name__,error=str(error))
 finally:
  if remote:
   clean=ps("$ErrorActionPreference='Stop';Remove-Item -LiteralPath '"+remote.replace("'","''")+"' -Recurse -Force")
   record['cleanupExitCode']=clean.returncode
   if clean.returncode:record['exitCode']=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(record,indent=2)+'\n');a.output.chmod(0o600)
 print('windows native host boundary exit',record['exitCode']);return record['exitCode']
if __name__=='__main__':raise SystemExit(main())
