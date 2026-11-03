#!/usr/bin/env python3
"""Use real Codex app-server discovery and the checked-out OpenCode parser."""
import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time

from model import ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--opencode-source', type=Path, default=ROOT.parent / 'opencode')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    catalog = json.loads((ROOT / 'business-catalog.json').read_text())
    inputs = []
    for package in catalog['skills']:
        source = ROOT / package['path']
        metadata = json.loads((source / 'resources/source-metadata.json').read_text())
        inputs.append({'id': package['id'], 'path': str(source / 'SKILL.md'),
                       'manual': 'invocation: manual' in metadata['originalFrontmatter']})
    result = subprocess.run(['bun', str(ROOT / 'tools/business/parse-opencode.ts'),
        str(args.opencode_source.resolve() / 'packages/core/src/config/plugin/skill-file.ts')],
        input=json.dumps(inputs), text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError('OpenCode parser failed: ' + result.stderr[-3000:])
    report = {'schemaVersion': 1, 'opencode': json.loads(result.stdout), 'codex': []}
    with tempfile.TemporaryDirectory(prefix='business-consumer-') as temporary:
        work = Path(temporary); home = work / 'home'; home.mkdir()
        codex_home = work / 'codex'; codex_home.mkdir()
        destination = codex_home / 'skills'; destination.mkdir()
        log = work / 'server.log'
        with log.open('w') as stderr:
            process = subprocess.Popen(['codex', 'app-server', '--stdio'], cwd=work,
                env={**os.environ, 'CODEX_HOME': str(codex_home), 'HOME': str(home)},
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1)
            selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
            def request(number, method, params):
                process.stdin.write(json.dumps({'id': number, 'method': method, 'params': params}) + '\n')
                process.stdin.flush()
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if not selector.select(timeout=max(0, deadline-time.monotonic())):
                        break
                    line = process.stdout.readline()
                    if not line:
                        raise RuntimeError('Codex server exited: ' + log.read_text()[-1500:])
                    message = json.loads(line)
                    if message.get('id') == number:
                        if 'error' in message:
                            raise RuntimeError(str(message['error']))
                        return message['result']
                raise RuntimeError('Codex discovery request timed out')
            try:
                request(1, 'initialize', {'clientInfo': {'name': 'kai-business-verification', 'version': '1.1.0'}})
                process.stdin.write(json.dumps({'method': 'initialized'}) + '\n'); process.stdin.flush()
                selections = [
                    ['kai-download-acceleration'],
                    [m['id'] for m in json.loads((ROOT / 'bundles/development.json').read_text())['members']],
                    [m['id'] for m in json.loads((ROOT / 'bundles/windows-all-on-device.json').read_text())['members']],
                ]
                for number, names in enumerate(selections, 2):
                    for name in names:
                        if not (destination / name).exists():
                            shutil.copytree(ROOT / 'skills' / name, destination / name)
                    response = request(number, 'skills/list', {'cwds': [str(work)], 'forceReload': True})
                    entries = response['data']
                    errors = [error for entry in entries for error in entry['errors']]
                    actual = [s for entry in entries for s in entry['skills'] if s['name'] in {p['id'] for p in catalog['skills']}]
                    if errors or {s['name'] for s in actual} != set(names) or len(actual) != len(names):
                        raise RuntimeError('Codex discovery mismatch: ' + json.dumps({'wanted': names, 'actual': actual, 'errors': errors}))
                    report['codex'].append({'selection': ['single', 'development', 'windows-all'][number-2],
                                             'skills': sorted(names), 'status': 'passed'})
            finally:
                selector.close()
                process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.communicate()
    report['status'] = 'passed'
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': 'passed', 'opencodeSkills': len(report['opencode']), 'codexSelections': len(report['codex'])}))


if __name__ == '__main__':
    main()
