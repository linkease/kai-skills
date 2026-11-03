#!/usr/bin/env python3
"""Require complete native evidence before emitting a public BM7 summary."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

from model import Distribution, ROOT
from package import tree_digest


def require(value, message):
    if not value:
        raise ValueError(message)


def read_passed(path):
    value = json.loads(path.read_text())
    require(value.get('status') == 'passed', path.parent.name + ' has not passed')
    return value


def collect(base, replacement=None):
    distribution = Distribution()
    catalog = json.loads((ROOT / 'business-catalog.json').read_text())
    packages = {p['id']: p for p in catalog['skills']}
    for name, package in packages.items():
        require(tree_digest(ROOT / 'skills' / name) == package['treeDigest'], 'generated package changed: ' + name)
    expected = {case['id']: case for case in json.loads(
        (ROOT / 'docs/verification/business-bm0-inventory.json').read_text())['nativeCases'] if case['milestone'] == 'BM7'}
    singles = read_passed(base / 'singles/result.json')['targets']
    require({row['target'] for row in singles} == {'ubuntu', 'debian', 'istoreos'} and len(singles) == 3,
        'three native independent targets required')
    core = []
    for target in singles:
        require(target.get('status') == 'passed' and target.get('cleanup') == 'passed', 'independent target or cleanup incomplete')
        require(any(row.get('status') == 'passed' for row in target.get('acceleration', [])),
            'same-instance transfer evidence missing: ' + target['target'])
        if target['target'] == 'istoreos':
            require(target.get('systemCurlAndTlsUnchanged'), 'iStoreOS system guard failed')
        for case in target['cases']:
            require(case['id'] in expected and case['status'] == 'passed' and case['isolatedSkillCount'] == 1,
                'unexpected or unsuccessful independent case')
            require(case['treeDigest'] == packages[case['skill']]['treeDigest'], 'independent package evidence is stale')
            core.append(case)
    require(len(core) == 18 and {case['id'] for case in core} == set(expected), '18 frozen native cases required')
    specialists = read_passed(base / 'specialists/result.json')['targets']
    require(len(specialists) == 1 and specialists[0]['target'] == 'istoreos', 'iStoreOS specialist report required')
    specialist = specialists[0]
    names = {name for name, package in distribution.packages.items() if package['component'] == 'istoreos'}
    require({case['skill'] for case in specialist['cases']} == names and len(specialist['cases']) == len(names),
        'every public iStoreOS specialist must have an explicit native result')
    require(specialist.get('cleanup') == 'passed' and specialist.get('systemCurlAndTlsUnchanged'),
        'specialist cleanup or protected system guard failed')
    for case in specialist['cases']:
        require(case['status'] == 'passed' and case['treeDigest'] == packages[case['skill']]['treeDigest'],
            'specialist evidence failed or changed')
    bundles = []
    for name in ['development', 'software-management']:
        rows = read_passed(base / name / 'result.json')['targets']
        require(len(rows) == 3 and {row['target'] for row in rows} == {'ubuntu', 'debian', 'istoreos'},
            'three native business collection targets required')
        lock = json.loads((ROOT / 'bundles' / (name + '.json')).read_text())
        for row in rows:
            require(row.get('bundle') == lock and row.get('collectionLifecycle') == 'passed'
                and row.get('cleanup') == 'passed' and row.get('freshHome') and row.get('freshClientCache')
                and row.get('freshGatewayCache'), 'business collection has stale or incomplete evidence')
            bundles.append({'platform': row['target'], 'bundle': name, 'status': 'passed', 'members': lock['members']})
    collection_path = base / 'collections/result.json'
    collection_report = json.loads(collection_path.read_text())
    require(collection_report.get('hostCurlLibrariesPolicyAndTlsUnchanged'), 'host system guard failed')
    cycles = collection_report['cycles']
    superseded = []
    if replacement is not None:
        retry = read_passed(replacement)
        require(collection_report['status'] == 'failed' and retry.get('hostCurlLibrariesPolicyAndTlsUnchanged'),
            'replacement requires an explicit failed source report and preserved host')
        failed = [row for row in cycles if row['status'] != 'passed']
        require(len(failed) == 1 and failed[0]['target'] == 'istoreos' and failed[0]['tag'] == 'fresh-repeat',
            'only the diagnosed failed iStoreOS fresh repeat can be replaced')
        require(len(retry['cycles']) == 1, 'replacement must contain exactly one actual journey')
        row = retry['cycles'][0]
        require(row['target'] == 'istoreos' and row['tag'] == 'fresh-repeat' and row['status'] == 'passed',
            'replacement is not the same native case')
        for key in ['client', 'gateway', 'imageId', 'collection']:
            require(row[key] == failed[0][key], 'replacement changed frozen programs, image or package locks')
        cycles = [row if old is failed[0] else old for old in cycles]
        superseded = [{'platform': 'istoreos', 'cycle': 'fresh-repeat', 'status': 'failed',
            'sourceReportSha256': hashlib.sha256(collection_path.read_bytes()).hexdigest(),
            'reason': 'native SDK download returned 502/truncated content and exhausted its 180-second request budget',
            'replacementReportSha256': hashlib.sha256(replacement.read_bytes()).hexdigest()}]
    else:
        require(collection_report.get('status') == 'passed', 'collections has not passed')
    require(len(cycles) == 9 and {(row['target'], row['tag']) for row in cycles} == {
        (target, tag) for target in ['ubuntu', 'debian', 'istoreos']
        for tag in ['collection-local', 'collection-ssh', 'fresh-repeat']}, 'nine system journeys required')
    systems = []
    platform_diagnostics = []
    for row in cycles:
        lock = json.loads((ROOT / 'bundles' / (row['target'] + '-all-' + row['mode'] + '.json')).read_text())
        require(row.get('status') == 'passed' and row.get('collection') == lock
            and row.get('collectionLifecycle') == 'passed' and row.get('cleanup') == 'passed'
            and row.get('configurationAndProtectedMarkerUnchanged'), 'system collection journey incomplete or stale')
        require(row.get('freshHome') and row.get('freshClientCache') and row.get('freshGatewayCache'),
            'fresh system journey evidence missing')
        if row['tag'] == 'collection-local':
            require(set(row.get('nativeNegativeCases', [])) == {
                'missing-client', 'unsupported-platform', 'network-failure', 'content-hash'}, 'native failure cases missing')
            if row['target'] in {'ubuntu', 'debian'}:
                names = {'debian-system-diagnostics'}
                if row['target'] == 'ubuntu':
                    names.add('ubuntu-release-diagnostics')
                entries = row.get('platformDiagnostics', [])
                require({case['skill'] for case in entries} == names, 'native distribution diagnostics missing')
                for case in entries:
                    require(case['status'] == 'passed' and case['treeDigest'] == packages[case['skill']]['treeDigest'],
                        'distribution diagnostic evidence failed or changed')
                platform_diagnostics.append({'platform': row['target'], 'cases': entries,
                    'productionServiceGate': row['platformServiceGate']})
        systems.append({'platform': row['target'], 'mode': row['mode'], 'cycle': row['tag'],
            'status': 'passed', 'members': lock['members']})
    return {'schemaVersion': 1, 'milestone': 'BM7', 'status': 'passed', 'independentCases': core,
        'specialists': specialist['cases'], 'productionGates': specialist['productionGates'],
        'linuxPlatformDiagnostics': platform_diagnostics,
        'supersededAttempts': superseded,
        'businessCollections': bundles, 'systemJourneys': systems,
        'transfers': {row['target']: {'fileSelectedRoute': row['fileRoute'],
            'acceleration': row['acceleration']} for row in singles},
        'programs': {row['target']: {'client': {k: v for k, v in row['client'].items() if k != 'executable'},
            'gateway': row['gateway'], 'imageId': row['imageId']} for row in singles},
        'hostProtectedSystemUnchanged': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--repeat-replacement', type=Path)
    args = parser.parse_args()
    try:
        value = collect(args.evidence, args.repeat_replacement)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix('.pending')
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(args.output)
        print('passed: 18 native independent cases, six business collections and nine system journeys')
        return 0
    except (ValueError, OSError, KeyError) as error:
        print('failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
