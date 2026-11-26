#!/usr/bin/env python3
"""Inventory the existing capability surface without changing installed skills."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/business'))
from model import Distribution

RULES = [
    ('forced-primary-skill', r'一次只加载一个主|先加载.*task-router|明确任务直接使用', 'KA5'),
    ('business-prescription', r'优先回到第|前置：先跑|先按提示完成并等待|## (?:Business workflow|流程)', 'KA5'),
    ('success-without-verification', r'already on requested data_root|ok: migrate attempted|best-effort', 'KA4'),
    ('business-route-gate', r'CheckFinalGate|preferred capabilities.*unused|required capabilities not successfully', 'KA6'),
    ('automatic-route-policy', r'^auto-use:\s*(?:prefer|require)|^routing-group:', 'KA6'),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files(base):
    return sorted(p for p in base.rglob('*') if p.is_file() and
                  not {'__pycache__', '.git', 'node_modules'} & set(p.parts))


def inventory(root=ROOT, reasonix=None):
    root = Path(root).resolve()
    reasonix = Path(reasonix or root.parent / 'reasonix-kai').resolve()
    distribution = Distribution(root)
    records, seen = [], set()
    def record(path, owner, repository, relative, disposition, milestone):
        key = (repository, relative)
        if key in seen:
            return
        seen.add(key)
        findings = []
        if path.suffix in {'.md', '.go', '.sh', '.ps1', '.py', '.json'}:
            for line, text in enumerate(path.read_text(errors='replace').splitlines(), 1):
                for name, pattern, stage in RULES:
                    if re.search(pattern, text):
                        findings.append({'line': line, 'signal': name, 'milestone': stage})
        records.append({'repository': repository, 'path': relative, 'owner': owner,
                        'sha256': sha(path), 'disposition': disposition,
                        'milestone': milestone, 'reviewSignals': findings})
    for component, relative in distribution.composition['componentRoots'].items():
        base = root / relative
        for path in source_files(base):
            rel = path.relative_to(root).as_posix()
            skill = next((name for name, origin in distribution.resources.items()
                          if path.is_relative_to(root / origin)), None)
            if path.name in {'SKILL.md'} or 'agents' in path.parts or 'rules' in path.parts:
                disposition, stage = 'refactor-interface-instructions', 'KA5'
            elif 'tests' in path.parts:
                disposition, stage = 'retain-or-update-behavior-assertions', 'KA9'
            elif path.suffix in {'.sh', '.ps1', '.py'}:
                disposition, stage = 'verify-operation-contract', 'KA3/KA4'
            else:
                disposition, stage = 'retain-platform-facts-and-provenance', 'KA10'
            record(path, skill or component, 'kai-skills', rel, disposition, stage)
    for name in ['components/business.json', 'components/composition.json', 'catalog.json',
                 'business-catalog.json', 'install.sh', 'install.ps1', 'tools/build-kaiplus-snapshot.py',
                 'tools/business/generate.py', 'tools/compose.py', 'tools/sync-kai-system-packs.py']:
        record(root / name, 'distribution', 'kai-skills', name, 'preserve-and-verify-distribution', 'KA10')
    host_roots = ['internal/capability', 'internal/deviceguard', 'internal/systempack']
    host_files = ['internal/control/capability.go', 'internal/control/capability_bridge.go',
                  'internal/tool/shell_execution.go', 'internal/agent/capability.go']
    for relative in host_roots:
        for path in source_files(reasonix / relative):
            if path.suffix == '.go':
                host_files.append(path.relative_to(reasonix).as_posix())
    for path in source_files(reasonix / 'kaiplus-defaults'):
        if path.suffix in {'.md', '.json'}:
            host_files.append(path.relative_to(reasonix).as_posix())
    for relative in sorted(set(host_files)):
        path = reasonix / relative
        if path.is_file():
            stage = 'KA7' if 'deviceguard' in relative or 'shell_execution' in relative else 'KA6'
            if relative.startswith('kaiplus-defaults/'):
                stage = 'KA5'
            record(path, 'KaiPlus-host', 'reasonix-kai', relative,
                   'preserve-safety-remove-business-prescription', stage)
    def commit(path):
        return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    return {'schemaVersion': 1, 'kind': 'agent-capability-inventory',
            'sources': {'kai-skills': commit(root), 'reasonix-kai': commit(reasonix)},
            'packages': sorted(distribution.packages.values(), key=lambda x: x['id']),
            'resources': distribution.resources,
            'entrypoints': records,
            'reviewSignalNote': 'Signals identify review locations, not proven defects.',
            'reviewSignalCount': sum(len(r['reviewSignals']) for r in records)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reasonix', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inventory(reasonix=args.reasonix)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'packages': len(result['packages']), 'entrypoints': len(result['entrypoints']),
                      'reviewSignals': result['reviewSignalCount']}))


if __name__ == '__main__':
    main()
