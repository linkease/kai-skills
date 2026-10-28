"""Run explicit milestone cases; missing tests and interrupted cases never pass."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def source_digest():
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT).split(b'\0')
    digest = hashlib.sha256()
    for name in sorted(set(names) - {b''}):
        path = ROOT / os.fsdecode(name)
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink():
            content = b'link\0' + os.fsencode(os.readlink(path))
        elif path.is_file():
            content = path.read_bytes()
        else:
            continue
        digest.update(name + b'\0' + hashlib.sha256(content).digest())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--milestone', choices=[f'MS{i}' for i in range(11)])
    parser.add_argument('--suite', choices=['baseline', 'contract', 'lab', 'required'], default='required')
    parser.add_argument('--target')
    parser.add_argument('--report-dir', type=Path)
    args = parser.parse_args()
    scope = json.loads((ROOT / 'tests/multisystem/scope.json').read_text())
    if args.list:
        if args.json:
            print(json.dumps(scope, ensure_ascii=False))
        else:
            for case in scope['cases']:
                print('\t'.join([case['id'], case['milestone'], case['suite'], case['platform'], case['expected']]))
        return 0
    cases = [c for c in scope['cases'] if
             (not args.milestone or c['milestone'] == args.milestone) and
             (args.suite == 'required' or c['suite'] == args.suite) and
             (not args.target or c['platform'] in [args.target, 'all'])]
    if not cases:
        parser.error('No cases match; an empty suite cannot pass')
    report_dir = (args.report_dir or Path(tempfile.mkdtemp(prefix='kai-multisystem-'))).resolve()
    if report_dir == ROOT or ROOT in report_dir.parents:
        parser.error('Evidence must be stored outside the source checkout')
    report_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(report_dir, 0o700)
    report = {'schemaVersion': 1, 'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'scopeDigest': hashlib.sha256((ROOT / 'tests/multisystem/scope.json').read_bytes()).hexdigest(),
              'cases': [], 'status': 'running'}
    output = report_dir / 'result.json'
    def save():
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    save()
    for case in cases:
        argv = [a.replace('{reasonix}', str(Path(os.environ.get('KAI_REASONIX_SOURCE', ROOT.parent / 'reasonix-kai')).resolve())) for a in case['argv']]
        if case['suite'] == 'baseline' and Path('/var/cache/build-cache/run.sh').is_file():
            argv = ['/var/cache/build-cache/run.sh', '--', *argv]
        started = time.monotonic()
        case_source = source_digest()
        logfile = report_dir / (case['id'] + '.log')
        print(f"RUN {case['id']}", flush=True)
        status, code = 'failed', None
        with logfile.open('w') as log:
            try:
                process = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=case.get('timeoutSeconds', 180))
                    status = 'passed' if code == 0 else 'failed'
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    status = 'failed'
                    log.write('\nCase timed out or was cancelled\n')
            except OSError as error:
                log.write(str(error))
        item = {'id': case['id'], 'milestone': case['milestone'], 'suite': case['suite'],
                'platform': case['platform'], 'status': status, 'exitCode': code,
                'sourceTreeDigest': case_source,
                'elapsedSeconds': round(time.monotonic()-started, 3), 'log': str(logfile),
                'logSha256': hashlib.sha256(logfile.read_bytes()).hexdigest(),
                'expected': case['expected'], 'evidence': case['evidence']}
        report['cases'].append(item)
        save()
        print(f"{status.upper()} {case['id']} ({item['elapsedSeconds']}s)", flush=True)
        if status != 'passed':
            print(logfile.read_text(errors='replace')[-1800:], flush=True)
    report['status'] = 'passed' if all(c['status'] == 'passed' for c in report['cases']) else 'failed'
    report['finishedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save()
    print(json.dumps({'status': report['status'], 'cases': len(cases), 'report': str(output)}), flush=True)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
