#!/usr/bin/env python3
"""Replay existing behavior contracts against one independent package at a time."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

from model import Distribution, ROOT
from package import build_package


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    cases = [
        ('test_bootstrap', 'kai-tool-bootstrap', {'CLI': 'scripts/tool.sh'}),
        ('test_runtime', 'kai-dev-environment', {'CLI': 'scripts/runtime.sh', 'DIAGNOSE': 'scripts/diagnose.sh'}),
        ('test_software', 'kai-software', {'CLI': 'scripts/software.sh'}),
        ('test_dependencies', 'kai-project-dependencies', {'CLI': 'scripts/dependencies.sh'}),
        ('test_acceleration', 'kai-download-acceleration', {'CLI': 'scripts/accelerate.sh', 'EVIDENCE': 'scripts/evidence.sh'}),
        ('test_storage', 'kai-storage-files', {'USAGE': 'scripts/usage.sh', 'DEV': 'resources/runtime/kai-dev-environment/scripts/dev-cli.sh'}),
    ]
    groups = []
    with tempfile.TemporaryDirectory(prefix='business isolated 中文 ') as temporary:
        for module_name, skill, bindings in cases:
            base = Path(temporary) / skill / 'only-selected-skill'
            metadata = build_package(Distribution(), skill, base)
            spec = importlib.util.spec_from_file_location('isolated_' + module_name, ROOT / 'tests/multisystem' / (module_name + '.py'))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            for key, relative in bindings.items():
                setattr(module, key, base / relative)
            if module_name == 'test_bootstrap':
                module.SKILL = base
            log = io.StringIO()
            result = unittest.TextTestRunner(stream=log, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(module))
            groups.append({'skill': skill, 'treeDigest': metadata['treeDigest'],
                           'tests': result.testsRun, 'failures': len(result.failures),
                           'errors': len(result.errors), 'skipped': len(result.skipped),
                           'status': 'passed' if result.wasSuccessful() and not result.skipped else 'failed',
                           'log': log.getvalue()})
            print(skill + ': ' + groups[-1]['status'] + ' (' + str(result.testsRun) + ')', flush=True)
            if not result.wasSuccessful():
                print(log.getvalue(), file=sys.stderr)
    report = {'schemaVersion': 1, 'groups': groups,
              'status': 'passed' if all(g['status'] == 'passed' for g in groups) else 'failed'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
