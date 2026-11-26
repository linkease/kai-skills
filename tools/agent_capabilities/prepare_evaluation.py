#!/usr/bin/env python3
"""Materialize only sanitized task documents into a caller-owned new directory.

Rubrics stay in the source manifest, never in the model-visible workspace.
This is scenario preparation, not native platform acceptance or a model judge.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def prepare(destination):
    destination = Path(destination).absolute()
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    source = ROOT / 'tests/agent_capabilities/task-cards.json'
    cards = json.loads(source.read_text())['cards']
    suite = {'schemaVersion': 1, 'cardsSHA256': hashlib.sha256(source.read_bytes()).hexdigest(), 'cards': []}
    for card in cards:
        root = destination / card['id']
        root.mkdir(mode=0o700)
        for path, text in card['documents'].items():
            relative = Path(path.removeprefix('/'))
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('unsafe scenario path')
            p = root / relative
            p.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            p.write_text(text)
            p.chmod(0o600)
        skill = ROOT / 'components/system-packs' / card['skill']
        # Some capabilities moved to the common pack. Resolve by the exact ID,
        # never substitute a different business capability.
        if not skill.exists():
            candidates = list((ROOT / 'components/system-packs').glob('*/skills/' + Path(card['skill']).parts[-2] + '/SKILL.md'))
            if len(candidates) != 1:
                raise ValueError('unresolved canonical resource: ' + card['skill'])
            skill = candidates[0]
        entry = {'id': card['id'], 'prompt': card['prompt'], 'targetId': 'case-target',
                 'root': str(root), 'documents': list(card['documents']), 'skillDocument': str(skill)}
        if card.get('service'):
            entry['serviceScript'] = str(ROOT / 'components/system-packs/istoreos/skills/istoreos-service-manager/scripts/inspect.sh')
        if card['skill'].startswith('istoreos/'):
            entry['agentPromptDir'] = str(ROOT / 'components/system-packs/istoreos/agents')
        suite['cards'].append(entry)
    manifest = destination / 'suite.json'
    manifest.write_text(json.dumps(suite, ensure_ascii=False, indent=2) + '\n')
    manifest.chmod(0o600)
    print(json.dumps({'manifest': str(manifest), 'cardsSHA256': suite['cardsSHA256'], 'cards': len(cards)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', required=True)
    prepare(parser.parse_args().destination)
