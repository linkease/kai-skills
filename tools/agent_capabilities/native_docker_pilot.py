#!/usr/bin/env python3
"""Exercise service.apply against an owned native Docker engine; no host service changes.
The procd protocol adapter reads the real owned daemon PID. It is not native procd evidence.
"""
import argparse,hashlib,json,os,shlex,shutil,signal,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
APPLY=ROOT/'components/system-packs/istoreos/skills/istoreos-service-manager/scripts/apply.sh'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--work-dir',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
 if os.geteuid()!=0:raise SystemExit('Run this owned engine test with existing root authorization.')
 docker=shutil.which('docker');dockerd=shutil.which('dockerd')
 if not docker or not dockerd:raise SystemExit('Existing native docker and dockerd are required; nothing installed.')
 own=Path(tempfile.mkdtemp(prefix='kai-ka8-engine-',dir=args.work_dir));own.chmod(0o700)
 runtime=Path(tempfile.mkdtemp(prefix='kai-ka8-runtime-',dir='/tmp'));runtime.chmod(0o700)
 record={'status':'failed','scope':'owned native Docker engine with a procd protocol adapter; no host init/config mutation','sourceSHA256':{str(p.relative_to(ROOT)):digest(p)for p in [APPLY,APPLY.with_name('docker-owner.sh')]}}
 tracked=[];daemon=None
 def info():
  try:p=subprocess.run([docker,'--host',endpoint,'info','--format','{{json .}}'],capture_output=True,text=True,timeout=3)
  except subprocess.TimeoutExpired:return None
  if p.returncode:return None
  value=json.loads(p.stdout)
  return value if all(value.get(key)for key in ['ID','DockerRootDir','ServerVersion'])else None
 def stop(pid):
  try:
   command=Path('/proc')/str(pid)/'cmdline'
   if not command.exists():return
   if str(own).encode()not in command.read_bytes():raise RuntimeError('Refusing to stop a process outside this owned test')
   os.kill(pid,signal.SIGTERM)
   for _ in range(100):
    if not command.exists()or (Path('/proc')/str(pid)/'stat').read_text().split(') ',1)[-1].startswith('Z'):return
    time.sleep(.1)
   os.kill(pid,signal.SIGKILL)
  except ProcessLookupError:pass
 try:
  config=own/'daemon.json';config.write_text('{}')
  log=own/'daemon.log';pidfile=runtime/'daemon.pid';endpoint='unix://'+str(runtime/'docker.sock')
  argv=[dockerd,'--config-file',str(config),'--data-root',str(own/'data'),'--exec-root',str(runtime/'exec'),'--pidfile',str(pidfile),'--host',endpoint,'--storage-driver','vfs','--iptables=false','--ip-masq=false','--bridge=none','--ip-forward=false','--userland-proxy=false']
  with log.open('wb')as logfile:daemon=subprocess.Popen(argv,stdout=logfile,stderr=subprocess.STDOUT,start_new_session=True)
  tracked.append(daemon.pid);initial=None
  deadline=time.monotonic()+30
  while time.monotonic()<deadline:
   if daemon.poll()is not None:raise RuntimeError('Owned engine exited during initialization: '+log.read_text(errors='replace')[-3000:])
   initial=info()
   if initial:break
   time.sleep(.2)
  if not initial:raise RuntimeError('Owned Docker API did not become available')
  record['initialObservation']={key:initial.get(key)for key in ['ID','DockerRootDir','ServerVersion']};record['endpoint']=endpoint
  engine_id=initial['ID'];stop(daemon.pid);daemon.wait(timeout=10)
  system=own/'system';init=system/'etc/init.d/dockerd';cfg=system/'etc/config/dockerd'
  init.parent.mkdir(parents=True);cfg.parent.mkdir(parents=True);cfg.write_text('config globals globals\n')
  starts=own/'starts'
  command=shlex.join(argv)
  init.write_text('#!/bin/bash\nset -eu\ncase "$1" in\nstart)\n printf "start\\n" >> '+shlex.quote(str(starts))+'\n '+command+' >> '+shlex.quote(str(log))+' 2>&1 &\n echo $! > '+shlex.quote(str(own/'started.pid'))+'\n for i in {1..100}; do '+shlex.quote(docker)+' --host '+shlex.quote(endpoint)+' info >/dev/null 2>&1 && exit 0; sleep .1; done\n exit 1;;\nrestart) exit 0;;\n*) exit 2;;\nesac\n');init.chmod(0o700)
  binary=own/'bin';binary.mkdir();ubus=binary/'ubus'
  ubus.write_text('#!/usr/bin/env python3\nimport json,os\nfrom pathlib import Path\npid=int(os.environ.get("TEST_OTHER_PID") or Path('+repr(str(own/'started.pid'))+').read_text())\nprint(json.dumps({"dockerd":{"instances":{"owned":{"running":True,"pid":pid}}}}))\n');ubus.chmod(0o700)
  state=own/'operations';state.mkdir(mode=0o700)
  env={**os.environ,'PATH':str(binary)+':'+os.environ['PATH'],'ISTOREOS_ROOT':str(system),'ZSETUP_TASK_TARGET_ID':'ka8-native-owned-engine','KAI_OPERATION_STATE_DIR':str(state),'KAIPLUS_CONFIRMED':'1'}
  request={'schemaVersion':1,'operation':'service.apply','targetId':'ka8-native-owned-engine','parameters':{'operationId':'native-start','service':'dockerd','action':'start','configName':'dockerd','expectedInitSHA256':digest(init),'expectedConfigSHA256':digest(cfg),'timeoutSeconds':20,'verification':{'kind':'docker-api','endpoint':endpoint,'expectedEngineId':engine_id,'expectedDataRoot':str(own/'data')}}}
  path=own/'request.json';path.write_text(json.dumps(request));before=(digest(init),digest(cfg))
  run=subprocess.run(['bash',str(APPLY),str(path)],env=env,capture_output=True,text=True,timeout=60)
  if (own/'started.pid').exists():tracked.append(int((own/'started.pid').read_text()))
  receipt=json.loads(run.stdout);record['positive']={'exitCode':run.returncode,'receipt':receipt}
  if run.returncode or receipt['operationStatus']!='succeeded':raise RuntimeError('Owned native Docker postcondition did not pass')
  repeated=subprocess.run(['bash',str(APPLY),str(path)],env=env,capture_output=True,text=True,timeout=15)
  if repeated.returncode or json.loads(repeated.stdout)!=receipt or starts.read_text()!='start\n':raise RuntimeError('Same operation ID replayed service start')
  record['idempotentReplay']='passed'
  unrelated=subprocess.Popen(['sleep','30']);tracked.append(unrelated.pid)
  request['parameters'].update(operationId='native-unrelated',action='restart');path.write_text(json.dumps(request))
  wrong=subprocess.run(['bash',str(APPLY),str(path)],env={**env,'TEST_OTHER_PID':str(unrelated.pid)},capture_output=True,text=True,timeout=30)
  negative=json.loads(wrong.stdout);record['unrelatedProcess']={'exitCode':wrong.returncode,'receipt':negative}
  if wrong.returncode==0 or negative['operationStatus']=='succeeded':raise RuntimeError('Unrelated service process falsely validated another engine')
  unrelated.terminate();unrelated.wait();tracked.remove(unrelated.pid)
  if before!=(digest(init),digest(cfg)):raise RuntimeError('Source init or configuration changed')
  record.update(status='passed',initAndConfigPreserved=True,nativeDocker={'serverVersion':initial['ServerVersion'],'storageDriver':initial['Driver']})
 except Exception as error:
  record['error']=str(error)
  if (own/'daemon.log').exists():record['daemonLogTail']=(own/'daemon.log').read_text(errors='replace')[-5000:]
 finally:
  cleanup=[]
  for pid in reversed(tracked):
   try:stop(pid)
   except Exception as error:cleanup.append(type(error).__name__)
  if daemon is not None:
   try:daemon.wait(timeout=10)
   except subprocess.TimeoutExpired:cleanup.append('daemon-wait-timeout')
  if not cleanup:
   mounts=[]
   for line in Path('/proc/self/mountinfo').read_text().splitlines():
    mount=line.split()[4].replace('\\040',' ').replace('\\011','\t').replace('\\134','\\')
    if mount==str(own)or mount.startswith(str(own)+'/'):mounts.append(mount)
   for mount in sorted(set(mounts),key=len,reverse=True):
    for attempt in range(20):
     unmounted=subprocess.run(['umount','--',mount],capture_output=True,timeout=10)
     if unmounted.returncode==0:break
     if b'busy' not in unmounted.stderr.lower():break
     time.sleep(.1)
    if unmounted.returncode:
     cleanup.append('owned-unmount-failed')
     record.setdefault('unmountErrors',[]).append(unmounted.stderr.decode(errors='replace')[:1000])
  if cleanup:record.update(status='failed',cleanupErrors=cleanup,ownedDirectoryRetained=str(own))
  else:
   try:shutil.rmtree(own);shutil.rmtree(runtime);record['cleanup']='passed'
   except OSError as error:record.update(status='failed',cleanupErrors=[str(error)],ownedDirectoryRetained=str(own))
  args.output.write_text(json.dumps(record,indent=2)+'\n');args.output.chmod(0o600)
  if os.environ.get('SUDO_UID'):os.chown(args.output,int(os.environ['SUDO_UID']),int(os.environ['SUDO_GID']))
 print('native Docker pilot',record['status']);return 0 if record['status']=='passed'else 1
if __name__=='__main__':raise SystemExit(main())
