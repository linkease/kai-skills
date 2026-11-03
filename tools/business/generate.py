#!/usr/bin/env python3
"""Generate independent packages and exact business/system collection locks."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile

from model import Distribution, ROOT
from package import build_package, write_json


def generate(output):
    output = Path(output).absolute()
    if output == Path('/') or output.resolve() != output:
        raise ValueError('unsafe generation output')
    output.mkdir(parents=True, exist_ok=True)
    distribution = Distribution()
    metadata = {}
    with tempfile.TemporaryDirectory(prefix='.business-generate-', dir=output) as temporary:
        stage = Path(temporary)
        for name in distribution.packages:
            metadata[name] = build_package(distribution, name, stage / 'skills' / name)
        for name in distribution.packages:
            target = output / 'skills' / name
            if target.is_symlink() or target.parent.is_symlink():
                raise ValueError('generation target is aliased')
            if target.exists():
                marker = target / 'skill-package.json'
                source = target / 'resources/source-metadata.json'
                if not marker.is_file() or not source.is_file() or json.loads(marker.read_text()).get('id') != name:
                    raise ValueError('refusing to replace unowned skill directory: ' + name)
        catalog = distribution.catalog()
        catalog['skills'] = [metadata[name] for name in sorted(metadata)]
        write_json(stage / 'business-catalog.json', catalog)
        for name in distribution.bundles:
            selection = distribution.select(bundle=name)
            write_json(stage / 'bundles' / (name + '.json'), lock(distribution, selection, metadata))
        for preset in distribution.legacy['presets']:
            selection = distribution.select(platform=preset['platform'], mode=preset['mode'], all_skills=True)
            write_json(stage / 'bundles' / (preset['platform'] + '-all-' + preset['mode'] + '.json'),
                       lock(distribution, selection, metadata))
        for name in distribution.packages:
            target = output / 'skills' / name
            if target.exists():
                shutil.rmtree(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(stage / 'skills' / name, target)
        bundles = output / 'bundles'
        bundles.mkdir(exist_ok=True)
        for source in (stage / 'bundles').iterdir():
            if (bundles / source.name).is_symlink():
                raise ValueError('bundle target is aliased')
            shutil.copy2(source, bundles / source.name)
        shutil.copy2(stage / 'business-catalog.json', output / 'business-catalog.json')
    print('ok: generated ' + str(len(metadata)) + ' independent skills and 12 collection locks')


def lock(distribution, selection, metadata):
    return {'schemaVersion': 1, 'id': selection['selection'], 'version': distribution.config['releaseVersion'],
            'platform': selection['platform'], 'mode': selection['mode'],
            'members': [{key: metadata[package['id']][key] for key in ['id', 'version', 'treeDigest']}
                        for package in selection['packages']]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        generate(args.output)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, 'failed: ' + str(error) + '\n')
