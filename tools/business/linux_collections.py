#!/usr/bin/env python3
"""Native collection journeys, pinned SSH, lifecycle coexistence and fresh repeats."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

from linux_lab import BusinessLab, NativeTasks, Journey, collection_stage
from model import ROOT
from package import tree_digest


def cycle(lab, target, mode, tag):
    tasks = NativeTasks(lab, target, tag)
    tasks.receipt['mode'] = mode
    try:
        tasks.setup()
        boot = tasks.stage_single('kai-tool-bootstrap')
        tasks.bootstrap(boot)
        lab.exec(tasks.instance, 'sh', '-ec', 'test ! -L /workspace/one; rm -rf /workspace/one')
        archive = tasks.folder / 'offline-collection'
        collection_stage(target, mode, archive)
        tasks.receipt['collection'] = json.loads((archive / 'bundles' / (target + '-all-' + mode + '.json')).read_text())
        tasks.receipt.update(freshHome=True, freshClientCache=True, freshGatewayCache=True)
        for name in ['development', 'software-management']:
            shutil.copy2(ROOT / 'bundles' / (name + '.json'), archive / 'bundles')
        journey = Journey(lab, tasks.instance, mode, archive, tasks.folder, environment=tasks.env)
        tasks.capture_function = journey.capture
        expected = {m['id'] for m in json.loads((archive / 'bundles' / (target + '-all-' + mode + '.json')).read_text())['members']}
        target_expected = expected - {'target-ssh-controller', 'luci-http-controller'} if mode == 'remote-control' else expected
        active = set(lab.exec(tasks.instance, 'sh', '-ec', 'for p in /workspace/skills/*/SKILL.md; do basename "$(dirname "$p")"; done').splitlines())
        assert active == target_expected, (active, target_expected)
        if target in {'ubuntu', 'debian'} and tag == 'collection-local':
            evidence = tasks.capture('native-debian-diagnostics', ['sh', '-ec',
                'cat /etc/os-release; uname -m; uptime; head -n 5 /proc/meminfo; df -Pk /; '
                'dpkg-query -W bash; apt-cache policy bash; '
                'if test -d /run/systemd/system && command -v systemctl >/dev/null; then '
                'systemctl status ssh --no-pager || true; journalctl -u ssh -n 10 --no-pager; '
                'else printf "systemd=not-booted-in-container\\n"; fi'])
            assert 'ID=' + target in evidence['stdout'] and 'Installed:' in evidence['stdout']
            diagnostics = ['debian-system-diagnostics']
            if target == 'ubuntu':
                pocket = tasks.capture('native-ubuntu-release-diagnostics', ['sh', '-ec',
                    'apt-cache policy bash; for path in /etc/netplan /etc/cloud /var/lib/snapd; do '
                    'if test -d "$path"; then ls -ld "$path"; else printf "unavailable=%s\\n" "$path"; fi; done'])
                assert 'ubuntu' in pocket['stdout']
                diagnostics.append('ubuntu-release-diagnostics')
            tasks.receipt['platformDiagnostics'] = [{'skill': name, 'status': 'passed',
                'scope': 'native-read-only-diagnostic-commands', 'treeDigest': tree_digest(ROOT / 'skills' / name)}
                for name in diagnostics]
            tasks.receipt['platformServiceGate'] = 'systemd, snaps, netplan and cloud-init live service operations not verified in the container'
        runtime_home = '/workspace/runtime' if target == 'istoreos' else '/root'
        lab.exec(tasks.instance, 'sh', '-ec',
            'mkdir -p "$1/.config/mise" /workspace/external; printf "# keep global selection\n" > "$1/.config/mise/config.toml"; '
            'printf keep > /workspace/external/protected-marker', 'guards', runtime_home)
        before = lab.exec(tasks.instance, 'sha256sum', runtime_home + '/.config/mise/config.toml', '/workspace/external/protected-marker')
        for name, execute in [('kai-software', tasks.software), ('kai-dev-environment', tasks.runtime),
                              ('kai-project-dependencies', tasks.dependencies), ('kai-download-acceleration', tasks.download),
                              ('kai-storage-files', tasks.storage)]:
            saved = lab.state
            # Audit files belong to this cycle, not an earlier instance with the same target.
            lab.state = tasks.folder
            try:
                execute('/workspace/skills/' + name)
            finally:
                lab.state = saved
            tasks.receipt['cases'].append({'skill': name, 'status': 'passed', 'execution': mode})
        if tag == 'collection-local':
            tasks.negative_cases('/workspace/skills')
        after = lab.exec(tasks.instance, 'sha256sum', runtime_home + '/.config/mise/config.toml', '/workspace/external/protected-marker')
        assert before == after
        if mode == 'on-device':
            def install(*args):
                return tasks.capture('lifecycle-' + str(len(tasks.receipt['captures'])), ['sh', '/workspace/preset/tools/install-business.sh',
                    *args, '--consumer', 'generic', '--target-skills', '/workspace/skills'])
            def count():
                return int(lab.exec(tasks.instance, 'sh', '-ec', 'find /workspace/skills -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l'))
        else:
            destination = tasks.folder / 'controller-skills'
            def install(*args):
                result = subprocess.run(['sh', str(archive / 'tools/install-business.sh'), *args,
                    '--consumer', 'generic', '--target-skills', str(destination)], capture_output=True, text=True, timeout=60)
                assert result.returncode == 0, result.stdout + result.stderr
                return result
            def count():
                return len(list(destination.glob('*/SKILL.md')))
        install('--bundle', 'development')
        install('--bundle', 'software-management')
        install('--skill', 'kai-software')
        install('--platform', target, '--all', '--mode', mode, '--upgrade')
        install('--platform', target, '--all', '--mode', mode, '--uninstall')
        assert count() == 4
        install('--bundle', 'development', '--uninstall')
        assert count() == 2
        install('--bundle', 'software-management', '--uninstall')
        assert count() == 1
        install('--skill', 'kai-software', '--uninstall')
        assert count() == 0
        assert lab.exec(tasks.instance, 'sha256sum', runtime_home + '/.config/mise/config.toml',
            '/workspace/external/protected-marker') == before
        tasks.receipt.update(status='passed', collectionLifecycle='passed', configurationAndProtectedMarkerUnchanged=True)
    except BaseException as error:
        tasks.receipt.update(status='failed', error=str(error))
        raise
    finally:
        tasks.close()
    return tasks.receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--image-locks', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--gateway', type=Path, required=True)
    parser.add_argument('--program-commit', required=True)
    parser.add_argument('--report-dir', type=Path, required=True)
    parser.add_argument('--target', choices=['ubuntu','debian','istoreos'], action='append')
    parser.add_argument('--cycle', choices=['collection-local', 'collection-ssh', 'fresh-repeat'], action='append')
    args = parser.parse_args()
    args.report_dir.mkdir(parents=True, mode=0o700)
    config = json.loads(args.config.read_text())
    config.update(runId='business-' + uuid.uuid4().hex[:10], stateDir=str(args.report_dir.resolve()))
    config['remoteRoot'] += '/' + config['runId']
    for key, path in [('clientCandidate', args.client), ('gatewayCandidate', args.gateway)]:
        config[key] = {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'sourceCommit': args.program_commit}
    (args.report_dir / 'config-private.json').write_text(json.dumps(config, indent=2))
    lab = BusinessLab(config, args.image_locks)
    lab.capacity(minimum=5*1024**3)
    lab.remote_python('from pathlib import Path;import sys;p=Path(sys.argv[1]);assert not p.exists();p.mkdir()', lab.root)
    probe = 'sha256sum /usr/bin/curl /usr/lib/libcurl.so.* /usr/lib/libzstd.so.* /etc/opkg.conf /etc/ssl/openssl.cnf'
    before = lab.remote('sh', '-ec', probe)
    report = {'schemaVersion': 1, 'scope': 'BM7-collections-and-fresh-repeat', 'status': 'running', 'cycles': []}
    output = args.report_dir / 'result.json'
    output.write_text(json.dumps(report))
    try:
        for target in args.target or ['ubuntu','debian','istoreos']:
            for mode, tag in [('on-device','collection-local'), ('remote-control','collection-ssh'), ('on-device','fresh-repeat')]:
                if args.cycle and tag not in args.cycle:
                    continue
                try:
                    value = cycle(lab, target, mode, tag)
                    report['cycles'].append(value)
                finally:
                    if not any(c['target'] == target and c['tag'] == tag for c in report['cycles']):
                        file = args.report_dir / (target + '-' + tag) / 'receipt.json'
                        if file.exists(): report['cycles'].append(json.loads(file.read_text()))
                    output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
        report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=str(error))
    finally:
        after = lab.remote('sh', '-ec', probe)
        report['hostCurlLibrariesPolicyAndTlsUnchanged'] = before == after
        if before != after: report['status'] = 'failed'
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({'status': report['status'], 'cycles': len(report['cycles']), 'report': str(output)}))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
