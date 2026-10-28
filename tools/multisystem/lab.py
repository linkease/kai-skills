"""Isolated Docker acceptance lab. Target configuration and keys stay outside Git."""
import argparse
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import tarfile
import time

OWNER = 'io.linkease.kai-skills.lab'
RUN_LABEL = 'io.linkease.kai-skills.run'
BASES = {'ubuntu': 'ubuntu:24.04', 'debian': 'debian:12', 'istoreos': 'istoreos:24.10.1-rom'}
ROOT = Path(__file__).resolve().parents[2]


class LabCancelled(BaseException):
    pass


def cancel_lab(signum, frame):
    raise LabCancelled(signum)


class Lab:
    def __init__(self, config):
        self.config = config
        self.host = config['sshTarget']
        self.root = config['remoteRoot']
        self.run_id = config['runId']
        if not re.fullmatch(r'[A-Za-z0-9_.@:-]+', self.host) or self.host.startswith('-'):
            raise ValueError('invalid SSH target')
        root = PurePosixPath(self.root)
        if not root.is_absolute() or len(root.parts) < 4 or '..' in root.parts or not re.fullmatch(r'/[A-Za-z0-9_./-]+', self.root):
            raise ValueError('invalid remote root')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,40}', self.run_id):
            raise ValueError('invalid run ID')
        self.state = Path(config['stateDir']).resolve()
        if self.state == ROOT or ROOT in self.state.parents:
            raise ValueError('invalid state directory inside checkout')
        self.labels = {OWNER: 'multisystem', RUN_LABEL: self.run_id}
        self.ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=15', self.host]
        self.gateway_candidate = config.get('gatewayCandidate')
        self.client_candidate = config.get('clientCandidate')
        for candidate in [self.gateway_candidate,self.client_candidate]:
            if candidate is None:
                continue
            path = Path(candidate['path'])
            if (not path.is_absolute() or path.is_symlink() or not path.is_file()
                    or ROOT in path.resolve().parents or path.stat().st_size > 256*1024**2
                    or not re.fullmatch(r'[a-f0-9]{40}', candidate['sourceCommit'])
                    or hashlib.sha256(path.read_bytes()).hexdigest() != candidate['sha256']):
                raise ValueError('invalid gateway candidate: external regular file, source commit and matching SHA256 required')

    def remote(self, *argv, data=None, timeout=600):
        p = subprocess.run([*self.ssh, shlex.join(list(argv))], input=data, capture_output=True, timeout=timeout)
        if p.returncode:
            detail = (p.stdout + p.stderr).decode(errors='replace')[-7000:]
            raise RuntimeError(f'remote {argv[0]} exit={p.returncode}: {detail}')
        return p.stdout.decode(errors='replace').strip()

    def plan(self, target):
        evidence = ['identity', 'package-database', 'digest', 'on-device', 'ssh', 'cleanup']
        if target == 'istoreos':
            evidence.append('system-curl-unchanged')
        result = {'schemaVersion': 1, 'target': target, 'distribution': BASES[target], 'labels': self.labels,
                'minFreeBytes': 1024**3, 'memoryBytes': 1536*1024**2, 'pidsLimit': 256,
                'mountsHostRoot': False, 'mountsHostDockerSocket': False,
                'requiredEvidence': evidence}
        if self.gateway_candidate:
            result['gatewayCandidate'] = {key: self.gateway_candidate[key] for key in ['sha256', 'sourceCommit']}
        if self.client_candidate:
            result['clientCandidate'] = {key: self.client_candidate[key] for key in ['sha256', 'sourceCommit']}
        return result

    def stage_client_candidate(self, instance):
        if not self.client_candidate:
            return None
        candidate=self.client_candidate;payload=Path(candidate['path']).read_bytes()
        if hashlib.sha256(payload).hexdigest()!=candidate['sha256']:
            raise ValueError('client candidate changed after plan')
        executable='/workspace/candidate-bin/ks-cli'
        self.exec(instance,'sh','-ec','umask 077; mkdir -p /workspace/candidate-bin; cat > "$1"; chmod 500 "$1"',
                  'candidate',executable,data=payload)
        assert self.exec(instance,'sha256sum',executable).split()[0]==candidate['sha256']
        version=self.exec(instance,executable,'--version')
        assert 'commit='+candidate['sourceCommit'] in version,'client candidate source identity mismatch'
        return {'executable':executable,'version':version,**{k:candidate[k] for k in ['sha256','sourceCommit']}}

    def label_args(self):
        return [arg for k, v in self.labels.items() for arg in ['--label', f'{k}={v}']]

    def remote_python(self, code, *args, timeout=600):
        return self.remote('python3', '-c', code, *args, timeout=timeout)

    def capacity(self, minimum=2*1024**3):
        available = int(self.remote_python('import os,sys; from pathlib import Path; p=Path(sys.argv[1]);\nwhile not p.exists(): p=p.parent\ns=os.statvfs(p); print(s.f_bavail*s.f_frsize)', str(PurePosixPath(self.root).parent)))
        if available < minimum:
            raise RuntimeError(f'lab disk budget insufficient: need >={minimum} bytes before operation, including 1GiB reserve')
        return available

    def prepare(self, target):
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        record = self.state / f'{target}-image.json'
        if record.exists():
            lock = json.loads(record.read_text())
            details = json.loads(self.remote('docker', 'image', 'inspect', lock['image']))[0]
            if details['Id'] == lock['imageId'] and details['Config']['Labels'].get(RUN_LABEL) == self.run_id:
                return lock
            raise RuntimeError('saved image lock does not match Docker image')
        self.capacity()
        self.remote_python('from pathlib import Path; import sys,os; os.umask(0o077); p=Path(sys.argv[1]); assert not p.is_symlink(); p.mkdir(parents=True,exist_ok=True)', self.root)
        image = f'kai-skills-lab/{target}:{self.run_id.lower()}'
        source = {}
        context = {}
        if target == 'istoreos':
            archive = self.root + '/istoreos-rom-rootfs.tar.gz'
            marker = self.remote('cat', '/rom/usr/lib/os-release')
            if 'istoreos' not in marker.lower() or '24.10.1' not in marker:
                raise RuntimeError('ROM is not the frozen iStoreOS 24.10.1 distribution')
            base_image = f'kai-skills-lab/istoreos-rom:{self.run_id.lower()}'
            try:
                base_info = json.loads(self.remote('docker', 'image', 'inspect', base_image))[0]
                assert base_info['Config']['Labels'].get(RUN_LABEL) == self.run_id
                self.remote('test', '-f', archive)
            except RuntimeError:
                self.remote('tar', '--sort=name', '--numeric-owner', '-C', '/rom',
                            '--exclude=./etc/dropbear', '--exclude=./etc/ssh/ssh_host_*', '--exclude=./root/.ssh',
                            '-czf', archive, '.', timeout=240)
                self.remote('docker', 'import', '--change', f'LABEL {OWNER}=multisystem', '--change', f'LABEL {RUN_LABEL}={self.run_id}', archive, base_image, timeout=240)
            digest = self.remote('sha256sum', archive).split()[0]
            source = {'type': 'immutable-istoreos-rom', 'rootfsSha256': digest,
                      'identity': marker, 'sanitization': ['factory SSH host keys', 'root authorized keys'], 'baseImage': base_image}
            dockerfile = f'''FROM {base_image}
LABEL {OWNER}="multisystem" {RUN_LABEL}="{self.run_id}"
COPY prepare-istoreos.sh /tmp/kai-prepare-istoreos.sh
RUN /bin/sh /tmp/kai-prepare-istoreos.sh && rm /tmp/kai-prepare-istoreos.sh
CMD ["/bin/sh", "-c", "mkdir -p /etc/dropbear /root/.ssh; test -f /etc/dropbear/dropbear_ed25519_host_key || dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key; exec /usr/sbin/dropbear -F -E -s -p 22 -r /etc/dropbear/dropbear_ed25519_host_key"]
'''
            context['prepare-istoreos.sh'] = (Path(__file__).parent / 'prepare-istoreos.sh').read_bytes()
        else:
            self.remote('docker', 'pull', BASES[target], timeout=300)
            base = json.loads(self.remote('docker', 'image', 'inspect', BASES[target]))[0]
            pinned = base['RepoDigests'][0]
            source = {'type': 'registry', 'reference': BASES[target], 'digest': pinned, 'baseImageId': base['Id']}
            dockerfile = f'''FROM {pinned}
LABEL {OWNER}="multisystem" {RUN_LABEL}="{self.run_id}"
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash jq python3 curl ca-certificates openssh-server git xz-utils procps && rm -rf /var/lib/apt/lists/* && rm -f /etc/ssh/ssh_host_*
CMD ["/bin/sh", "-c", "mkdir -p /run/sshd /root/.ssh; ssh-keygen -A; exec /usr/sbin/sshd -D -e -o PermitRootLogin=prohibit-password -o PasswordAuthentication=no"]
'''
        print(f'BUILD {target}: isolated filesystem, host network for package retrieval only', flush=True)
        context['Dockerfile'] = dockerfile.encode()
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as tar:
            for name, content in context.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(content)
                entry.mode = 0o644
                tar.addfile(entry, io.BytesIO(content))
        self.remote('docker', 'build', '--force-rm', '--network', 'host', '--memory', '1536m', '--tag', image, '-', data=archive.getvalue(), timeout=600)
        details = json.loads(self.remote('docker', 'image', 'inspect', image))[0]
        lock = {'schemaVersion': 1, 'target': target, 'image': image, 'imageId': details['Id'],
                'source': source, 'dockerfileSha256': hashlib.sha256(dockerfile.encode()).hexdigest(),
                'contextSha256': {name: hashlib.sha256(content).hexdigest() for name, content in context.items()},
                'buildNetwork': 'host-package-download-only'}
        record.write_text(json.dumps(lock, indent=2))
        return lock

    def ensure_key(self):
        key = self.state / 'client-key'
        if not key.exists():
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        os.chmod(key, 0o600)
        return key

    def inspect_owned(self, kind, name):
        item = json.loads(self.remote('docker', kind, 'inspect', name))[0]
        labels = item.get('Config', {}).get('Labels', {}) if kind == 'container' else item.get('Labels', {})
        if any(labels.get(k) != v for k, v in self.labels.items()):
            raise RuntimeError('ownership mismatch; refusing mutation')
        return item

    def create(self, target, cycle, image):
        name = f'kai-ms-{self.run_id}-{target}-{cycle}'.lower()
        network = f'kai-ms-{self.run_id}-{target}-{cycle}-net'.lower()
        work = self.root + '/' + name
        self.remote_python('from pathlib import Path; import sys,os,json; os.umask(0o077); p=Path(sys.argv[1]); p.mkdir(); (p/"home").mkdir(); (p/"work").mkdir(); (p/".kai-owner.json").write_text(json.dumps({"run":sys.argv[2]}))', work, self.run_id)
        self.remote('docker', 'network', 'create', *self.label_args(), network)
        created = False
        try:
            self.remote('docker', 'run', '-d', '--name', name, *self.label_args(), '--network', network,
                        '--memory', '1536m', '--memory-swap', '1536m', '--cpus', '1.5', '--pids-limit', '256',
                        '--publish', '127.0.0.1::22', '--mount', f'type=bind,src={work}/home,dst=/root',
                        '--mount', f'type=bind,src={work}/work,dst=/workspace', image)
            created = True
            key = self.ensure_key()
            self.remote('docker', 'exec', '-i', name, 'sh', '-c', 'umask 077; mkdir -p /root/.ssh; cat > /root/.ssh/authorized_keys', data=key.with_suffix('.pub').read_bytes())
            self.remote('docker', 'exec', name, 'chmod', '700', '/root', '/root/.ssh')
            if target == 'istoreos':
                # OpenWrt's Dropbear reads this native path, unlike OpenSSH.
                self.remote('docker', 'exec', name, 'sh', '-ec', 'cp /root/.ssh/authorized_keys /etc/dropbear/authorized_keys; chmod 600 /etc/dropbear/authorized_keys')
            port = self.remote('docker', 'port', name, '22/tcp').rsplit(':', 1)[1]
            assert port.isdigit()
            public = None
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                try:
                    if target == 'istoreos':
                        text = self.remote('docker', 'exec', name, 'dropbearkey', '-y', '-f', '/etc/dropbear/dropbear_ed25519_host_key')
                        public = next(line for line in text.splitlines() if line.startswith('ssh-ed25519 '))
                    else:
                        public = self.remote('docker', 'exec', name, 'cat', '/etc/ssh/ssh_host_ed25519_key.pub')
                    break
                except (RuntimeError, StopIteration):
                    time.sleep(0.5)
            if not public:
                raise RuntimeError('container SSH host key not available')
            known_hosts = self.state / (name + '.known_hosts')
            known_hosts.write_text(name + ' ' + ' '.join(public.split()[:2]) + '\n')
            item = self.inspect_owned('container', name)
            assert not item['HostConfig']['Privileged']
            assert all(m['Source'] not in ['/', '/var/run/docker.sock', '/run/docker.sock'] for m in item['Mounts'])
            return {'name': name, 'network': network, 'work': work, 'port': port,
                    'knownHosts': str(known_hosts), 'key': str(key), 'target': target}
        except BaseException:
            if created:
                self.inspect_owned('container', name)
                self.remote('docker', 'rm', '-f', name)
            self.inspect_owned('network', network)
            self.remote('docker', 'network', 'rm', network)
            raise

    def exec(self, instance, *argv, data=None, timeout=120, user=None):
        options=[]
        if user is not None:
            if not re.fullmatch(r'[0-9]{1,10}:[0-9]{1,10}',user):
                raise ValueError('numeric lab uid:gid required')
            options=['--user',user]
        return self.remote('docker', 'exec', '-i', *options, instance['name'], *argv, data=data, timeout=timeout)

    def ssh_exec(self, instance, argv):
        proxy = shlex.join([*self.ssh[:-1], '-W', '127.0.0.1:' + instance['port'], self.host])
        args = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                '-o', 'UserKnownHostsFile=' + instance['knownHosts'], '-o', 'HostKeyAlias=' + instance['name'],
                '-o', 'ProxyCommand=' + proxy, '-o', 'ConnectTimeout=10', '-i', instance['key'], 'root@127.0.0.1', shlex.join(argv)]
        p = subprocess.run(args, capture_output=True, text=True, timeout=45)
        if p.returncode:
            raise RuntimeError('container SSH failed: ' + p.stderr[-2000:])
        return p.stdout.strip()

    def cleanup(self, instance):
        self.inspect_owned('container', instance['name'])
        self.remote('docker', 'rm', '-f', instance['name'])
        self.inspect_owned('network', instance['network'])
        self.remote('docker', 'network', 'rm', instance['network'])
        self.remote_python('from pathlib import Path; import sys,json,shutil; p=Path(sys.argv[1]); assert p.parent==Path(sys.argv[2]); assert not p.is_symlink(); assert json.loads((p/".kai-owner.json").read_text())["run"]==sys.argv[3]; shutil.rmtree(p)', instance['work'], self.root, self.run_id)

    def scenario(self, target, milestone):
        if target != 'istoreos':
            return self.run_scenario(target, milestone)
        probe = ('curl --version && sha256sum /usr/bin/curl /usr/lib/libcurl.so.* /usr/lib/libzstd.so.* /etc/opkg.conf /etc/ssl/openssl.cnf && '
                 'if jq_path=$(command -v jq); then printf "jq=present\\n"; sha256sum "$jq_path"; else printf "jq=absent\\n"; fi')
        before = self.remote('sh', '-ec', probe)
        try:
            return self.run_scenario(target, milestone)
        finally:
            after = self.remote('sh', '-ec', probe)
            self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
            (self.state / f'{milestone}-host-curl.json').write_text(json.dumps({
                'before': before, 'after': after, 'unchanged': before == after}, indent=2))
            if before != after:
                raise RuntimeError('host system curl or package policy changed')

    def run_scenario(self, target, milestone):
        lock = self.prepare(target)
        if milestone == 'MS3':
            return self.bootstrap_scenario(target, lock)
        if milestone == 'MS4':
            return self.software_scenario(target, lock)
        if milestone == 'MS5':
            return self.runtime_scenario(target, lock)
        if milestone == 'MS6':
            return self.dependency_scenario(target, lock)
        if milestone == 'MS7':
            from acceleration_lab import AccelerationAudit
            return self.dependency_scenario(target, lock, audit=AccelerationAudit(self, target))
        if milestone == 'MS8':
            from usage_lab import run_usage
            return run_usage(self,target,lock)
        if milestone == 'MS10':
            from distribution_lab import run_distribution
            return run_distribution(self,target,lock)
        if milestone != 'MS1':
            raise RuntimeError('milestone scenario not implemented: ' + milestone)
        daemon_root = self.remote('docker', 'info', '--format', '{{.DockerRootDir}}')
        results = []
        for cycle in [1, 2]:
            print(f'CYCLE {target} {cycle}', flush=True)
            instance = self.create(target, cycle, lock['image'])
            try:
                identity = self.exec(instance, 'cat', '/etc/os-release')
                assert target in identity.lower(), 'wrong distribution'
                if target == 'istoreos':
                    assert self.exec(instance, 'opkg', 'status', 'libc')
                    self.exec(instance, 'sh', '-c', 'test -x /usr/bin/mise && test -x /usr/sbin/mise-exec && test -f /lib/functions/mise.sh')
                    self.exec(instance, 'sh', '-ec', 'sha256sum -c /usr/share/kai-lab/system-curl.sha256; curl --version > /tmp/curl.version; cmp /usr/share/kai-lab/system-curl.version /tmp/curl.version')
                    system_curl = {'unchanged': True,
                                   'version': self.exec(instance, 'cat', '/usr/share/kai-lab/system-curl.version'),
                                   'baselineSha256': self.exec(instance, 'cat', '/usr/share/kai-lab/system-curl.sha256')}
                else:
                    assert self.exec(instance, 'dpkg-query', '-W', 'libc6')
                marker = self.exec(instance, 'sh', '-c', 'printf target-only > /workspace/kai-ms1-marker; cat /workspace/kai-ms1-marker')
                assert marker == 'target-only'
                assert self.ssh_exec(instance, ['cat', '/workspace/kai-ms1-marker']) == 'target-only'
                assert self.remote('test', '!', '-e', '/workspace/kai-ms1-marker') == ''
                results.append({'cycle': cycle, 'identity': identity, 'onDevice': 'passed', 'ssh': 'passed'})
                if target == 'istoreos':
                    results[-1]['systemCurl'] = system_curl
            finally:
                self.cleanup(instance)
            assert self.remote('docker', 'ps', '-aq', '--filter', 'name=^/' + instance['name'] + '$') == ''
        fault_results = []
        for fault in ['injected-failure', 'timeout', 'cancel-signal']:
            print(f'FAILURE-CLEANUP {target} {fault}', flush=True)
            instance = self.create(target, fault, lock['image'])
            caught = False
            try:
                try:
                    if fault == 'injected-failure':
                        raise RuntimeError('intentional-lab-failure')
                    if fault == 'cancel-signal':
                        signal.raise_signal(signal.SIGTERM)
                    self.exec(instance, 'sh', '-c', 'exec sleep 60', timeout=1)
                finally:
                    self.cleanup(instance)
            except subprocess.TimeoutExpired:
                caught = fault == 'timeout'
            except LabCancelled:
                caught = fault == 'cancel-signal'
            except RuntimeError as error:
                if str(error) != 'intentional-lab-failure':
                    raise
                caught = fault == 'injected-failure'
            assert caught, 'failure did not exercise cleanup'
            assert self.remote('docker', 'ps', '-aq', '--filter', 'name=^/' + instance['name'] + '$') == ''
            fault_results.append({'fault': fault, 'cleanup': 'passed'})
        assert self.remote('docker', 'info', '--format', '{{.DockerRootDir}}') == daemon_root
        receipt = {'schemaVersion': 1, 'milestone': milestone, 'target': target, 'status': 'passed',
                   'imageLock': lock, 'cycles': results, 'failureCleanup': fault_results, 'cleanup': 'passed', 'hostDockerRootUnchanged': True}
        (self.state / f'{milestone}-{target}.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt), flush=True)

    def stage_skills(self, instance):
        archive = io.BytesIO()
        base = ROOT / 'components/system-packs'
        with tarfile.open(fileobj=archive, mode='w') as tar:
            for pack in ['common', 'linux', 'openwrt', 'istoreos']:
                tar.add(base / pack, arcname=pack,
                        filter=lambda item: None if '__pycache__' in item.name or item.name.endswith('.pyc') else item)
        self.exec(instance, 'mkdir', '-p', '/workspace/canonical')
        self.exec(instance, 'tar', '-xf', '-', '-C', '/workspace/canonical', data=archive.getvalue())

    def bootstrap_scenario(self, target, lock):
        instance = self.create(target, 'ms3-bootstrap', lock['image'])
        tools = {}
        try:
            self.stage_skills(instance)
            helper = '/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
            inventory = 'sha256sum /etc/init.d/* 2>/dev/null || true'
            services_before = self.exec(instance, 'sh', '-c', inventory)
            env = ['env', 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work', 'ZSETUP_ROOT=/workspace/zsetup', 'ZSETUP_CACHE_DIR=/workspace/zsetup-cache']
            requested = ['bash', 'mise', 'ks-cli'] if target == 'istoreos' else ['bash', 'zsetup', 'ks-cli', 'mise']
            for tool in requested:
                print(f'BOOTSTRAP {target} {tool}', flush=True)
                result = json.loads(self.exec(instance, *env, 'bash', helper, 'ensure', tool, timeout=480).splitlines()[-1])
                assert result['status'] in ['installed', 'reused'], result
                repeat = json.loads(self.exec(instance, *env, 'bash', helper, 'ensure', tool).splitlines()[-1])
                assert repeat['status'] == 'reused', repeat
                tools[tool] = {'first': result, 'repeat': repeat}
            assert self.exec(instance, 'sh', '-c', inventory) == services_before, 'bootstrap changed service files'
            assert not self.exec(instance, 'sh', '-c', 'pidof iStoreEnhance kspeeder 2>/dev/null || true'), 'bootstrap started a gateway'
            native = None
            if target == 'istoreos':
                self.exec(instance, 'sh', '-ec', 'mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; test -x /usr/sbin/mise-exec; test -f /lib/functions/mise.sh; sha256sum -c /usr/share/kai-lab/system-curl.sha256')
                native = self.exec(instance, 'sh', '-ec', 'opkg status mise; opkg status ks-cli; printf "runtime_dir="; uci get mise.main.runtime_dir')
        finally:
            self.cleanup(instance)
        receipt = {'schemaVersion': 1, 'milestone': 'MS3', 'target': target, 'status': 'passed',
                   'imageLock': lock, 'tools': tools, 'nativeIntegration': native,
                   'serviceFilesUnchanged': True, 'gatewayNotStarted': True, 'cleanup': 'passed'}
        (self.state / f'MS3-{target}.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt), flush=True)

    def start_gateway(self, instance):
        """An Ubuntu process shares only the test target's network namespace."""
        helper = self.create('ubuntu', instance['target'] + '-gateway-owner', self.prepare('ubuntu')['image'])
        name = instance['name'] + '-gateway'
        running = False
        try:
            print(f'GATEWAY {instance["target"]} isolated Linux binary', flush=True)
            executable = '/root/.local/bin/kspeeder'
            if self.gateway_candidate:
                payload = Path(self.gateway_candidate['path']).read_bytes()
                if hashlib.sha256(payload).hexdigest() != self.gateway_candidate['sha256']:
                    raise ValueError('gateway candidate changed after plan')
                executable = '/workspace/kai-candidate-kspeeder'
                self.exec(helper, 'sh', '-ec', 'umask 077; cat > "$1"; chmod 500 "$1"', 'candidate', executable, data=payload)
                assert self.exec(helper, 'sha256sum', executable).split()[0] == self.gateway_candidate['sha256']
            else:
                self.stage_skills(helper)
                env = ['env', 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
                       'ZSETUP_ROOT=/workspace/zsetup', 'ZSETUP_CACHE_DIR=/workspace/zsetup-cache']
                bootstrap = '/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
                self.exec(helper, *env, 'bash', bootstrap, 'ensure', 'zsetup', timeout=180)
                self.exec(helper, *env, '/root/.local/bin/zsetup', 'install', 'kspeeder', '--foreground', timeout=300)
            version = self.exec(helper, executable, 'version')
            self.remote('docker', 'stop', '--time', '10', helper['name'])
            self.remote('docker', 'run', '-d', '--name', name, *self.label_args(),
                        '--network', 'container:' + instance['name'],
                        '--memory', '768m', '--memory-swap', '768m', '--cpus', '1', '--pids-limit', '128',
                        '--mount', f'type=bind,src={helper["work"]}/home,dst=/root',
                        '--mount', f'type=bind,src={helper["work"]}/work,dst=/workspace',
                        self.prepare('ubuntu')['image'], 'sh', '-ec',
                        'exec ' + executable + ' -cachePath /workspace/gateway-cache '
                        '-localAddr :5443 -adminAddr 127.0.0.1:5003 > /workspace/gateway.log 2>&1')
            running = True
            gateway = {'helper': helper, 'name': name, 'version': version}
            if self.gateway_candidate:
                gateway['candidate'] = {key: self.gateway_candidate[key] for key in ['sha256', 'sourceCommit']}
            # Initial certificate retrieval precedes the admin server. Keep a
            # bounded wall-clock budget, independent of curl/SSH request costs.
            deadline = time.monotonic() + 180
            last_error = ''
            while time.monotonic() < deadline:
                try:
                    capabilities = json.loads(self.exec(instance, 'curl', '-fsS', '--max-time', '2', 'http://127.0.0.1:5003/api/v1/capabilities'))
                    gateway['capabilities'] = capabilities
                    if self.gateway_candidate:
                        assert capabilities['service']['commit'] == self.gateway_candidate['sourceCommit'], 'candidate source identity mismatch'
                    return gateway
                except (RuntimeError, ValueError) as error:
                    last_error = str(error)[-2000:]
                    time.sleep(1)
            raise RuntimeError('isolated gateway did not become healthy within 180s; ' + last_error)
        except BaseException:
            if running:
                try:
                    item = self.inspect_owned('container', name)
                    diagnostic = {'schemaVersion': 1, 'status': 'failed',
                                  'target': instance['target'], 'state': item['State']}
                    log = self.remote('tail', '-c', '65536', helper['work'] + '/work/gateway.log')
                    # Failure files belong to this exact invocation. Normal
                    # scenario evidence may still hold an earlier run's log.
                    prefix = instance['name'] + '-gateway-start-failure'
                    (self.state / (prefix + '.log')).write_text(log)
                    (self.state / (prefix + '.json')).write_text(json.dumps(diagnostic, indent=2))
                finally:
                    self.inspect_owned('container', name)
                    self.remote('docker', 'rm', '-f', name)
            self.cleanup(helper)
            raise

    def stop_gateway(self, gateway):
        try:
            self.inspect_owned('container', gateway['name'])
            self.remote('docker', 'rm', '-f', gateway['name'])
        finally:
            self.cleanup(gateway['helper'])

    def runtime_tls_check(self, instance, env, helper, version):
        with tempfile.TemporaryDirectory(prefix='tls-fixture-', dir=self.state) as folder:
            cert = Path(folder) / 'certificate.pem'
            key = Path(folder) / 'key.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                            '-nodes', '-days', '1', '-keyout', str(key), '-out', str(cert),
                            '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subject_hash = subprocess.check_output(['openssl', 'x509', '-in', str(cert), '-noout', '-hash'], text=True).strip()
            archive = io.BytesIO()
            with tarfile.open(fileobj=archive, mode='w') as tar:
                for item in [cert, key]:
                    content = item.read_bytes()
                    entry = tarfile.TarInfo(item.name); entry.size = len(content); entry.mode = 0o600
                    tar.addfile(entry, io.BytesIO(content))
                content = cert.read_bytes()
                entry = tarfile.TarInfo('ca/' + subject_hash + '.0'); entry.size = len(content); entry.mode = 0o600
                tar.addfile(entry, io.BytesIO(content))
            self.exec(instance, 'mkdir', '-p', '/workspace/tls-fixture/ca')
            self.exec(instance, 'tar', '-xf', '-', '-C', '/workspace/tls-fixture', data=archive.getvalue())
            script = '/workspace/canonical/common/skills/kai-dev-environment/scripts/check-tls.py'
            result = json.loads(self.exec(instance, *env, 'bash', helper, 'exec', 'python', version, '--',
                                          'python', script, '/workspace/tls-fixture/certificate.pem',
                                          '/workspace/tls-fixture/key.pem', '--capath', '/workspace/tls-fixture/ca',
                                          '--system-trust-host', 'pypi.org', timeout=60))
            assert result['untrustedRejected'] and result['hostnameMismatchRejected']
            assert result['trustedHandshake'] == 'passed'
            assert result['capath']['trustedHandshake'] == 'passed'
            assert result['systemTrust']['status'] == 'passed'
            return result

    def runtime_scenario(self, target, lock):
        self.capacity(minimum=5*1024**3)
        instance = self.create(target, 'ms5-runtime', lock['image'])
        outcomes = {}
        gateway = None
        original_ssl_config = None
        versions = json.loads((ROOT / 'tests/multisystem/sdk-lock.json').read_text())
        try:
            self.stage_skills(instance)
            bootstrap = '/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
            helper = '/workspace/canonical/common/skills/kai-dev-environment/scripts/runtime.sh'
            env = ['env', 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
                   'ZSETUP_ROOT=/workspace/zsetup', 'ZSETUP_CACHE_DIR=/workspace/zsetup-cache',
                   'GOCACHE=/workspace/go-build-cache', 'GOMODCACHE=/workspace/go-mod-cache',
                   'GOTMPDIR=/workspace/go-tmp', 'GOTOOLCHAIN=local']
            print(f'RUNTIME {target} bootstrap mise', flush=True)
            self.exec(instance, *env, 'bash', bootstrap, 'ensure', 'mise', timeout=480)
            self.exec(instance, *env, 'bash', bootstrap, 'ensure', 'ks-cli', timeout=480)
            gateway = self.start_gateway(instance)
            env += ['KAI_RUNTIME_ACCELERATION=required', 'MISE_HTTP_TIMEOUT=180s']
            self.exec(instance, 'mkdir', '-p', '/workspace/project 中文', '/workspace/go-tmp')
            if target == 'istoreos':
                original_ssl_config = self.exec(instance, 'sha256sum', '/etc/ssl/openssl.cnf')
                self.exec(instance, 'sh', '-ec',
                    'mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; '
                    'touch /etc/config/istoreenhance; '
                    'uci set istoreenhance.kai_lab=istoreenhance; '
                    'uci set istoreenhance.kai_lab.enabled=0; '
                    'uci set istoreenhance.kai_lab.port=5443; '
                    'uci set istoreenhance.kai_lab.adminport=5003; '
                    'uci set istoreenhance.kai_lab.cache=/workspace/gateway-cache; '
                    'uci commit istoreenhance')
            for runtime in ['python', 'node', 'go']:
                version = versions[runtime]
                print(f'RUNTIME {target} {runtime}@{version}', flush=True)
                result = json.loads(self.exec(instance, *env, 'bash', helper, 'install', runtime, version, 'none', timeout=600))
                assert result['runtimeValidation'] == 'passed', result
                probe = json.loads(self.exec(instance, *env, 'bash', helper, 'probe', runtime, version))
                assert probe['installRoot'] == result['installRoot']
                if runtime == 'python':
                    self.exec(instance, *env, 'bash', helper, 'exec', runtime, version, '--', 'python', '-m', 'venv', '/workspace/project 中文/.venv', timeout=180)
                    functional = self.exec(instance, '/workspace/project 中文/.venv/bin/python', '-m', 'pip', '--version')
                    tls_result = self.runtime_tls_check(instance, env, helper, version)
                elif runtime == 'node':
                    functional = self.exec(instance, *env, 'bash', helper, 'exec', runtime, version, '--', 'node', '-e', 'console.log("node-functional-42")')
                    assert functional == 'node-functional-42'
                else:
                    self.exec(instance, 'sh', '-ec', 'printf \'package main\\nimport "fmt"\\nfunc main(){fmt.Println("go-functional-42")}\\n\' > /workspace/sample.go')
                    functional = self.exec(instance, *env, 'bash', helper, 'exec', runtime, version, '--', 'go', 'run', '/workspace/sample.go', timeout=240)
                    assert functional == 'go-functional-42'
                outcomes[runtime] = {'version': version, 'installation': result, 'probe': probe, 'functional': functional}
                if runtime == 'python':
                    outcomes[runtime]['tls'] = tls_result
            # Scope changes are explicit and isolated in the selected HOME.
            root_home = '/workspace/runtime' if target == 'istoreos' else '/root'
            self.exec(instance, 'sh', '-ec', 'test ! -e "$1/.config/mise/config.toml"', 'scope-check', root_home)
            project = json.loads(self.exec(instance, *env, 'sh', '-ec',
                'cd "/workspace/project 中文"; exec bash "$1" install node "$2" project', 'project-select', helper, versions['node'], timeout=180))
            assert project['scope'] == 'project'
            assert versions['node'] in self.exec(instance, 'cat', '/workspace/project 中文/mise.toml')
            global_result = json.loads(self.exec(instance, *env, 'bash', helper, 'install', 'node', versions['node'], 'global', timeout=180))
            assert global_result['scope'] == 'global'
            assert versions['node'] in self.exec(instance, 'cat', root_home + '/.config/mise/config.toml')
            if target == 'istoreos':
                self.exec(instance, 'sha256sum', '-c', '/usr/share/kai-lab/system-curl.sha256')
                assert self.exec(instance, 'sha256sum', '/etc/ssl/openssl.cnf') == original_ssl_config
        finally:
            try:
                if gateway:
                    try:
                        logs = self.remote('cat', gateway['helper']['work'] + '/work/gateway.log')
                        (self.state / f'MS5-{target}-gateway.log').write_text(logs)
                        gateway['logSha256'] = hashlib.sha256(logs.encode()).hexdigest()
                    finally:
                        self.stop_gateway(gateway)
            finally:
                self.cleanup(instance)
        receipt = {'schemaVersion': 1, 'milestone': 'MS5', 'target': target, 'status': 'passed',
                   'imageLock': lock, 'runtimes': outcomes, 'scopes': ['none', 'project', 'exec', 'global'],
                   'gateway': {k:v for k,v in gateway.items() if k not in ['helper', 'name']} if gateway else None,
                   'accelerationValidation': 'pending-MS7-channel-evidence', 'cleanup': 'passed'}
        (self.state / f'MS5-{target}.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt), flush=True)

    def capture_program(self, instance, environment, argv, log, *, user=None, timeout=600):
        script = '''log="$1"; shift; code=0; started="$(date +%s)"
"$@" > "$log.stdout" 2> "$log" || code=$?
finished="$(date +%s)"
digest="$(sha256sum "$log")"; digest="${digest%% *}"
jq -cn --argjson code "$code" --argjson started "$started" --argjson finished "$finished" --rawfile stdout "$log.stdout" --rawfile stderr "$log" --arg digest "$digest" \
'{exitCode:$code,stdout:$stdout,stderr:$stderr,logSha256:$digest,startedUnix:$started,finishedUnix:$finished}'
'''
        return json.loads(self.exec(instance, *environment, 'sh', '-c', script,
                                    'capture', log, *argv, timeout=timeout,user=user))

    def dependency_scenario(self, target, lock, audit=None):
        self.capacity(minimum=5*1024**3)
        milestone = 'MS7' if audit else 'MS6'
        instance = self.create(target, 'ms7-acceleration' if audit else 'ms6-dependencies', lock['image'])
        gateway = None
        outcomes = {'positive': [], 'negative': [], 'prerequisites': {}}
        negative_failures = []
        status = 'failed'
        versions = json.loads((ROOT / 'tests/multisystem/sdk-lock.json').read_text())
        uv_version = json.loads((ROOT / 'tests/multisystem/dependencies-lock.json').read_text())['packages']['uv']['version']
        helper = '/workspace/canonical/common/skills/kai-project-dependencies/scripts/dependencies.sh'
        runtime = '/workspace/canonical/common/skills/kai-dev-environment/scripts/runtime.sh'
        bootstrap = '/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
        env = ['env', 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work', 'ZSETUP_ROOT=/workspace/zsetup',
               'ZSETUP_CACHE_DIR=/workspace/zsetup-cache', 'GOCACHE=/workspace/sdk-go-build',
               'GOMODCACHE=/workspace/sdk-go-mod', 'GOTMPDIR=/workspace/sdk-go-tmp', 'GOTOOLCHAIN=local']

        def fresh_channel(name):
            nonlocal gateway
            if audit:
                if gateway:
                    audit.save_gateway(gateway)
                    self.stop_gateway(gateway)
                gateway = self.start_gateway(instance)
                audit.bind(instance, gateway, env, runtime, helper, versions)
                audit.channel = name

        def project_from_fixture(manager, name):
            project = '/workspace/ms6/' + name + ' 中文'
            self.exec(instance, 'sh', '-ec', 'test ! -e "$1"; mkdir -p "$1"; cp -R "$2/." "$1/"; mkdir -p "$1/.tmp" "$1/.gotmp"',
                      'new-project', project, '/workspace/ms6-fixtures/' + manager)
            return project

        def project_env(project, accelerated=True):
            return [*env, 'KAI_DEP_ACCELERATION=' + ('required' if accelerated else 'none'),
                    'KAI_UV_VERSION=' + uv_version, 'TMPDIR=' + project + '/.tmp',
                    'npm_config_cache=' + project + '/.cache/npm', 'npm_config_audit=false', 'npm_config_fund=false',
                    'PIP_CACHE_DIR=' + project + '/.cache/pip', 'PIP_DISABLE_PIP_VERSION_CHECK=1', 'PIP_TRUSTED_HOST=',
                    'UV_CACHE_DIR=' + project + '/.cache/uv', 'GOCACHE=' + project + '/.cache/go-build',
                    'GOMODCACHE=' + project + '/.cache/go-mod', 'GOPATH=' + project + '/.gopath',
                    'GOTMPDIR=' + project + '/.gotmp']

        def dependency(action, manager, project, *args, accelerated=True):
            version = versions[{'npm': 'node', 'pip': 'python', 'uv': 'python', 'go': 'go'}[manager]]
            return self.capture_program(instance, project_env(project, accelerated),
                                        ['bash', helper, action, manager, version, project, *args],
                                        project + '/client-' + action + '.log')

        def negative(name, result, expected_code=None, needle=None):
            matched = result['exitCode'] != 0
            if expected_code is not None:
                matched = matched and result['exitCode'] == expected_code
            if needle:
                matched = matched and any(text.lower() in (result['stdout'] + result['stderr']).lower() for text in needle)
            if not matched:
                negative_failures.append(name)
            outcomes['negative'].append({'case': name, 'exitCode': result['exitCode'],
                                         'status':'passed' if matched else 'failed',
                                         'logSha256': result['logSha256'], 'stderrTail': result['stderr'][-1200:]})

        try:
            self.stage_skills(instance)
            archive = io.BytesIO()
            fixtures = ROOT / 'tests/multisystem/fixtures/dependencies'
            with tarfile.open(fileobj=archive, mode='w') as tar:
                for path in sorted(fixtures.rglob('*')):
                    assert not path.is_symlink()
                    entry = tarfile.TarInfo(str(path.relative_to(fixtures)))
                    entry.mode = 0o755 if path.is_dir() else 0o644
                    if path.is_dir():
                        entry.type = tarfile.DIRTYPE; tar.addfile(entry)
                    else:
                        content = path.read_bytes(); entry.size = len(content); tar.addfile(entry, io.BytesIO(content))
            self.exec(instance, 'mkdir', '-p', '/workspace/ms6-fixtures', '/workspace/sdk-go-tmp')
            self.exec(instance, 'tar', '-xf', '-', '-C', '/workspace/ms6-fixtures', data=archive.getvalue())
            print(f'DEPENDENCIES {target} SDK prerequisites', flush=True)
            self.exec(instance, *env, 'bash', bootstrap, 'ensure', 'mise', timeout=480)
            self.exec(instance, *env, 'bash', bootstrap, 'ensure', 'ks-cli', timeout=480)
            if audit:
                candidate=self.stage_client_candidate(instance)
                if candidate:
                    env += ['KAI_KSCLI_BIN='+candidate['executable'],
                            'PATH=/workspace/candidate-bin:/root/.local/bin:'+self.exec(instance,'sh','-c','printf %s "$PATH"')]
                    outcomes['clientCandidate']=candidate
                audit.missing_service(instance, env)
            gateway = self.start_gateway(instance)
            env += ['KAI_RUNTIME_ACCELERATION=required', 'MISE_HTTP_TIMEOUT=180s']
            print(f'DEPENDENCIES {target} managed jq prerequisite', flush=True)
            jq_before = self.exec(instance,'sh','-ec','sha256sum "$(command -v jq)"')
            jq_origin = 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64'
            jq_remap = json.loads(self.exec(instance,'curl','-fsS','-H','Content-Type: application/json',
                '-d',json.dumps({'url':jq_origin}),'http://127.0.0.1:5003/api/domainfold/remap'))
            assert jq_remap['input'] == jq_origin and jq_remap['output'].startswith('https://') and jq_remap['output'].endswith('/jq-linux-amd64')
            jq_env = [*env,'JQ_DOWNLOAD_BASE='+jq_remap['output'].rsplit('/',1)[0]]
            jq_owner = '/workspace/canonical/common/skills/kai-tool-bootstrap/resources/jq-install.sh'
            if target == 'istoreos':
                # Firmware setup need not already contain zsetup. The public
                # jq entry uses its owner's jq-independent core bootstrap.
                jq_result = self.capture_program(instance,jq_env,['bash',bootstrap,'ensure','jq'],'/workspace/prerequisite-jq.log')
            else:
                jq_result = self.capture_program(instance,[*jq_env,'ZSETUP_BIN=/root/.local/bin/zsetup','ZSETUP_INSTALLER_MODE=1'],
                    ['/root/.local/bin/zsetup','run','--','sh',jq_owner],'/workspace/prerequisite-jq.log')
            outcomes['jqPrerequisite'] = {'exitCode':jq_result['exitCode'],'logSha256':jq_result['logSha256'],'sourceRemap':jq_remap}
            assert jq_result['exitCode'] == 0, jq_result
            env += ['KAI_JQ_BIN=/root/.local/bin/jq']
            jq_receipt = json.loads(self.exec(instance,*env,'bash',bootstrap,'ensure','jq'))
            assert jq_receipt['status'] == 'reused' and jq_receipt['version'] == 'jq-1.8.2', jq_receipt
            assert self.exec(instance,'sh','-ec','sha256sum "$(command -v jq)"') == jq_before
            outcomes['jqPrerequisite'].update({'receipt':jq_receipt,'firmwareOrSystemJqUnchanged':True})
            outcomes['jqPrerequisite']['binarySha256'] = self.exec(instance,'sha256sum','/root/.local/bin/jq').split()[0]
            if target == 'istoreos':
                original_ssl = self.exec(instance, 'sha256sum', '/etc/ssl/openssl.cnf')
                self.exec(instance, 'sh', '-ec',
                          'mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; '
                          'touch /etc/config/istoreenhance; uci set istoreenhance.kai_lab=istoreenhance; '
                          'uci set istoreenhance.kai_lab.enabled=0; uci set istoreenhance.kai_lab.port=5443; '
                          'uci set istoreenhance.kai_lab.adminport=5003; uci set istoreenhance.kai_lab.cache=/workspace/gateway-cache; uci commit istoreenhance')
                # Git is the native Go catalog fallback when the version API
                # is unavailable. Inspect package effects before installation.
                protected = 'sha256sum /usr/bin/curl /usr/lib/libcurl.so.* /usr/lib/libzstd.so.* /usr/lib/libssl.so.* /usr/lib/libcrypto.so.* /etc/opkg.conf /etc/ssl/openssl.cnf /etc/ssl/certs/ca-certificates.crt'
                protected_before = self.exec(instance,'sh','-ec',protected)
                self.exec(instance,'opkg','update',timeout=180)
                git_plan = self.exec(instance,'opkg','--noaction','install','git','git-http',timeout=180)
                if re.search(r'(?im)^Upgrading |^Installing (?:curl|libcurl\S*|libzstd\S*|openssl\S*|libopenssl\S*)[ (]',git_plan):
                    raise RuntimeError('Git prerequisite would change an existing or protected system package; installation was not applied')
                self.exec(instance,'opkg','install','git','git-http',timeout=180)
                assert self.exec(instance,'sh','-ec',protected) == protected_before
                outcomes['gitPrerequisite'] = {'version':self.exec(instance,'git','--version'),'manager':'opkg','protectedSystemFilesUnchanged':True}
            if audit:
                for lane in ['file', 'git', 'docker']:
                    fresh_channel(lane)
                    audit.basic_lane(lane)
            for sdk in ['python', 'node', 'go']:
                fresh_channel('sdk-' + sdk)
                print(f'DEPENDENCIES {target} install {sdk}', flush=True)
                sdk_env = [*env, 'KAI_GO_GIT_METADATA=required'] if sdk == 'go' else env
                if audit:
                    sdk_env = [*sdk_env, 'MISE_DEBUG=1', 'MISE_ALWAYS_KEEP_DOWNLOAD=1', 'MISE_CACHE_DIR=/workspace/cache-sdk-' + sdk]
                captured = self.capture_program(instance,sdk_env,['bash',runtime,'install',sdk,versions[sdk],'none'],
                                                '/workspace/prerequisite-' + sdk + '.log')
                outcomes['prerequisites'][sdk] = {'exitCode':captured['exitCode'],'logSha256':captured['logSha256']}
                if sdk == 'node' and captured['exitCode'] != 0:
                    # Inspect an untrusted failed archive as data; never extract
                    # or execute it and never replace the expected digest.
                    archive_dir = ('/workspace/runtime' if target == 'istoreos' else '/root') + '/.local/share/mise/downloads/node/' + versions['node']
                    diagnostic = '''import gzip,hashlib,json,sys
from pathlib import Path
rows=[]
for p in Path(sys.argv[1]).glob("node-*.tar.gz"):
 if not p.is_file() or p.is_symlink(): continue
 with p.open("rb") as f: digest=hashlib.file_digest(f,"sha256").hexdigest()
 row={"file":p.name,"size":p.stat().st_size,"sha256":digest}
 try:
  with gzip.open(p,"rb") as f:
   count=0
   while chunk:=f.read(1024*1024):
    count+=len(chunk)
    if count>256*1024*1024: raise ValueError("diagnostic decompression bound reached")
  row["gzipValidation"]="passed"
 except Exception as e: row["gzipValidation"]=type(e).__name__
 rows.append(row)
print(json.dumps(rows))
'''
                    try:
                        outcomes['prerequisites'][sdk]['failedArchiveDiagnostic'] = json.loads(self.exec(
                            instance,*env,'bash',runtime,'exec','python',versions['python'],'--','python','-c',diagnostic,archive_dir,timeout=40))
                    except (RuntimeError,ValueError,subprocess.SubprocessError):
                        outcomes['prerequisites'][sdk]['failedArchiveDiagnosticUnavailable'] = True
                assert captured['exitCode'] == 0, captured
                result = json.loads(captured['stdout'])
                assert result['runtimeValidation'] == 'passed', result
                if audit:
                    audit.sdk(sdk, captured)
            print(f'DEPENDENCIES {target} install uv@{uv_version}', flush=True)
            captured = self.capture_program(instance,env,['bash',runtime,'exec','python',versions['python'],'--',
                                            'ks-cli','mise','install','uv@' + uv_version],'/workspace/prerequisite-uv.log')
            outcomes['prerequisites']['uv'] = {'exitCode':captured['exitCode'],'logSha256':captured['logSha256']}
            assert captured['exitCode'] == 0, captured
            home = '/workspace/runtime' if target == 'istoreos' else '/root'
            global_files = [home + '/.npmrc', home + '/.config/pip/pip.conf', home + '/.config/go/env']
            self.exec(instance, 'sh', '-ec',
                      'mkdir -p "$1/.config/pip" "$1/.config/go"; '
                      'printf "fund=false\n# kai-preserve-global\n" > "$1/.npmrc"; '
                      'printf "[global]\ndisable-pip-version-check = true\n# kai-preserve-global\n" > "$1/.config/pip/pip.conf"; '
                      'printf "GOFLAGS=-trimpath\n" > "$1/.config/go/env"', 'global-fixture', home)
            global_before = self.exec(instance, 'sha256sum', *global_files)
            system_python_before = self.exec(instance, 'sh', '-c', 'if test -e /usr/bin/python3; then sha256sum /usr/bin/python3; else echo absent; fi')
            projects = {}
            for manager in ['npm', 'pip', 'uv', 'go']:
                for cycle in ['cold', 'repeat']:
                    print(f'DEPENDENCIES {target} {manager} {cycle}', flush=True)
                    project = project_from_fixture(manager, manager + '-' + cycle)
                    projects[manager + '-' + cycle] = project
                    names = {'npm': ['package.json', 'package-lock.json'], 'pip': ['requirements.txt'],
                             'uv': ['requirements.txt'], 'go': ['go.mod', 'go.sum']}[manager]
                    paths = [project + '/' + name for name in names]
                    before = self.exec(instance, 'sha256sum', *paths)
                    metadata = None
                    if audit and cycle == 'cold':
                        fresh_channel('go-modules' if manager == 'go' else manager)
                        if manager == 'npm':
                            metadata = dependency('run', 'npm', project, '--', 'view', 'is-number@7.0.0', '--json')
                            assert metadata['exitCode'] == 0, metadata
                    installed = dependency('install', manager, project)
                    assert installed['exitCode'] == 0, installed
                    assert json.loads(installed['stdout'])['status'] == 'passed', installed
                    if manager == 'npm':
                        argv = ['bash', runtime, 'exec', 'node', versions['node'], '--', 'node', project + '/check.cjs']
                        expected = 'is-number:7.0.0:42'
                    elif manager in ['pip', 'uv']:
                        argv = ['bash', runtime, 'exec', 'python', versions['python'], '--', project + '/.venv/bin/python', project + '/check.py', project + '/.venv']
                        expected = 'idna:3.10:venv-functional'
                    else:
                        argv = ['bash', helper, 'run', 'go', versions['go'], project, '--', 'run', '.']
                        expected = '123e4567-e89b-12d3-a456-426614174000'
                    functional = self.capture_program(instance, project_env(project), argv, project + '/functional.log')
                    assert functional['exitCode'] == 0 and functional['stdout'].strip() == expected, functional
                    assert self.exec(instance, 'sha256sum', *paths) == before, 'existing lock or manifest changed'
                    sources = json.loads(self.exec(instance, 'bash', helper, 'sources', manager,
                                                  versions[{'npm':'node','pip':'python','uv':'python','go':'go'}[manager]], project))
                    assert sources['accelerationValidation'] == 'not-tested'
                    outcomes['positive'].append({'manager':manager,'cycle':cycle,'project':project,'installation':json.loads(installed['stdout']),
                                                  'functional':expected,'locksUnchanged':True,'clientLogSha256':installed['logSha256'],
                                                  'functionalLogSha256':functional['logSha256'],'sourceInspection':sources})
                    if audit and cycle == 'cold':
                        audit.package(manager, project, project_env(project), installed, functional, metadata)
            project = projects['uv-cold']
            uv_cli = dependency('run','uv',project,'--','--version')
            assert uv_cli['exitCode'] == 0 and uv_cli['stdout'].startswith('uv ' + uv_version), uv_cli
            self.exec(instance,'sh','-ec','cat > "$1/pyproject.toml"','uv-project',project,
                      data=b'[project]\nname="kai-uv-demo"\nversion="1.0.0"\nrequires-python=">=3.13"\ndependencies=["idna==3.10"]\n')
            generated = dependency('run','uv',project,'--','lock')
            assert generated['exitCode'] == 0, generated
            before = self.exec(instance,'sha256sum',project + '/uv.lock',project + '/pyproject.toml')
            synchronized = dependency('install','uv',project)
            assert synchronized['exitCode'] == 0, synchronized
            assert self.exec(instance,'sha256sum',project + '/uv.lock',project + '/pyproject.toml') == before
            function = self.capture_program(instance,project_env(project),['bash',runtime,'exec','python',versions['python'],'--',
                        project + '/.venv/bin/python',project + '/check.py',project + '/.venv'],project + '/uv-lock-functional.log')
            assert function['exitCode'] == 0 and function['stdout'].strip() == 'idna:3.10:venv-functional', function
            outcomes['uvProjectLock'] = {'toolVersion':uv_cli['stdout'].strip(),'explicitGeneration':'passed','frozenSync':'passed','lockAndManifestUnchanged':True,'functional':'passed'}
            project = projects['npm-cold']
            old_manifest = json.loads(self.exec(instance, 'cat', project + '/package.json'))
            added = dependency('add', 'npm', project, '--', 'is-number@6.0.0')
            assert added['exitCode'] == 0, added
            expected_manifest = {**old_manifest, 'dependencies': {'is-number':'6.0.0'}}
            assert json.loads(self.exec(instance, 'cat', project + '/package.json')) == expected_manifest
            added_lock = json.loads(self.exec(instance, 'cat', project + '/package-lock.json'))
            assert added_lock['packages']['node_modules/is-number']['version'] == '6.0.0'
            function = self.capture_program(instance, project_env(project), ['bash', runtime, 'exec', 'node', versions['node'], '--',
                        'node', project + '/check.cjs', '6.0.0'], project + '/add-functional.log')
            assert function['exitCode'] == 0 and function['stdout'].strip() == 'is-number:6.0.0:42', function
            outcomes['explicitAdd'] = {'manager':'npm','version':'6.0.0','manifestAndLockUpdated':True,'functional':'passed'}
            print(f'DEPENDENCIES {target} negative cases', flush=True)
            project = project_from_fixture('npm', 'missing-runtime')
            missing = self.capture_program(instance, project_env(project), ['bash',helper,'install','npm','0.0.0',project], project + '/missing.log')
            negative('missing-runtime', missing, 4, ['runtime-not-installed'])
            project = project_from_fixture('npm', 'mismatched-lock')
            self.exec(instance, 'sh', '-ec', 'sed -i s/7.0.0/6.0.0/ "$1/package.json"', 'mismatch', project)
            before = self.exec(instance, 'sha256sum', project + '/package-lock.json')
            negative('lock-mismatch', dependency('install','npm',project), 1, ['EUSAGE','lock file','Invalid:'])
            assert self.exec(instance, 'sha256sum', project + '/package-lock.json') == before
            project = project_from_fixture('pip', 'missing-dependency')
            self.exec(instance, 'sh', '-ec', 'printf "idna==0.0.0\n" > "$1/requirements.txt"', 'missing-package', project)
            negative('missing-dependency', dependency('install','pip',project), 1, ['No matching distribution','Could not find a version'])
            project = project_from_fixture('pip', 'network-failure')
            self.exec(instance, *env, 'bash', runtime, 'exec', 'python', versions['python'], '--', 'python','-m','venv',project + '/.venv',timeout=180)
            negative('network-failure', dependency('run','pip',project,'--','install','-vv','--no-cache-dir','--retries','0','--timeout','2',
                     '--index-url','https://127.0.0.1:9/simple','idna==3.10',accelerated=False), 1, ['Connection refused','Failed to establish a new connection'])
            project = project_from_fixture('native-negative', 'missing-native-library')
            installed = dependency('install','pip',project)
            assert installed['exitCode'] == 0, installed
            native = self.capture_program(instance, project_env(project), ['bash',runtime,'exec','python',versions['python'],'--',
                     project + '/.venv/bin/python','-c','from pyzbar.pyzbar import decode'],project + '/native-import.log')
            negative('missing-native-library',native,1,['Unable to find zbar shared library'])
            assert self.exec(instance, 'sha256sum', *global_files) == global_before, 'global dependency configuration changed'
            assert self.exec(instance, 'sh', '-c', 'if test -e /usr/bin/python3; then sha256sum /usr/bin/python3; else echo absent; fi') == system_python_before
            if target == 'istoreos':
                self.exec(instance, 'sha256sum','-c','/usr/share/kai-lab/system-curl.sha256')
                assert self.exec(instance,'sha256sum','/etc/ssl/openssl.cnf') == original_ssl
            outcomes['globalConfigurationUnchanged'] = True
            outcomes['systemPythonUnchanged'] = True
            assert not negative_failures, 'negative acceptance failures: ' + ','.join(negative_failures)
            if audit:
                audit.negative_cases()
                outcomes['acceleration'] = audit.result()
                assert outcomes['acceleration']['status'] == 'passed', outcomes['acceleration']
            status = 'passed'
        finally:
            gateway_clean = gateway is None
            try:
                try:
                    prerequisite_logs = json.loads(self.remote_python(
                        'import json,sys; from pathlib import Path; root=Path(sys.argv[1]); '
                        'print(json.dumps({p.name:p.read_text(errors="replace") for p in root.glob("prerequisite-*.log") if p.is_file()}))',
                        instance['work'] + '/work'))
                    for name, content in prerequisite_logs.items():
                        (self.state / f'{milestone}-{target}-{name}').write_text(content)
                    outcomes['prerequisiteLogs'] = {name:hashlib.sha256(content.encode()).hexdigest() for name,content in prerequisite_logs.items()}
                except (RuntimeError,OSError,ValueError):
                    outcomes['prerequisiteLogsUnavailable'] = True
                if gateway:
                    try:
                        logs = self.remote('cat',gateway['helper']['work'] + '/work/gateway.log')
                        (self.state / f'{milestone}-{target}-gateway.log').write_text(logs)
                        gateway['logSha256'] = hashlib.sha256(logs.encode()).hexdigest()
                        if audit:
                            audit.save_gateway(gateway)
                    finally:
                        self.stop_gateway(gateway); gateway_clean = True
            finally:
                main_clean = False
                try:
                    self.cleanup(instance); main_clean = True
                finally:
                    if audit:
                        outcomes['acceleration'] = audit.result()
                    receipt = {'schemaVersion':1,'milestone':milestone,'target':target,
                               'status':status if gateway_clean and main_clean else 'failed','imageLock':lock,'outcomes':outcomes,
                               'gateway':{k:v for k,v in gateway.items() if k not in ['helper','name']} if gateway else None,
                               'clientCacheScope':'fresh per project and repeat directory','gatewayCacheScope':'fresh per cold channel' if audit else 'shared within this target scenario; not acceleration evidence',
                               'accelerationValidation':outcomes['acceleration']['status'] if audit else 'pending-MS7-channel-evidence','cleanup':'passed' if gateway_clean and main_clean else 'failed'}
                    (self.state / f'{milestone}-{target}.json').write_text(json.dumps(receipt,indent=2))
        print(json.dumps(receipt),flush=True)

    def software_scenario(self, target, lock):
        instance = self.create(target, 'ms4-software', lock['image'])
        outcomes = {}
        missing = []
        try:
            self.stage_skills(instance)
            helper = '/workspace/canonical/common/skills/kai-software/scripts/software.sh'
            env = ['env', 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
                   'ZSETUP_ROOT=/workspace/zsetup', 'ZSETUP_CACHE_DIR=/workspace/zsetup-cache']
            def software(*args, provider=None):
                override = ['KAI_SOFTWARE_PROVIDER=' + provider] if provider else []
                return self.exec(instance, *env, *override, 'bash', helper, *args, timeout=240)
            provider = 'opkg' if target == 'istoreos' else 'apt'
            software('refresh', provider)
            before_index = self.exec(instance, 'sh', '-c', 'find /var/lib/apt/lists /var/opkg-lists /tmp/is-root/tmp/opkg-lists -maxdepth 1 -type f -exec sha256sum {} \\; 2>/dev/null | sort')
            search = json.loads(software('search', 'tree'))
            assert search and any(row['id'] == provider + ':tree' for row in search), 'exact tree package absent from search: ' + json.dumps(search)
            info = json.loads(software('info', provider + ':tree'))
            after_index = self.exec(instance, 'sh', '-c', 'find /var/lib/apt/lists /var/opkg-lists /tmp/is-root/tmp/opkg-lists -maxdepth 1 -type f -exec sha256sum {} \\; 2>/dev/null | sort')
            assert before_index == after_index, 'query refreshed or changed indexes'
            version = info['availableVersion']
            installed = json.loads(software('install', provider + ':tree', version))
            assert installed['installedVersion'] == version
            repeat = json.loads(software('install', provider + ':tree', version))
            assert repeat['installedVersion'] == version
            files = software('files', provider + ':tree')
            executable = next(line for line in files.splitlines() if line.startswith('/') and PurePosixPath(line).name == 'tree')
            self.exec(instance, 'sh', '-ec', 'mkdir -p /workspace/ms4-sample; printf sample > /workspace/ms4-sample/known-file.txt')
            functional = self.exec(instance, executable, '/workspace/ms4-sample')
            assert 'known-file.txt' in functional, 'tree did not list the known sample'
            assert software('owner', executable)
            self.exec(instance, 'sh', '-ec', 'printf keep-project > /workspace/ms4-keep-project')
            removed = json.loads(software('remove', provider + ':tree'))
            assert removed['status'] == 'passed'
            assert not json.loads(software('info', provider + ':tree'))['installed']
            assert self.exec(instance, 'cat', '/workspace/ms4-keep-project') == 'keep-project'
            outcomes['systemPackage'] = {'id': provider + ':tree', 'version': version,
                                         'search': search, 'functional': functional, 'queryIndexesUnchanged': True,
                                         'repeatInstall': 'passed', 'remove': 'passed', 'projectPreserved': True}
            if target == 'istoreos':
                software('refresh', 'istore')
                info = json.loads(software('info', 'istore:ks-cli'))
                version = info['availableVersion']
                result = json.loads(software('install', 'istore:ks-cli', version))
                assert result['installedVersion'] == version
                functional = self.exec(instance, '/usr/bin/ks-cli', '--help')
                assert 'ks-cli' in functional.lower()
                software('files', 'istore:ks-cli')
                software('remove', 'istore:ks-cli')
                assert not json.loads(software('info', 'istore:ks-cli'))['installed']
                outcomes['internalSoftware'] = {'id': 'istore:ks-cli', 'version': version, 'functional': functional, 'remove': 'passed'}
                self.exec(instance, 'sha256sum', '-c', '/usr/share/kai-lab/system-curl.sha256')
            else:
                bootstrap = '/workspace/canonical/common/skills/kai-tool-bootstrap/scripts/tool.sh'
                self.exec(instance, *env, 'bash', bootstrap, 'ensure', 'zsetup', timeout=180)
                software('refresh', 'zsetup')
                search = json.loads(software('search', 'linkspace', provider='zsetup'))
                assert any(row['id'] == 'zsetup:linkspace' for row in search)
                result = json.loads(software('install', 'zsetup:linkspace'))
                assert result['installed']
                version = self.exec(instance, '/root/.local/bin/linkspace', 'version')
                functional = json.loads(self.exec(instance, '/root/.local/bin/linkspace', 'capabilities', '--json'))
                assert functional, 'Linkspace capability query returned no result'
                self.exec(instance, 'sh', '-ec',
                    'printf keep-config > /root/.local/lib/linkease/linkspace/config.json; '
                    'printf keep-cache > /workspace/zsetup-cache/ms4-keep-cache')
                removal = json.loads(software('remove', 'zsetup:linkspace'))
                assert removal['status'] == 'passed'
                assert not json.loads(software('info', 'zsetup:linkspace'))['installed']
                self.exec(instance, 'sh', '-ec',
                    'test ! -L /root/.local/bin/linkspace; '
                    'test ! -e /root/.local/lib/linkease/linkspace/versions; '
                    'test "$(cat /root/.local/lib/linkease/linkspace/config.json)" = keep-config; '
                    'test "$(cat /workspace/zsetup-cache/ms4-keep-cache)" = keep-cache')
                assert json.loads(software('remove', 'zsetup:linkspace'))['status'] == 'passed'
                outcomes['internalSoftware'] = {'id': 'zsetup:linkspace', 'search': search,
                                               'version': version, 'functional': functional,
                                               'remove': 'passed', 'removalReceipt': removal,
                                               'repeatRemove': 'passed', 'configAndCachePreserved': True}
            assert self.exec(instance, 'cat', '/workspace/ms4-keep-project') == 'keep-project'
        finally:
            self.cleanup(instance)
        receipt = {'schemaVersion': 1, 'milestone': 'MS4', 'target': target,
                   'status': 'blocked' if missing else 'passed', 'imageLock': lock,
                   'outcomes': outcomes, 'missingCapabilities': missing, 'cleanup': 'passed'}
        (self.state / f'MS4-{target}.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt), flush=True)
        if missing:
            raise RuntimeError('MS4 product decision required: ' + ', '.join(missing))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, default=os.environ.get('KAI_LAB_CONFIG'))
    parser.add_argument('action', choices=['plan', 'scenario'])
    parser.add_argument('--target', choices=list(BASES), required=True)
    parser.add_argument('--milestone', default='MS1')
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, cancel_lab)
    signal.signal(signal.SIGINT, cancel_lab)
    try:
        if not args.config:
            raise ValueError('invalid lab configuration: set KAI_LAB_CONFIG outside the repository')
        config = json.loads(Path(args.config).read_text())
        lab = Lab(config)
        if args.action == 'plan':
            print(json.dumps(lab.plan(args.target)))
        else:
            lab.state.mkdir(parents=True, exist_ok=True, mode=0o700)
            with (lab.state / 'operation.lock').open('a') as lock:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                lab.scenario(args.target, args.milestone)
        return 0
    except LabCancelled:
        print('lab cancelled; owned runtime resources cleaned', file=sys.stderr)
        return 130
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError, AssertionError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
