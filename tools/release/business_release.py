#!/usr/bin/env python3
"""Build and verify business distribution artifacts. Targets need no Python.

Building a worktree candidate is deliberately separate from accepting a release.
The latter requires a clean commit and evidence bound to the frozen manifest.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/business'))
from package import members, tree_digest, write_json


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return 'sha256:' + digest.hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def relative(value):
    require(isinstance(value, str) and value and '\\' not in value and ':' not in value and
            not any(c in value for c in '\x00\r\n'), 'unsafe artifact path')
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(p not in ('', '.', '..') for p in value.split('/')),
            'unsafe artifact path: ' + value)
    return value


def regular(root, name):
    path = Path(root) / relative(name)
    require(path.resolve() == path.absolute() and path.is_file(), 'missing or aliased file: ' + name)
    return path


def archive(stage, top, target, format_name):
    """Normalize ordering, times, ownership, modes and gzip header on all hosts."""
    paths = list(members(stage))
    if format_name == 'zip':
        with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
            for path in paths:
                name = top + '/' + path.relative_to(stage).as_posix()
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = ((0o100755 if path.suffix == '.sh' else 0o100644) << 16)
                output.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    else:
        with Path(target).open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w', format=tarfile.PAX_FORMAT) as output:
                for path in paths:
                    data = path.read_bytes()
                    info = tarfile.TarInfo(top + '/' + path.relative_to(stage).as_posix())
                    info.size = len(data)
                    info.mode = 0o755 if path.suffix == '.sh' else 0o644
                    info.mtime = 315532800
                    output.addfile(info, io.BytesIO(data))


def requirements(root, packages):
    inventory = read(root / 'docs/verification/business-bm0-inventory.json')
    result = []
    for case in inventory['acceptanceCriteria']:
        if case['required'] and case['milestone'] != 'BM10':
            result.append({'id': case['id'], 'kind': 'acceptance', 'packages': sorted(packages)})
    for case in inventory['nativeCases']:
        if case['required']:
            result.append({'id': case['id'], 'kind': 'native', 'platform': case['platform'],
                           'packages': [case['skill']]})
    require(len({r['id'] for r in result}) == len(result), 'duplicate release requirement')
    return result


def build(root, output):
    root, output = Path(root).resolve(), Path(output).absolute()
    require(not output.exists(), 'output must be a new directory')
    require(output.resolve() == output and output.parent.is_dir(), 'unsafe output parent')
    catalog = read(root / 'business-catalog.json')
    packages = {p['id']: p for p in catalog['skills']}
    for name, package in packages.items():
        require(relative(package['path']) == 'skills/' + name, 'invalid package path')
        require(tree_digest(root / package['path']) == package['treeDigest'], 'stale package: ' + name)
    commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    require(re.fullmatch('[a-f0-9]{40,64}', commit), 'invalid actual Git commit')
    state = 'worktree' if subprocess.check_output(
        ['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all']) else 'committed'
    collections = []
    for lock_path in sorted((root / 'bundles').glob('*.json')):
        lock = read(lock_path)
        for member in lock['members']:
            require(all(member[k] == packages[member['id']][k] for k in ('id', 'version', 'treeDigest')),
                    'stale collection lock: ' + lock_path.name)
        kind = 'system' if lock['id'].startswith('system:') else 'bundle'
        collections.append(dict(lock, kind=kind, lockPath='bundles/' + lock_path.name))
    units = [{'id': p['id'], 'kind': 'skill', 'version': p['version'], 'members': [p['id']],
              'platform': None, 'mode': None} for p in catalog['skills']]
    for collection in collections:
        units.append({'id': Path(collection['lockPath']).stem, 'kind': collection['kind'],
                      'version': collection['version'], 'members': [m['id'] for m in collection['members']],
                      'platform': collection['platform'], 'mode': collection['mode']})
    inputs = ['business-catalog.json', 'install.sh', 'install.ps1', 'tools/install-business.sh',
              'tools/build-release.sh', 'tools/release/business_release.py',
              'skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1',
              'docs/verification/business-bm0-inventory.json']
    inputs += [c['lockPath'] for c in collections]
    # Payload trees and canonical resource hashes are recorded separately below.
    source_files = {p: sha(regular(root, p)) for p in sorted(inputs)}
    with tempfile.TemporaryDirectory(prefix='.kai-release-', dir=output.parent) as temporary:
        temporary = Path(temporary)
        artifacts = temporary / 'output'; artifacts.mkdir()
        records = []
        for unit in units:
            stage = temporary / 'payload'
            stage.mkdir()
            selected = [packages[n] for n in unit['members']]
            if unit['kind'] == 'skill':
                shutil.copytree(root / selected[0]['path'], stage, dirs_exist_ok=True)
                top = unit['id']
            else:
                top = 'kai-skills-' + unit['id'] + '-v' + unit['version']
                for package in selected:
                    shutil.copytree(root / package['path'], stage / package['path'])
                for name in ('install.sh', 'install.ps1', 'tools/install-business.sh'):
                    target = stage / name; target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(root / name, target)
                # A support resource, not an extra active/discoverable skill.
                shutil.copyfile(root / 'skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1',
                                stage / 'tools/bootstrap-bash.ps1')
                filtered = dict(catalog, skills=selected,
                    bundles={unit['id']: catalog['bundles'][unit['id']]} if unit['kind'] == 'bundle' else {})
                write_json(stage / 'business-catalog.json', filtered)
                collection = next(c for c in collections if Path(c['lockPath']).stem == unit['id'])
                shutil.copyfile(root / collection['lockPath'], _parent(stage / collection['lockPath']))
                write_json(stage / 'SOURCE.json', {'schemaVersion': 2, 'sourceCommit': commit,
                    'sourceState': state, 'id': unit['id'], 'kind': unit['kind'],
                    'members': collection['members'], 'sourceFiles': source_files})
                selection = ('--bundle ' + unit['id'] if unit['kind'] == 'bundle' else
                             '--platform ' + unit['platform'] + ' --all --mode ' + unit['mode'])
                (stage / 'README.md').write_text(
                    '# ' + unit['id'] + '\n\nOffline managed installation (Bash, full jq and SHA256 tools required):\n\n'
                    '```sh\nsh install.sh ' + selection + ' --consumer generic --target-skills /path/to/skills --dry-run\n```\n\n'
                    'Review, then remove --dry-run. Reuse the same selection with --upgrade or --uninstall.\n'
                    'Windows first entry: install.ps1 -Action Plan, with -Bundle ID or -Platform PLATFORM -All -Mode MODE, '
                    'and -TargetSkills DIR. EnsureBash is an explicit preparation operation.\n'
                    'Run tasks on the intended target through its authorized transport.\n', encoding='utf-8')
            digest = tree_digest(stage)
            for format_name in ('tar.gz', 'zip'):
                filename = 'kai-' + unit['kind'] + '-' + unit['id'] + '-v' + unit['version'] + '.' + format_name
                archive(stage, top, artifacts / filename, format_name)
                records.append(dict(unit, root=top, format=format_name, path=filename,
                                    sha256=sha(artifacts / filename), treeDigest=digest))
            shutil.rmtree(stage)
        manifest = {'schemaVersion': 2, 'version': catalog['version'], 'sourceCommit': commit,
                    'sourceState': state, 'sourceFiles': source_files,
                    'packages': catalog['skills'], 'collections': collections, 'artifacts': records,
                    'requirements': requirements(root, packages), 'validationStatus': 'unverified',
                    'limitations': ['Native acceptance must match these package digests.',
                                    'WinGet native installation and npm audit are not declared passed by this build.']}
        write_json(artifacts / 'release-manifest.json', manifest)
        (artifacts / 'SHA256SUMS').write_text(''.join(
            sha(p).split(':')[1] + '  ' + p.name + '\n' for p in sorted(artifacts.iterdir())), encoding='utf-8')
        verify(artifacts)
        artifacts.rename(output)
    return manifest


def _parent(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def unpack(archive_path, format_name, destination, top):
    """Never let an archive create links, aliases or files outside its one root."""
    seen = set()
    def put(name, data):
        relative(name)
        require(name.startswith(top + '/') and name not in seen, 'invalid archive root or duplicate entry')
        seen.add(name)
        _parent(destination / name).write_bytes(data)
    if format_name == 'zip':
        with zipfile.ZipFile(archive_path) as archive_file:
            for item in archive_file.infolist():
                mode = (item.external_attr >> 16) & 0o170000
                require(not item.is_dir() and mode in (0, 0o100000), 'archive contains a link or non-file')
                put(item.filename, archive_file.read(item))
    else:
        with tarfile.open(archive_path, 'r:gz') as archive_file:
            for item in archive_file:
                require(item.isfile(), 'archive contains a link or non-file')
                put(item.name, archive_file.extractfile(item).read())


def verify(directory):
    directory = Path(directory).absolute()
    manifest = read(regular(directory, 'release-manifest.json'))
    require(manifest['schemaVersion'] == 2, 'unsupported release manifest')
    packages = {p['id']: p for p in manifest['packages']}
    require(len(packages) == len(manifest['packages']), 'duplicate package')
    collections = {Path(c['lockPath']).stem: c for c in manifest['collections']}
    require(len(collections) == len(manifest['collections']), 'duplicate collection')
    units = {('skill', p): [p] for p in packages}
    for name, collection in collections.items():
        units[(collection['kind'], name)] = [m['id'] for m in collection['members']]
        for member in collection['members']:
            require(member == {k: packages[member['id']][k] for k in ('id', 'version', 'treeDigest')},
                    'manifest collection mismatch')
    expected = {(kind, name, fmt) for kind, name in units for fmt in ('zip', 'tar.gz')}
    actual, filenames = set(), set()
    for artifact in manifest['artifacts']:
        key = (artifact['kind'], artifact['id'], artifact['format'])
        require(key in expected and key not in actual, 'missing, duplicate or unknown artifact')
        actual.add(key)
        require(artifact['members'] == units[key[:2]], 'artifact members mismatch')
        require('/' not in relative(artifact['path']) and artifact['path'] not in filenames, 'invalid archive filename')
        filenames.add(artifact['path'])
        path = regular(directory, artifact['path'])
        require(sha(path) == artifact['sha256'], 'archive SHA256 mismatch: ' + path.name)
        relative(artifact['root'])
        require('/' not in artifact['root'], 'invalid archive root')
        with tempfile.TemporaryDirectory(prefix='kai-release-verify-') as temporary:
            temporary = Path(temporary)
            unpack(path, artifact['format'], temporary, artifact['root'])
            stage = temporary / artifact['root']
            require(tree_digest(stage) == artifact['treeDigest'], 'archive tree mismatch')
            for name in artifact['members']:
                package_root = stage if artifact['kind'] == 'skill' else stage / 'skills' / name
                require(tree_digest(package_root) == packages[name]['treeDigest'], 'package digest mismatch: ' + name)
                metadata = read(package_root / 'skill-package.json')
                require(metadata == {k: v for k, v in packages[name].items() if k != 'treeDigest'},
                        'package source metadata mismatch')
            if artifact['kind'] != 'skill':
                source = read(stage / 'SOURCE.json')
                collection = collections[artifact['id']]
                require(source['sourceCommit'] == manifest['sourceCommit'] and
                        source['sourceState'] == manifest['sourceState'] and
                        source['sourceFiles'] == manifest['sourceFiles'] and
                        source['members'] == collection['members'], 'archive source mismatch')
                lock = read(regular(stage, collection['lockPath']))
                require(lock == {k: v for k, v in collection.items() if k not in ('kind', 'lockPath')},
                        'archive collection lock mismatch')
                catalog = read(stage / 'business-catalog.json')
                require(catalog['skills'] == [packages[n] for n in artifact['members']], 'offline catalog mismatch')
                for name in ('install.sh', 'install.ps1', 'tools/install-business.sh'):
                    require(sha(stage / name) == manifest['sourceFiles'][name], 'installer source mismatch')
                require(sha(stage / 'tools/bootstrap-bash.ps1') ==
                        manifest['sourceFiles']['skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1'],
                        'native bootstrap source mismatch')
    require(actual == expected, 'release is missing artifacts')
    sums = regular(directory, 'SHA256SUMS').read_text(encoding='utf-8')
    expected_sums = ''.join(sha(directory / name).split(':')[1] + '  ' + name + '\n'
                            for name in sorted(filenames | {'release-manifest.json'}))
    require(sums == expected_sums, 'SHA256SUMS mismatch')
    return manifest


def evidence_template(directory):
    manifest = verify(directory)
    packages = {p['id']: p for p in manifest['packages']}
    return {'schemaVersion': 1, 'manifestDigest': sha(Path(directory) / 'release-manifest.json'),
            'results': [{'id': case['id'], 'status': 'pending',
                         'packageDigests': {n: packages[n]['treeDigest'] for n in case['packages']},
                         'receipts': []} for case in manifest['requirements']]}


def gate(directory, evidence_path):
    manifest = verify(directory)
    require(manifest['sourceState'] == 'committed', 'release requires a clean committed candidate')
    evidence_path = Path(evidence_path).absolute()
    evidence = read(evidence_path)
    require(evidence.get('schemaVersion') == 1 and
            evidence.get('manifestDigest') == sha(Path(directory) / 'release-manifest.json'),
            'evidence does not match frozen manifest')
    results = {r['id']: r for r in evidence['results']}
    require(len(results) == len(evidence['results']), 'duplicate evidence result')
    packages = {p['id']: p for p in manifest['packages']}
    # The required set is frozen from BM0, never supplied by the test reporter.
    required = requirements(ROOT, packages)
    require(manifest['requirements'] == required, 'release requirements changed since BM0')
    for case in required:
        result = results.get(case['id'], {})
        require(result.get('status') == 'passed', 'required evidence not passed: ' + case['id'])
        require(result.get('packageDigests') == {n: packages[n]['treeDigest'] for n in case['packages']},
                'stale package evidence: ' + case['id'])
        require(isinstance(result.get('receipts'), list) and result['receipts'], 'missing execution receipts')
        for receipt in result['receipts']:
            require(sha(regular(evidence_path.parent, receipt['path'])) == receipt['sha256'],
                    'execution receipt digest mismatch')
    return {'schemaVersion': 1, 'status': 'release-ready', 'manifestDigest': evidence['manifestDigest'],
            'sourceCommit': manifest['sourceCommit'], 'requiredPassed': len(required)}


def fetch(manifest_path, base_url, output, allow_http=False):
    """A locally trusted manifest pins both the remote index and every payload."""
    output = Path(output).absolute()
    require(not output.exists() and output.parent.is_dir() and output.resolve() == output,
            'download output must be a new directory without aliases')
    url = urllib.parse.urlsplit(base_url)
    require(url.scheme in (('https', 'http') if allow_http else ('https',)) and url.netloc and
            not url.username and not url.password and not url.query and not url.fragment, 'invalid release base URL')
    manifest = read(manifest_path)
    filenames = ['release-manifest.json', 'SHA256SUMS'] + [a['path'] for a in manifest['artifacts']]
    with tempfile.TemporaryDirectory(prefix='.kai-fetch-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'download'; stage.mkdir()
        for name in filenames:
            require('/' not in relative(name), 'invalid download filename')
            request_url = base_url.rstrip('/') + '/' + urllib.parse.quote(name)
            with urllib.request.urlopen(request_url, timeout=60) as response, (stage / name).open('wb') as target:
                require(urllib.parse.urlsplit(response.url).scheme in (url.scheme, 'https'), 'insecure redirect')
                shutil.copyfileobj(response, target)
        require(sha(stage / 'release-manifest.json') == sha(manifest_path), 'published manifest differs from frozen candidate')
        verify(stage)
        stage.rename(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build_parser = commands.add_parser('build'); build_parser.add_argument('directory', type=Path)
    for command in ('verify', 'evidence-template', 'gate'):
        sub = commands.add_parser(command); sub.add_argument('directory', type=Path)
        if command == 'gate': sub.add_argument('--evidence', type=Path, required=True)
    sub = commands.add_parser('fetch')
    sub.add_argument('--manifest', type=Path, required=True)
    sub.add_argument('--base-url', required=True); sub.add_argument('--output', type=Path, required=True)
    sub.add_argument('--allow-http', action='store_true', help='local fixture testing only')
    args = parser.parse_args()
    try:
        if args.command == 'build':
            subprocess.run(['sh', str(ROOT / 'tools/verify-generated.sh')], check=True,
                           stdout=sys.stderr)
            result = build(ROOT, args.directory)
            print(json.dumps({'status': 'built', 'artifacts': len(result['artifacts']),
                              'sourceState': result['sourceState'], 'validationStatus': 'unverified'}))
        elif args.command == 'verify':
            result = verify(args.directory)
            print(json.dumps({'status': 'verified', 'artifacts': len(result['artifacts'])}))
        elif args.command == 'evidence-template':
            print(json.dumps(evidence_template(args.directory), ensure_ascii=False, indent=2))
        elif args.command == 'gate':
            print(json.dumps(gate(args.directory, args.evidence)))
        else:
            fetch(args.manifest, args.base_url, args.output, args.allow_http)
            print(json.dumps({'status': 'downloaded-and-verified'}))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError,
            zipfile.BadZipFile, tarfile.TarError) as error:
        parser.exit(1, 'failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
