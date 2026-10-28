#!/usr/bin/env python3
"""Explicit development sync; distributed skills need no sibling checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
dest = root / 'components/system-packs/common/skills/kai-software/resources'
relative = 'scripts/remove-managed.sh'
payload = (args.source / relative).read_bytes()
commit = subprocess.check_output(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True).strip()
lock = {'schemaVersion': 1, 'owner': 'zsetup-scripts', 'path': relative,
        'sourceCommit': commit, 'sourceState': 'local-candidate',
        'sha256': hashlib.sha256(payload).hexdigest(), 'size': len(payload),
        'protocol': 'managed-binary-remove-v1', 'applications': ['linkspace', 'ks-cli', 'kspeeder']}
if args.check:
    assert (dest / 'remove-managed.sh').read_bytes() == payload, 'stale owner resource'
    assert json.loads((dest / 'owner.lock.json').read_text()) == lock, 'stale owner lock'
else:
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'remove-managed.sh').write_bytes(payload)
    (dest / 'owner.lock.json').write_text(json.dumps(lock, indent=2) + '\n')

# jq has its own portable managed layout and removal policy. Keep its owner
# bytes intact; distributed helpers never need this sibling checkout.
jq_dest = root / 'components/system-packs/common/skills/kai-tool-bootstrap/resources'
jq_files = []
for source, name in [('jq/jq-install.sh', 'jq-install.sh'),
                     ('jq/jq-install.ps1', 'jq-install.ps1'),
                     ('lib/bootstrap.ps1', 'bootstrap-windows.ps1')]:
    payload = (args.source / source).read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    jq_files.append({'source': source, 'file': name, 'sha256': digest, 'size': len(payload)})
    if args.check:
        assert (jq_dest / name).read_bytes() == payload, 'stale jq owner resource'
    else:
        jq_dest.mkdir(parents=True, exist_ok=True)
        (jq_dest / name).write_bytes(payload)
jq_lock = {'schemaVersion': 1, 'owner': 'zsetup-scripts', 'sourceCommit': commit,
           'sourceState': 'local-candidate', 'protocol': 'jq-managed-v1',
           'version': '1.8.2', 'files': jq_files, 'publiclyActivated': False}
checksum = ''.join(item['sha256'] + '  ' + item['file'] + '\n' for item in jq_files)
if args.check:
    assert json.loads((jq_dest / 'jq-owner.lock.json').read_text()) == jq_lock
    assert (jq_dest / 'jq-owner.sha256').read_text() == checksum
else:
    (jq_dest / 'jq-owner.lock.json').write_text(json.dumps(jq_lock, indent=2) + '\n')
    (jq_dest / 'jq-owner.sha256').write_text(checksum)
