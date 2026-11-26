#!/usr/bin/env python3
"""Observe locked Linux rootfs images with no network, host mounts or writes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import uuid

from native_query import SCRIPT,payload,validate_identity,validate_result


def run(platform,image,output,docker):
    if not re.fullmatch(r'sha256:[0-9a-f]{64}',image):
        raise ValueError('Pin an existing full image ID before native validation')
    name='kai-capabilities-ka2-'+uuid.uuid4().hex
    script=payload(platform,'ka2-native-'+platform).encode()
    argv=docker+['run','--pull','never','--name',name,'--rm','-i','--network','none',
        '--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
        '--pids-limit','64','--memory','128m','--tmpfs','/tmp:rw,nosuid,nodev,noexec',
        '--entrypoint','/bin/sh',image,'-s']
    started=time.monotonic()
    try:
        result=subprocess.run(argv,input=script,capture_output=True,timeout=30)
    finally:
        subprocess.run(docker+['rm','-f',name],capture_output=True,timeout=15)
    receipt={'platform':platform,'image':image,'evidenceType':'native-linux-container',
        'mode':'on-device','elapsedSeconds':round(time.monotonic()-started,3),
        'exitCode':result.returncode,'stdout':result.stdout.decode(errors='replace'),
        'stderr':result.stderr.decode(errors='replace'),'executionArguments':argv,
        'sourceFiles':{name:hashlib.sha256((SCRIPT/name).read_bytes()).hexdigest()
                       for name in ('inspect.sh','lib/receipt.sh','lib/probe.sh')},
        'payloadSHA256':hashlib.sha256(script).hexdigest(),
        'driverSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    try:
        value=validate_result(result.stdout,'ka2-native-'+platform)
        validate_identity(platform,value)
        if result.returncode or 'KA2_PRESERVATION=passed' not in receipt['stderr']:
            raise ValueError('Native preservation or query check failed')
        receipt.update(result=value,status='passed')
    except ValueError as error:
        receipt.update(status='failed',error=str(error))
    path=output/(platform+'.json');path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    path.chmod(0o600)
    print(platform,receipt['status'],flush=True)
    return receipt


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--images-file',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--sudo',action='store_true')
    args=parser.parse_args();images=json.loads(args.images_file.read_text())
    args.output.mkdir(parents=True,exist_ok=False);args.output.chmod(0o700)
    docker=['sudo','-n','docker'] if args.sudo else ['docker']
    results=[run(platform,image,args.output,docker) for platform,image in images.items()]
    return 0 if all(r['status']=='passed' for r in results) else 1


if __name__=='__main__':raise SystemExit(main())
