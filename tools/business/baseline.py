#!/usr/bin/env python3
"""Freeze the business-distribution inventory and observable native case matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PLATFORMS = ['ubuntu', 'debian', 'istoreos', 'macos', 'windows']
TASKS = {
    'kai-tool-bootstrap': ('probe-and-ensure-full-jq', 'jq Unicode and regex result; compatible install reused'),
    'kai-software': ('exact-package-lifecycle', 'exact package query, install, actual command and owned removal'),
    'kai-dev-environment': ('mise-sdk', 'fixed mise SDK provenance, version and actual program output'),
    'kai-project-dependencies': ('locked-project', 'native locked dependency install, unchanged lock and actual import/run'),
    'kai-download-acceleration': ('verified-file-and-git', 'download SHA256 and Git full commit; actual route separately proven'),
    'kai-storage-files': ('bounded-space-and-search', 'known large file and exact search result in an isolated fixture tree'),
}


def inventory():
    composition = json.loads((ROOT / 'components/composition.json').read_text())
    catalog = json.loads((ROOT / 'catalog.json').read_text())
    items = []
    for component, relative in composition['componentRoots'].items():
        base = ROOT / relative / 'skills'
        for path in sorted(base.iterdir()) if base.exists() else []:
            if not (path / 'SKILL.md').is_file():
                continue
            if path.is_symlink():
                raise ValueError('canonical skill symlink requires an explicit contract')
            supported = sorted({p['platform'] for p in catalog['presets']
                                if component in p['generatedFrom'] and
                                (not component.startswith('transport.') or
                                 any(t['component'] == component and path.name in t['skills']
                                     for t in composition['presets'][p['id']]['transports']))})
            refs, programs, members = [], set(), []
            for member in sorted(path.rglob('*')):
                if member.is_symlink():
                    raise ValueError('canonical resources must not be symlinks')
                if not member.is_file() or '__pycache__' in member.parts:
                    continue
                members.append({'path': str(member.relative_to(path)),
                                'sha256': hashlib.sha256(member.read_bytes()).hexdigest()})
                if member.suffix not in {'.sh', '.ps1', '.py', '.md', '.cjs'}:
                    continue
                for lineno, line in enumerate(member.read_text(errors='replace').splitlines(), 1):
                    for target in sorted(set(re.findall(r'(?:\.\./\.\./|\$SKILLS_DIR/)((?:kai|istoreos|target|luci)-[a-z-]+)', line)) - {path.name}):
                        refs.append({'file': str(member.relative_to(path)), 'line': lineno,
                                     'skill': target, 'kind': 'documented-invocation' if member.suffix == '.md' else 'executable-sibling-path'})
                    programs.update(re.findall(r'(?<![\w-])(bash|jq|zsetup|mise|ks-cli|linkspace|python3|node|go|brew|winget|opkg)(?![\w-])', line))
            retired = any(path.name in preset['compatibilityResources']
                          for preset in composition['presets'].values())
            items.append({'id': path.name, 'component': component,
                          'canonicalPath': str(path.relative_to(ROOT)), 'platforms': supported,
                          'disposition': 'compatibility-resource' if retired else 'independent-skill',
                          'aliasTarget': composition['aliases'].get(path.name),
                          'siblingCalls': refs, 'programMentionsToReview': sorted(programs),
                          'files': members})
    cases = [{'id': f'{"BM8" if platform in ["macos", "windows"] else "BM7"}-{platform}-{skill}',
              'milestone': 'BM8' if platform in ['macos', 'windows'] else 'BM7',
              'platform': platform, 'skill': skill, 'required': True,
              'scenario': task[0], 'expected': task[1], 'evidence': 'native-target-execution'}
             for platform in PLATFORMS for skill, task in TASKS.items()]
    plan = (ROOT / 'docs/architecture/business-skill-distribution-milestones.md').read_text()
    criteria = []
    for match in re.finditer(r'^## (BM\d+) [^\n]+\n(.*?)(?=^## |\Z)', plan, re.M | re.S):
        milestone, section = match.groups()
        acceptance = section.split('验收标准：', 1)[1].split('交付证据：', 1)[0]
        for number, expected in re.findall(r'^(\d+)\. (.+)$', acceptance, re.M):
            criteria.append({'id': f'{milestone}-{int(number):02}', 'milestone': milestone,
                             'required': True, 'expected': expected})
    assert len(cases) == 30 and len({c['id'] for c in cases}) == 30
    assert {c['milestone'] for c in criteria} == {f'BM{i}' for i in range(11)}
    assert len(items) == len(list((ROOT / 'components').rglob('SKILL.md')))
    return {'schemaVersion': 1,
            'baselineCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'platformScope': {'linux': 'existing environment-lock.json architecture/digests',
                              'macos': 'arm64-native', 'windows': 'amd64-native'},
            'skills': items, 'nativeCases': cases, 'acceptanceCriteria': criteria}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = inventory()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'skillsAndResources': len(data['skills']),
                      'nativeCases': len(data['nativeCases']),
                      'acceptanceCriteria': len(data['acceptanceCriteria'])}))


if __name__ == '__main__':
    main()
