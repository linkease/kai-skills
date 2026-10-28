#!/usr/bin/env python3
"""Exercise actual Reasonix discovery/routing against temporary installations."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--presets',type=Path,required=True)
parser.add_argument('--reasonix',type=Path,default=root.parent/'reasonix-kai');args=parser.parse_args()
scope=json.loads((root/'tests/multisystem/scope.json').read_text())
aliases={m['oldId']:m['newId'] for m in scope['migration'] if m['decision']=='extract-with-platform-adapter'}
with tempfile.TemporaryDirectory(prefix='kai-consumers-') as directory:
 work=Path(directory);roots=[]
 checkout=work/'checkout';checkout.mkdir()
 shutil.copy2(root/'install.sh',checkout/'install.sh');shutil.copy2(root/'catalog.json',checkout/'catalog.json')
 (checkout/'platforms').symlink_to(args.presets.resolve(),target_is_directory=True)
 for platform in ['ubuntu','debian','istoreos','windows','macos']:
  for mode in ['on-device','remote-control']:
   for consumer in ['codex','opencode']:
    destination=work/platform/mode/consumer
    command=['sh',str(checkout/'install.sh'),'--platform',platform,'--mode',mode,
             '--consumer',consumer,'--target-skills',str(destination)]
    subprocess.run([*command,'--dry-run'],check=True,capture_output=True)
    subprocess.run(command,check=True,capture_output=True)
    roots.append({'Platform':platform,'Mode':mode,'Consumer':consumer,'Path':str(destination)})
 cases=[{'Platform':c['platform'],'Task':c['task'],'Skill':c['skill']} for c in scope['routingCases']]
 data=work/'input.json';data.write_text(json.dumps({'Roots':roots,'Aliases':aliases,'Cases':cases},ensure_ascii=False))
 overlay=work/'overlay.json';overlay.write_text(json.dumps({'Replace':{
  str(args.reasonix/'internal/skill/kai_distribution_external_test.go'):
  str(root/'tests/multisystem/fixtures/distribution_consumer_test.go')}}))
 command=['go','test','-overlay',str(overlay),'./internal/skill','-run','^TestKaiMultisystemDistributionConsumer$','-count=1']
 cache=Path('/var/cache/build-cache/run.sh')
 if cache.is_file():command=[str(cache),'--',*command]
 result=subprocess.run(command,cwd=args.reasonix,env={**os.environ,'KAI_DISTRIBUTION_INPUT':str(data)})
 sys.exit(result.returncode)
