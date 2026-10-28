#!/usr/bin/env python3
"""Snapshot the two native iStore entry files; one canonical owner remains."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
source=root/'components/system-packs/istoreos/skills/istoreos-mise-runtime/scripts'
destination=root/'components/system-packs/common/skills/kai-dev-environment/resources/istore-runtime'
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
names=['exec.sh','environment.sh']
paths=[str((source/name).relative_to(root)) for name in names]
if not args.check:
 commit=subprocess.check_output(['git','log','-1','--format=%H','--',*paths],cwd=root,text=True).strip()
 clean=subprocess.run(['git','diff','--quiet','HEAD','--',*paths],cwd=root).returncode==0
 lock={'schemaVersion':1,'owner':'system-pack/istoreos','sourceCommit':commit,
       'sourceState':'committed' if clean else 'worktree',
       'sourcePaths':paths,'files':{name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in names}}
if args.check:
 lock=json.loads((destination/'source.lock.json').read_text())
 assert lock['owner']=='system-pack/istoreos' and lock['sourcePaths']==paths and len(lock['sourceCommit'])==40
 assert lock['files']=={name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in names},'native owner hash drift'
encoded=(json.dumps(lock,indent=2)+'\n').encode()
if args.check:
    assert (destination/'source.lock.json').read_bytes()==encoded,'native runtime source lock drift'
    for name in names:assert (destination/name).read_bytes()==(source/name).read_bytes(),'native runtime resource drift'
else:
    destination.mkdir(parents=True,exist_ok=True)
    for name in names:(destination/name).write_bytes((source/name).read_bytes())
    (destination/'source.lock.json').write_bytes(encoded)
print('ok: native runtime owner snapshot '+('checked' if args.check else 'synchronized'))
