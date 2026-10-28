#!/usr/bin/env python3
"""Stage canonical layers, then check or replace the authorized Kai snapshots."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--reasonix',type=Path,default=root.parent/'reasonix-kai')
parser.add_argument('--apply',action='store_true');args=parser.parse_args()
consumer=args.reasonix.resolve();registry_file=consumer/'internal/systempack/builtin/registry.json'
registry=json.loads(registry_file.read_text())
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
remote=subprocess.check_output(['git','remote','get-url','origin'],cwd=root,text=True).strip()
if remote.startswith('git@'):
 host,path=remote[4:].split(':',1);remote='https://'+host+'/'+path
parsed=urllib.parse.urlsplit(remote)
repository=urllib.parse.urlunsplit((parsed.scheme,parsed.hostname or '',parsed.path,'',''))
components=['common','linux','openwrt','istoreos','ubuntu','debian','windows','macos']


def tree_digest(path):
    digest=hashlib.sha256()
    for item in sorted((item for item in path.rglob('*') if item.is_file()),key=lambda p:p.relative_to(path).as_posix().encode()):
        if item.is_symlink():raise ValueError('snapshot symlink is not an immutable file')
        digest.update(item.relative_to(path).as_posix().encode()+b'\0'+item.read_bytes()+b'\0')
    return 'sha256:'+digest.hexdigest()


with tempfile.TemporaryDirectory(prefix='kai-canonical-layers-',dir=os.environ.get('BUILD_CACHE_WORK_DIR')) as temporary:
 stage=Path(temporary);expected={};staged={}
 for component in components:
    source=stage/component
    subprocess.run([sys.executable,str(root/'tools/compose.py'),'layer','--platform',component,'--output',str(source)],check=True,capture_output=True)
    relative='kaiplus-defaults/'+('system-packs/' if component in ['common','linux','openwrt'] else 'profiles/')+component
    metadata=json.loads((root/'components/system-packs'/component/'pack.json').read_text())
    digest=tree_digest(source);record=next(item for item in registry if item['id']==component)
    record.update(version=metadata['version'],layer=metadata['layer'],extends=metadata.get('extends',[]),
        match=metadata.get('match',{}),requires=metadata.get('requires',[]),assetsRoot=relative,
        source={'repository':repository,'commit':commit,'treeDigest':digest})
    expected[component]={'destination':relative,'sourceCommit':commit,'sourceState':'worktree',
        'sourceDigest':json.loads((source/'composition-source.json').read_text())['sourceDigest'],'treeDigest':digest}
    staged[component]=(source,consumer/relative)
 # Generic has no independent files; its inherited source is the actual common layer.
 next(item for item in registry if item['id']=='generic')['source']=next(item['source'] for item in registry if item['id']=='common').copy()
 lock={'schemaVersion':1,'repository':repository,'sourceCommit':commit,'sourceState':'worktree',
       'sourceLayout':'canonical-layers; no third-party Transports','components':expected}
 lock_path=consumer/'kaiplus-defaults/kai-skills-source.lock.json'
 if args.apply:
    # All output has been assembled and hashed before any snapshot is replaced.
    for source,destination in staged.values():
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination.is_symlink():raise ValueError('refusing to replace a snapshot symlink')
        if destination.exists():shutil.rmtree(destination)
        shutil.copytree(source,destination)
    registry_file.write_text(json.dumps(registry,ensure_ascii=False,indent=2)+'\n')
    lock_path.write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n')
 else:
    current=json.loads(registry_file.read_text())
    assert current==registry,'canonical registry/source lock drift'
    assert json.loads(lock_path.read_text())==lock,'canonical provenance lock drift'
    for component,(source,destination) in staged.items():
        assert tree_digest(destination)==expected[component]['treeDigest'],'canonical snapshot drift: '+component
 print('ok: '+('synchronized' if args.apply else 'checked')+' eight canonical layers and their source locks')
