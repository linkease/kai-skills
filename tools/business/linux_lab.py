#!/usr/bin/env python3
"""Native Linux acceptance of independently staged skills and owned collections."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

from model import ROOT
from package import tree_digest

sys.path.insert(0, str(ROOT / 'tools/multisystem'))
from lab import Lab
from distribution_lab import Journey, stage_tree
import acceleration_lab


class BusinessLab(Lab):
    def __init__(self, config, image_locks):
        super().__init__(config)
        self.image_locks = Path(image_locks)

    def prepare(self, target):
        lock = json.loads((self.image_locks / (target + '-image.json')).read_text())
        actual = json.loads(self.remote('docker', 'image', 'inspect', lock['image']))[0]
        if actual['Id'] != lock['imageId']:
            raise ValueError('frozen lab image changed')
        return lock


def collection_stage(platform, mode, destination):
    """A self-contained offline collection; skills are the exact independent bytes."""
    destination.mkdir(parents=True)
    lock = json.loads((ROOT / 'bundles' / (platform + '-all-' + mode + '.json')).read_text())
    catalog = json.loads((ROOT / 'business-catalog.json').read_text())
    names = {member['id'] for member in lock['members']}
    catalog['skills'] = [p for p in catalog['skills'] if p['id'] in names]
    (destination / 'business-catalog.json').write_text(json.dumps(catalog))
    shutil.copy2(ROOT / 'catalog.json', destination / 'catalog.json')
    (destination / 'bundles').mkdir()
    shutil.copy2(ROOT / 'bundles' / (platform + '-all-' + mode + '.json'), destination / 'bundles')
    (destination / 'tools').mkdir()
    shutil.copy2(ROOT / 'tools/install-business.sh', destination / 'tools/install-business.sh')
    for name in sorted(names):
        shutil.copytree(ROOT / 'skills' / name, destination / 'skills' / name)
    (destination / 'install.sh').write_text('#!/bin/sh\nset -eu\nroot="$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)"\n'
        'exec sh "$root/tools/install-business.sh" --platform ' + platform + ' --all --mode ' + mode + ' "$@"\n')
    preset = json.loads((ROOT / 'platforms' / platform / mode / 'preset.json').read_text())
    preset.update(resources=[], treeDigest=tree_digest(destination / 'skills'))
    (destination / 'preset.json').write_text(json.dumps(preset, indent=2) + '\n')


def bundle_stage(name, destination):
    destination.mkdir(parents=True)
    lock = json.loads((ROOT / 'bundles' / (name + '.json')).read_text())
    for relative in ['business-catalog.json', 'catalog.json', 'tools/install-business.sh', 'bundles/' + name + '.json']:
        path = destination / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, path)
    for member in lock['members']:
        shutil.copytree(ROOT / 'skills' / member['id'], destination / 'skills' / member['id'])
    return lock


def environment(target):
    return ['env', 'PATH=/workspace/candidate-bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'KAI_PLATFORM=' + target, 'KAI_TOOL_WORK_DIR=/workspace/bootstrap-work',
            'ZSETUP_ROOT=/workspace/zsetup', 'ZSETUP_CACHE_DIR=/workspace/zsetup-cache',
            'KAI_KSCLI_BIN=/workspace/candidate-bin/ks-cli', 'KAI_RUNTIME_ACCELERATION=required',
            'KAI_DEP_ACCELERATION=required', 'MISE_HTTP_TIMEOUT=180s', 'MISE_LOG_LEVEL=debug',
            'PIP_DISABLE_PIP_VERSION_CHECK=1', 'KAI_USAGE_TEMP_DIR=/workspace/scratch']


class NativeTasks:
    def __init__(self, lab, target, tag):
        self.lab, self.target, self.tag = lab, target, tag
        self.folder = lab.state / (target + '-' + tag)
        self.folder.mkdir(parents=True, mode=0o700)
        self.receipt = {'target': target, 'tag': tag, 'status': 'running', 'cases': [], 'captures': {}}
        self.instance = lab.create(target, tag, lab.prepare(target)['image'])
        self.gateway = None
        self.env = environment(target)
        self.version = json.loads((ROOT / 'tests/multisystem/sdk-lock.json').read_text())['node']
        self.capture_function = None

    def save(self):
        (self.folder / 'receipt.json').write_text(json.dumps(self.receipt, ensure_ascii=False, indent=2) + '\n')

    def capture(self, name, argv, *, env=None, expect=0, timeout=600):
        print('NATIVE ' + self.target + ' ' + self.tag + ' ' + name, flush=True)
        if self.capture_function:
            value = self.capture_function(name, argv, env=env or self.env, timeout=timeout)
        else:
            value = self.lab.capture_program(self.instance, env or self.env, argv, '/workspace/logs/' + name, timeout=timeout)
        (self.folder / (name + '.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2))
        self.receipt['captures'][name] = {key: value[key] for key in ['exitCode', 'logSha256', 'startedUnix', 'finishedUnix']}
        self.save()
        if expect is not None and value['exitCode'] != expect:
            raise RuntimeError(name + ' exit=' + str(value['exitCode']) + ': ' + value['stderr'][-1800:] + value['stdout'][-1200:])
        return value

    def stage_single(self, name):
        # Only this run's exact staging path is replaced; no installed Agent directory.
        self.lab.exec(self.instance, 'sh', '-ec', 'test ! -L /workspace/one; rm -rf /workspace/one; mkdir /workspace/one')
        stage_tree(self.lab, self.instance, ROOT / 'skills' / name, '/workspace/one/' + name)
        count = self.lab.exec(self.instance, 'sh', '-ec', 'find /workspace -name SKILL.md -type f | wc -l')
        if int(count) != 1:
            raise RuntimeError('single-skill target has additional active skill directories: ' + count)
        return '/workspace/one/' + name

    def setup(self):
        self.lab.exec(self.instance, 'mkdir', '-p', '/workspace/logs', '/workspace/scratch', '/workspace/samples')
        if self.target in {'ubuntu', 'debian'}:
            config = 'Acquire::Retries "0"; Acquire::http::Timeout "30"; Acquire::https::Timeout "30"; APT::Update::Error-Mode "any";\n'
            if self.target == 'debian':
                original = self.lab.exec(self.instance, 'cat', '/etc/apt/sources.list.d/debian.sources')
                sources = original.replace('http://deb.debian.org', 'https://mirrors.tuna.tsinghua.edu.cn')
                self.lab.exec(self.instance, 'sh', '-ec', 'cat > /workspace/lab-debian.sources', data=sources.encode())
                config += 'Dir::Etc::sourcelist "/workspace/lab-debian.sources"; Dir::Etc::sourceparts "-";\n'
                self.receipt['testRepository'] = {'configuration': sources,
                    'originalConfigurationSha256': hashlib.sha256(original.encode()).hexdigest(),
                    'systemSourcesModified': False, 'signatureValidation': 'native-apt-keyring'}
            self.lab.exec(self.instance, 'sh', '-ec', 'cat > /workspace/lab-apt.conf', data=config.encode())
            self.env += ['APT_CONFIG=/workspace/lab-apt.conf']
        self.receipt['client'] = self.lab.stage_client_candidate(self.instance)
        self.gateway = self.lab.start_gateway(self.instance)
        self.receipt['gateway'] = self.gateway.get('candidate')
        self.receipt['imageId'] = self.lab.prepare(self.target)['imageId']
        if self.target == 'istoreos':
            self.receipt['systemBefore'] = self.lab.exec(self.instance, 'sh', '-ec',
                'sha256sum -c /usr/share/kai-lab/system-curl.sha256; sha256sum /etc/ssl/openssl.cnf')
            self.lab.exec(self.instance, 'sh', '-ec',
                'mkdir -p /workspace/runtime; uci set mise.main.runtime_dir=/workspace/runtime; uci commit mise; '
                'touch /etc/config/istoreenhance; uci set istoreenhance.kai_lab=istoreenhance; '
                'uci set istoreenhance.kai_lab.enabled=0; uci set istoreenhance.kai_lab.port=5443; '
                'uci set istoreenhance.kai_lab.adminport=5003; uci commit istoreenhance')

    def bootstrap(self, root, tools=('mise', 'zsetup')):
        helper = root + '/scripts/tool.sh'
        extra = []
        if self.target == 'istoreos':
            url = 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64'
            remap = json.loads(self.lab.exec(self.instance, 'curl', '-fsS', '-H', 'Content-Type: application/json',
                '-d', json.dumps({'url': url}), 'http://127.0.0.1:5003/api/domainfold/remap'))
            extra = ['JQ_DOWNLOAD_BASE=' + remap['output'].rsplit('/', 1)[0]]
        jq_receipt = json.loads(self.capture('ensure-full-jq', ['bash', helper, 'ensure', 'jq'], env=self.env + extra)['stdout'])
        self.env += ['KAI_JQ_BIN=' + jq_receipt['path']]
        self.capture('repeat-full-jq', ['bash', helper, 'ensure', 'jq'])
        self.capture('verify-jq-function', ['sh', '-ec', '"$KAI_JQ_BIN" -ne \'("中文"|test("中文")) and (("abc"|sub("a";"x"))=="xbc")\''])
        for tool in tools:
            self.capture('prepare-' + tool, ['bash', helper, 'ensure', tool])
        if 'zsetup' in tools:
            core = json.loads(self.capture('find-zsetup', ['bash', helper, 'probe', 'zsetup'])['stdout'])
            self.env += ['KAI_ZSETUP_BIN=' + core['path']]
            self.receipt['core'] = core

    def software(self, root):
        helper = root + '/scripts/software.sh'
        provider = 'opkg' if self.target == 'istoreos' else 'apt'
        self.capture('refresh-software', ['bash', helper, 'refresh', provider])
        info = json.loads(self.capture('query-software', ['bash', helper, 'info', provider + ':tree'])['stdout'])
        version = info['availableVersion']
        self.capture('install-software', ['bash', helper, 'install', provider + ':tree', version])
        self.lab.exec(self.instance, 'sh', '-ec', 'printf fixture > /workspace/samples/known-file.txt')
        value = self.capture('use-software', ['tree', '/workspace/samples'])
        assert 'known-file.txt' in value['stdout']
        self.capture('remove-software', ['bash', helper, 'remove', provider + ':tree'])
        self.capture('prepare-internal-index', ['bash', helper, 'refresh', 'zsetup'])
        product = json.loads(self.capture('prepare-linkspace', ['bash', helper, 'install', 'zsetup:linkspace'])['stdout'])
        frozen = json.loads((ROOT / 'tests/multisystem/usage-lock.json').read_text())['linkspace']
        assert product['installedVersion'] == frozen['version']
        assert self.lab.exec(self.instance, 'sha256sum', '/root/.local/bin/linkspace').split()[0] == frozen['artifacts']['x64']['sha256']

    def runtime(self, root):
        helper = root + '/scripts/runtime.sh'
        # The gateway validates the complete 55 MiB musl archive before replying.
        # The measured upstream can sustain ~100 KiB/s; 180 s cancels valid progress.
        sdk_env = self.env + (['MISE_HTTP_TIMEOUT=900s'] if self.target == 'istoreos' else [])
        if self.target == 'istoreos':
            self.receipt['sdkTransportBudget'] = {'miseRequestSeconds': 900, 'commandSeconds': 1800,
                'routing': 'native-auto', 'archiveValidation': 'unchanged'}
        result = json.loads(self.capture('install-node', ['bash', helper, 'install', 'node', self.version, 'none'],
            env=sdk_env, timeout=1800 if self.target == 'istoreos' else 600)['stdout'])
        assert result['runtimeValidation'] == 'passed' and result['scope'] == 'none'
        value = self.capture('use-node', ['bash', helper, 'exec', 'node', self.version, '--', 'node', '-e',
            'if(process.version!=="v' + self.version + '")process.exit(5); console.log("node-functional:"+process.version)'])
        assert 'node-functional:v' + self.version in value['stdout']

    def dependencies(self, root):
        helper = root + '/scripts/dependencies.sh'
        runtime = root + '/resources/runtime/kai-dev-environment/scripts/runtime.sh'
        stage_tree(self.lab, self.instance, ROOT / 'tests/multisystem/fixtures/dependencies/npm', '/workspace/project')
        before = self.lab.exec(self.instance, 'sha256sum', '/workspace/project/package-lock.json')
        env = self.env + ['npm_config_cache=/workspace/project/.cache/npm']
        metadata = self.capture('npm-metadata', ['bash', helper, 'run', 'npm', self.version, '/workspace/project', '--', 'view', 'is-number@7.0.0', '--json'], env=env)
        installed = self.capture('npm-install', ['bash', helper, 'install', 'npm', self.version, '/workspace/project'], env=env)
        used = self.capture('npm-functional', ['bash', runtime, 'exec', 'node', self.version, '--', 'node', '/workspace/project/check.cjs'], env=env)
        assert 'is-number:7.0.0:42' in used['stdout']
        assert self.lab.exec(self.instance, 'sha256sum', '/workspace/project/package-lock.json') == before
        packed = self.capture('npm-pack', ['bash', helper, 'run', 'npm', self.version, '/workspace/project', '--',
            'pack', 'is-number@7.0.0', '--pack-destination', '/workspace/project', '--json'], env=env)
        hashes = json.loads(self.capture('npm-hash', ['bash', runtime, 'exec', 'node', self.version, '--', 'node', '-e',
            'const c=require("crypto"),b=require("fs").readFileSync("/workspace/project/is-number-7.0.0.tgz");console.log(JSON.stringify({sha256:c.createHash("sha256").update(b).digest("hex"),sri:"sha512-"+c.createHash("sha512").update(b).digest("base64")}))'], env=env)['stdout'])
        frozen = json.loads((ROOT / 'tests/multisystem/dependencies-lock.json').read_text())['packages']['npm']
        assert hashes['sri'] == frozen['integrity']
        audit = acceleration_lab.AccelerationAudit(self.lab, self.target)
        audit.bind(self.instance, self.gateway, self.env, runtime, helper, {'node': self.version})
        acceleration_lab.EVIDENCE = ROOT / 'skills/kai-download-acceleration/scripts/evidence.sh'
        audit.prove('npm', [metadata, installed, used, packed], [
            audit.request('metadata', 'dl-npm.linkease.net:5443', '/is-number'),
            audit.request('artifact', 'dl-npm.linkease.net:5443', '/is-number/-/is-number-7.0.0.tgz', hashes['sha256'])])
        assert not audit.failures, audit.records
        self.receipt['acceleration'] = audit.records

    def download(self, root):
        helper = root + '/scripts/accelerate.sh'
        lock = json.loads((ROOT / 'tests/multisystem/acceleration-lock.json').read_text())
        item = lock['file']
        result = json.loads(self.capture('verified-file', ['bash', helper, 'download', item['url'], '/workspace/verified-file', item['sha256']])['stdout'])
        assert self.lab.exec(self.instance, 'sha256sum', '/workspace/verified-file').split()[0] == item['sha256']
        if not self.lab.exec(self.instance, 'sh', '-c', 'command -v git || true'):
            assert self.target == 'istoreos', 'native Git prerequisite absent'
            plan = self.capture('git-native-install-plan', ['opkg', '--noaction', 'install', 'git-http'])
            operations = re.findall(r'^(?:Installing|Upgrading|Downgrading|Removing)\s+(\S+)',
                plan['stdout'] + '\n' + plan['stderr'], re.M)
            assert operations and all(not re.search(r'curl|zstd|openssl|ustream|ca-bundle|ca-certificates|opkg',
                name, re.I) for name in operations), 'Git plan would replace a protected runtime: ' + str(operations)
            self.capture('git-native-install', ['opkg', 'install', 'git-http'])
        item = lock['git']
        cloned = json.loads(self.capture('verified-git', ['bash', helper, 'git-clone', item['repository'], '/workspace/repository', item['commit']])['stdout'])
        assert cloned['commit'] == item['commit'] and cloned['tree'] == item['tree']
        self.receipt['fileRoute'] = result['download'].get('selected')

    def storage(self, root):
        helper = root + '/scripts/usage.sh'
        self.lab.exec(self.instance, 'sh', '-ec', 'printf known > "/workspace/samples/目标 file.txt"; dd if=/dev/zero of="/workspace/samples/big file.bin" bs=1048576 count=2')
        space = json.loads(self.capture('space', ['bash', helper, 'space', '/workspace/samples', '3', '10'])['stdout'])['data']
        search = json.loads(self.capture('search', ['bash', helper, 'search', '/workspace/samples', '目标', '2', '10'])['stdout'])['data']
        assert space['complete'] and space['topFiles'][0]['allocatedBytes'] == 2 * 1024**2
        assert len(search['items']) == 1 and search['items'][0]['name'] == '目标 file.txt'
        self.capture('storage-facts', ['bash', helper, 'storage', '/workspace/samples', '1048576'])

    def negative_cases(self, base):
        helper = base + '/kai-download-acceleration/scripts/accelerate.sh'
        value = self.capture('negative-missing-client', ['bash', helper, 'doctor', 'file'],
            env=self.env + ['KAI_KSCLI_BIN=/workspace/no-such-client'], expect=127)
        assert json.loads(value['stdout'])['category'] == 'missing-executable'
        value = self.capture('negative-unsupported-platform', ['bash', base + '/kai-software/scripts/software.sh', 'info', 'apt:bash'],
            env=self.env + ['KAI_PLATFORM=unsupported'], expect=18)
        assert json.loads(value['stdout'])['category'] == 'unsupported-platform'
        value = self.capture('negative-network-failure', ['bash', helper, 'download', 'https://127.0.0.1:9/absent',
            '/workspace/negative-network', '0' * 64], env=self.env + ['KAI_DOWNLOAD_MODE=direct'], expect=None, timeout=60)
        assert value['exitCode'] != 0 and json.loads(value['stdout'])['category'] == 'download-failed'
        lock = json.loads((ROOT / 'tests/multisystem/acceleration-lock.json').read_text())['file']
        value = self.capture('negative-content-hash', ['bash', helper, 'download', lock['url'],
            '/workspace/negative-hash', '0' * 64], expect=4)
        assert json.loads(value['stdout'])['category'] == 'integrity'
        self.lab.exec(self.instance, 'sh', '-ec', 'test ! -e /workspace/negative-network; test ! -e /workspace/negative-hash')
        assert self.lab.exec(self.instance, 'sha256sum', '/workspace/verified-file').split()[0] == lock['sha256']
        self.receipt['nativeNegativeCases'] = ['missing-client', 'unsupported-platform', 'network-failure', 'content-hash']

    def close(self):
        try:
            # Preserve partial output too: an SSH timeout must not erase diagnosis.
            partial = json.loads(self.lab.remote_python(
                'import json,sys;from pathlib import Path;p=Path(sys.argv[1]);'
                'print(json.dumps({f.name:f.read_text(errors="replace")[-2097152:] '
                'for f in p.glob("*") if f.is_file()}))', self.instance['work'] + '/work/logs'))
            (self.folder / 'native-logs.json').write_text(json.dumps(partial, ensure_ascii=False, indent=2))
            if self.target == 'istoreos' and 'systemBefore' in self.receipt:
                after = self.lab.exec(self.instance, 'sh', '-ec', 'sha256sum -c /usr/share/kai-lab/system-curl.sha256; sha256sum /etc/ssl/openssl.cnf')
                assert after == self.receipt['systemBefore']
                self.receipt['systemCurlAndTlsUnchanged'] = True
            if self.gateway:
                (self.folder / 'gateway.log').write_text(self.lab.remote('cat', self.gateway['helper']['work'] + '/work/gateway.log'))
        finally:
            try:
                if self.gateway:
                    self.lab.stop_gateway(self.gateway)
            finally:
                self.lab.cleanup(self.instance)
                self.receipt['cleanup'] = 'passed'
                self.save()

    def singles(self):
        try:
            self.setup()
            for name, execute in [('kai-tool-bootstrap', self.bootstrap), ('kai-software', self.software),
                                  ('kai-dev-environment', self.runtime), ('kai-project-dependencies', self.dependencies),
                                  ('kai-download-acceleration', self.download), ('kai-storage-files', self.storage)]:
                root = self.stage_single(name)
                execute(root)
                self.receipt['cases'].append({'id': 'BM7-' + self.target + '-' + name, 'skill': name,
                    'treeDigest': tree_digest(ROOT / 'skills' / name), 'status': 'passed', 'isolatedSkillCount': 1})
                self.save()
            self.receipt['status'] = 'passed'
        except BaseException as error:
            self.receipt.update(status='failed', error=str(error))
            raise
        finally:
            self.close()
        return self.receipt

    def specialists(self):
        """Run each iStoreOS entry alone; separate diagnostics from production gates."""
        assert self.target == 'istoreos'
        self.receipt['productionGates'] = []
        try:
            self.setup()
            boot = self.stage_single('kai-tool-bootstrap')
            url = 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64'
            remap = json.loads(self.lab.exec(self.instance, 'curl', '-fsS', '-H', 'Content-Type: application/json',
                '-d', json.dumps({'url': url}), 'http://127.0.0.1:5003/api/domainfold/remap'))
            jq = json.loads(self.capture('specialist-jq', ['bash', boot + '/scripts/tool.sh', 'ensure', 'jq'],
                env=self.env + ['JQ_DOWNLOAD_BASE=' + remap['output'].rsplit('/', 1)[0]])['stdout'])
            self.env += ['KAI_JQ_BIN=' + jq['path']]
            entries = [
                ('istoreos-app-search', 'search.sh', ['linkease', '3'], 'catalog_source'),
                ('istoreos-app-diagnostics', 'inspect.sh', ['linkease'], 'requested_app'),
                ('istoreos-backup-restore', 'check.sh', [], '## support'),
                ('istoreos-docker-acceleration-istoreenhance', 'check.sh', [], 'Registry Search'),
                ('istoreos-docker-basics', 'check.sh', [], 'Docker Space Check'),
                ('istoreos-docker-data-root-migrate', 'plan.sh', [], '## docker data_root'),
                ('istoreos-kspeeder-domainfold-fetch', 'remap_url.sh', [url], 'https://'),
                ('istoreos-logs-and-diagnostics', 'min-diag.sh', ['base'], '## Base'),
                ('istoreos-luci-recovery', 'diag.sh', [], 'skill=istoreos-luci-recovery'),
                ('istoreos-network-quality', 'inspect.sh', [], '[network]'),
                ('istoreos-source-introspect', 'collect.sh', ['dropbear'], 'target=dropbear'),
                ('istoreos-system-task-router', 'observe.sh', ['package', 'bash'], '[package]'),
                ('istoreos-systools', 'inspect.sh', ['store'], '[store]')]
            for name, script, arguments, expected in entries:
                root = self.stage_single(name)
                result = self.capture(name, ['sh', root + '/scripts/' + script, *arguments])
                assert expected in result['stdout'], (name, result['stdout'])
                if name == 'istoreos-app-search':
                    offline = self.capture('app-search-offline', ['sh', root + '/scripts/search.sh', 'linkease', '3'],
                        env=self.env + ['ISTORE_STORE_RESPONSE_FILE=/workspace/no-such-store-response'])
                    assert any(row['name'] == 'linkease' and row['catalog_source'] == 'first-party-offline'
                        for row in json.loads(offline['stdout']))
                self.receipt['cases'].append({'skill': name, 'status': 'passed', 'scope': 'native-read-only',
                    'treeDigest': tree_digest(ROOT / 'skills' / name), 'isolatedSkillCount': 1})
                self.save()
            root = self.stage_single('istoreos-run-executable')
            for code in [0, 7]:
                fixture = '#!/bin/sh\nprintf "native-run-fixture\\n"\nexit ' + str(code) + '\n'
                self.lab.exec(self.instance, 'sh', '-ec', 'cat > /workspace/owned-fixture.run', data=fixture.encode())
                result = self.capture('run-executable-' + str(code), ['sh', root + '/scripts/run.sh', '/workspace/owned-fixture.run'],
                    env=self.env + ['CONFIRM_RUN_EXEC=YES', 'CONFIRM_BACKUP_SKIPPED=YES', 'RUN_VIA_ISTORE_DOTRUN=no'], expect=code)
                assert 'native-run-fixture' in result['stdout']
            self.receipt['cases'].append({'skill': 'istoreos-run-executable', 'status': 'passed',
                'scope': 'actual-owned-executable-and-failure', 'treeDigest': tree_digest(ROOT / 'skills/istoreos-run-executable'),
                'isolatedSkillCount': 1})
            for name, script, args, message in [
                ('istoreos-service-manager', 'ensure.sh', ['dropbear'], 'need-confirmation'),
                ('istoreos-quickstart-api', 'request.sh', ['GET', '/system/status/'], 'TARGET_HTTP_HOST is required')]:
                root = self.stage_single(name)
                result = self.capture(name + '-guard', ['sh', root + '/scripts/' + script, *args], expect=2)
                assert message in result['stderr']
                self.receipt['cases'].append({'skill': name, 'status': 'passed', 'scope': 'native-precondition-rejection',
                    'treeDigest': tree_digest(ROOT / 'skills' / name), 'isolatedSkillCount': 1})
            for name, reason in [
                ('istoreos-backup-restore', 'full overlay backup and restore require a booted device'),
                ('istoreos-docker-acceleration-istoreenhance', 'production Docker daemon and registry mirror not mounted into the container'),
                ('istoreos-docker-basics', 'production Docker daemon deliberately unavailable'),
                ('istoreos-docker-data-root-migrate', 'real daemon data-root migration requires a separately authorized device journey'),
                ('istoreos-luci-recovery', 'production rpcd/uhttpd restart and core reinstall not exercised'),
                ('istoreos-network-quality', 'WAN saturation and physical LAN measurements not exercised'),
                ('istoreos-service-manager', 'procd boot and production service restart not exercised'),
                ('istoreos-quickstart-api', 'authenticated QuickStart backend unavailable in the ROM container'),
                ('istoreos-systools', 'kernel, disk power, upgrade and network mutations not exercised')]:
                self.receipt['productionGates'].append({'skill': name, 'status': 'not-verified-in-container', 'reason': reason})
            self.receipt['status'] = 'passed'
        except BaseException as error:
            self.receipt.update(status='failed', error=str(error))
            raise
        finally:
            self.close()
        return self.receipt

    def business_bundle(self, name):
        try:
            self.setup()
            first = 'kai-dev-environment' if name == 'development' else 'kai-software'
            root = self.stage_single(first)
            self.bootstrap(root + '/resources/runtime/kai-tool-bootstrap',
                tools=('mise', 'zsetup') if name == 'development' else ('zsetup',))
            self.lab.exec(self.instance, 'sh', '-ec', 'test ! -L /workspace/one; rm -rf /workspace/one')
            archive = self.folder / 'offline-bundle'
            lock = bundle_stage(name, archive)
            stage_tree(self.lab, self.instance, archive, '/workspace/bundle')
            command = ['sh', '/workspace/bundle/tools/install-business.sh', '--bundle', name,
                '--consumer', 'generic', '--target-skills', '/workspace/skills']
            self.capture('install-business-bundle', command)
            expected = {member['id'] for member in lock['members']}
            active = set(self.lab.exec(self.instance, 'sh', '-ec',
                'for p in /workspace/skills/*/SKILL.md; do basename "$(dirname "$p")"; done').splitlines())
            assert active == expected, (active, expected)
            if name == 'development':
                self.runtime('/workspace/skills/kai-dev-environment')
                self.dependencies('/workspace/skills/kai-project-dependencies')
            else:
                self.software('/workspace/skills/kai-software')
            self.download('/workspace/skills/kai-download-acceleration')
            self.capture('repeat-business-bundle', command)
            # A separately selected member survives removal of the collection.
            self.capture('select-business-member', ['sh', '/workspace/bundle/tools/install-business.sh',
                '--skill', first, '--consumer', 'generic', '--target-skills', '/workspace/skills'])
            self.capture('upgrade-business-bundle', command + ['--upgrade'])
            self.capture('remove-business-bundle', command + ['--uninstall'])
            count = self.lab.exec(self.instance, 'sh', '-ec', 'find /workspace/skills -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l')
            assert int(count) == 1
            self.receipt.update(status='passed', bundle=lock, activeMembers=sorted(expected),
                collectionLifecycle='passed', freshHome=True, freshClientCache=True, freshGatewayCache=True)
        except BaseException as error:
            self.receipt.update(status='failed', error=str(error))
            raise
        finally:
            self.close()
        return self.receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--image-locks', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--gateway', type=Path, required=True)
    parser.add_argument('--program-commit', required=True)
    parser.add_argument('--report-dir', type=Path, required=True)
    parser.add_argument('--target', choices=['ubuntu','debian','istoreos'], action='append')
    parser.add_argument('--scope', choices=['singles', 'specialists', 'bundle-development', 'bundle-software-management'], default='singles')
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
    report = {'schemaVersion': 1, 'scope': 'BM7-' + args.scope, 'status': 'running', 'targets': []}
    output = args.report_dir / 'result.json'
    try:
        for target in args.target or (['istoreos'] if args.scope == 'specialists' else ['ubuntu','debian','istoreos']):
            tasks = NativeTasks(lab, target, args.scope)
            try:
                if args.scope.startswith('bundle-'):
                    tasks.business_bundle(args.scope.removeprefix('bundle-'))
                else:
                    getattr(tasks, args.scope)()
            finally:
                report['targets'].append(tasks.receipt)
                output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
        report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=str(error))
    finally:
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({'status': report['status'], 'targets': len(report['targets']), 'report': str(output)}))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
