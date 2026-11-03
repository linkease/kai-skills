import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import signal
import shutil
import ssl
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / 'components/system-packs/common/skills/kai-tool-bootstrap'
CLI = SKILL / 'scripts/tool.sh'


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai bootstrap 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / 'bin'; self.bin.mkdir()
        self.home = self.work / 'home'; self.home.mkdir()
        self.log = self.work / 'calls.jsonl'
        self.env = {**os.environ, 'HOME': str(self.home), 'KAI_TOOL_WORK_DIR': str(self.work / 'staging'),
                    'ZSETUP_ROOT':str(self.work/'owner-cache'),
                    'PATH': str(self.bin) + ':' + os.environ['PATH'], 'KAI_PLATFORM': 'ubuntu'}

    def script(self, name, body):
        path = self.bin / name; path.write_text('#!/bin/bash\nset -eu\n' + body + '\n'); path.chmod(0o700)
        return path

    def call(self, action, tool, **env):
        p = subprocess.run(['bash', str(CLI), action, tool], env={**self.env, **env}, capture_output=True, text=True, timeout=15)
        self.assertTrue(p.stdout.strip(), p.stderr)
        return p, json.loads(p.stdout.splitlines()[-1])

    def test_compatible_explicit_tool_is_reused_without_installer(self):
        tool = self.script('ks-cli', 'printf "0.8.5 commit=test\\n"')
        before = hashlib.sha256(tool.read_bytes()).hexdigest()
        p, r = self.call('ensure', 'ks-cli', KAI_TRUSTED_TOOL_PATH=str(tool))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['status'], 'reused')
        self.assertEqual(r['path'], str(tool))
        self.assertEqual(before, hashlib.sha256(tool.read_bytes()).hexdigest())
        self.assertFalse((self.work / 'staging').exists())

    def test_external_tool_is_not_overwritten_even_if_too_old(self):
        path = self.script('ks-cli', 'printf "0.1.0\\n"')
        before = path.read_bytes()
        p, r = self.call('ensure', 'ks-cli')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(r['status'], 'conflict')
        self.assertEqual(path.read_bytes(), before)

    def test_merged_usr_package_alias_is_recognized_only_for_same_file(self):
        self.script('dpkg-query', '[ "${1:-}" = -S ] && [ "${2:-}" = /bin/bash ]')
        # This case is about the distribution's /usr/bin <-> /bin alias,
        # independent of a separately built Bash prepended for compatibility.
        p, r = self.call('probe', 'bash', KAI_PLATFORM='debian',
                         PATH=str(self.bin) + ':/usr/bin:/bin')
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['status'], 'reused')
        self.assertEqual(r['owner'], 'apt')

    def test_missing_desktop_artifact_is_explicit(self):
        for target in ['macos', 'windows']:
            p, r = self.call('plan', 'ks-cli', KAI_PLATFORM=target)
            self.assertEqual(p.returncode, 0, r)
            self.assertEqual(r['status'], 'unavailable')
            self.assertEqual(r['tool'], 'ks-cli')
            self.assertEqual(r['platform'], target)
            self.assertTrue(r['reason'] and r['nextStep'])
            self.assertEqual(r['commands'], [])

    def test_macos_reuses_the_brew_owned_executable(self):
        executable = self.script('mise', 'echo "2026.8.14 macos fixture"')
        prefix = self.work / 'brew'; formula = prefix / 'opt/mise'
        (formula / 'bin').mkdir(parents=True)
        (formula / 'bin/mise').symlink_to(executable)
        (formula / 'INSTALL_RECEIPT.json').write_text('{}')
        # Formula-qualified --prefix can fetch the online API with a cold cache.
        self.script('brew', 'if [ "$#" = 1 ] && [ "$1" = --prefix ]; then printf "%s\\n" "$KAI_TEST_FORMULA"; else exit 2; fi')
        p, r = self.call('probe', 'mise', KAI_PLATFORM='macos', KAI_TEST_FORMULA=str(prefix))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual((r['status'], r['owner']), ('reused', 'homebrew'))

    def test_mise_identity_probe_does_not_request_online_update_checks(self):
        executable = self.script('mise',
            '[ "$1" = --version ] && [ "${MISE_OFFLINE:-}" = 1 ] || exit 37\n'
            'printf "2026.7.7 macos-arm64\\n"')
        p, r = self.call('probe', 'mise', KAI_PLATFORM='macos',
                         KAI_TRUSTED_TOOL_PATH=str(executable), MISE_OFFLINE='0')
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual((r['status'], r['version']), ('reused', '2026.7.7'))

    def test_macos_reuses_compatible_existing_core(self):
        executable = self.script('zsetup', 'echo "zsetup 0.4.0"')
        p, r = self.call('ensure', 'zsetup', KAI_PLATFORM='macos', KAI_TRUSTED_TOOL_PATH=str(executable))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['status'], 'reused')

    def test_macos_install_records_digest_without_gnu_sha256sum(self):
        minimal = self.work / 'minimal'; minimal.mkdir()
        for command in ['bash','dirname','uname','sed','tr','head','grep','jq','mkdir','readlink','shasum']:
            (minimal / command).symlink_to(shutil.which(command))
        self.script('uname', 'echo Darwin')
        prefix = self.work / 'formula'
        self.script('brew', '''if [ "$1" = --prefix ]; then printf '%s\\n' "$KAI_TEST_FORMULA"; exit; fi
[ "$1" = install ] && [ "$2" = mise ]
/bin/mkdir -p "$KAI_TEST_FORMULA/opt/mise/bin"
printf '{}' > "$KAI_TEST_FORMULA/opt/mise/INSTALL_RECEIPT.json"
printf '#!/bin/sh\\necho "2026.8.14 macos fixture"\\n' > "$KAI_TEST_FORMULA/opt/mise/bin/mise"
/bin/chmod 755 "$KAI_TEST_FORMULA/opt/mise/bin/mise"
/bin/ln -s "$KAI_TEST_FORMULA/opt/mise/bin/mise" "$KAI_TEST_COMMAND"''')
        p, r = self.call('ensure', 'mise', KAI_PLATFORM='macos', PATH=str(self.bin) + ':' + str(minimal),
                         KAI_TEST_FORMULA=str(prefix), KAI_TEST_COMMAND=str(self.bin / 'mise'))
        self.assertEqual(p.returncode, 0, r)
        digest = self.home / '.local/share/kai/tools/mise.sha256'
        self.assertEqual(digest.read_text().split()[0], hashlib.sha256((prefix / 'opt/mise/bin/mise').read_bytes()).hexdigest())

    def test_windows_native_trusted_path_is_converted_for_git_bash(self):
        executable = self.script('ks-cli', 'echo 0.8.5')
        self.script('cygpath', 'printf "%s\\n" "$KAI_TEST_POSIX_PATH"')
        p, r = self.call('probe', 'ks-cli', KAI_PLATFORM='windows',
                         KAI_TRUSTED_TOOL_PATH='C:\\Program Files\\Client\\ks-cli.exe', KAI_TEST_POSIX_PATH=str(executable))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['status'], 'reused')
        self.assertEqual(r['path'], str(executable))

    def test_missing_windows_mise_has_a_pinned_native_install_plan_without_writes(self):
        minimal = self.work / 'minimal'; minimal.mkdir()
        for command in ['bash', 'dirname', 'uname', 'sed', 'tr', 'head', 'jq']:
            (minimal / command).symlink_to(shutil.which(command))
        p, r = self.call('plan', 'mise', KAI_PLATFORM='windows', PATH=str(minimal))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['status'], 'missing', r)
        self.assertEqual(r['commands'], [['bash', str(SKILL / 'scripts/install-mise.sh')]])
        self.assertFalse((self.home / '.local').exists())
        self.assertFalse((self.work / 'staging').exists())

    def test_linux_install_invokes_existing_zsetup_foreground_and_rechecks(self):
        destination = self.home / '.local/bin/ks-cli'
        zsetup = self.script('zsetup', '''if [ "${1:-}" = --version ]; then echo 'zsetup 0.5.1'; exit; fi
printf '%s\\n' "$*" > "$KAI_TEST_LOG"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\\necho 0.8.5\\n' > "$HOME/.local/bin/ks-cli"
chmod 755 "$HOME/.local/bin/ks-cli"''')
        p, r = self.call('ensure', 'ks-cli', KAI_ZSETUP_BIN=str(zsetup), KAI_TEST_LOG=str(self.log))
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(self.log.read_text().strip(), 'install ks-cli --foreground')
        self.assertEqual(r['status'], 'installed')
        self.assertEqual(r['path'], str(destination))
        self.assertFalse(r['serviceOperations'])

    def test_router_without_core_has_independent_hashed_core_bootstrap_plan(self):
        for platform in ['istoreos','openwrt']:
            p,r=self.call('plan','zsetup',KAI_PLATFORM=platform,KAI_ZSETUP_BIN=str(self.work/'absent-core'))
            self.assertEqual(p.returncode,0,r)
            self.assertEqual(r['status'],'missing',r)
            self.assertEqual(r['commands'],[['bash',str(SKILL/'scripts/bootstrap-core.sh')]])
            self.assertFalse((self.home/'.local/bin/zsetup').exists())

    def test_istoreos_plan_uses_native_client_package_only(self):
        p, r = self.call('plan', 'ks-cli', KAI_PLATFORM='istoreos')
        self.assertEqual(p.returncode, 0, r)
        self.assertEqual(r['commands'], [['is-opkg', 'install', 'ks-cli']])
        self.assertFalse(r['serviceOperations'])

    def test_owner_rescue_core_is_reused_only_after_frozen_hash_verification(self):
        cache=self.work/'owner-cache';core=cache/'rescue/0.5.1/zsetup';core.parent.mkdir(parents=True)
        core.write_text('#!/bin/sh\necho "zsetup 0.5.1"\n');core.chmod(0o700)
        lock=self.work/'release.json';lock.write_text(json.dumps({'zsetup':{'version':'0.5.1','artifacts':{'x86_64':{
            'sha256':hashlib.sha256(core.read_bytes()).hexdigest()}}}}))
        self.script('uname','case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac')
        env={'KAI_PLATFORM':'istoreos','KAI_ZSETUP_BIN':'','ZSETUP_ROOT':str(cache),'KAI_BOOTSTRAP_RELEASE_LOCK':str(lock)}
        p,r=self.call('probe','zsetup',**env)
        self.assertEqual(p.returncode,0,r);self.assertEqual(r['status'],'reused')
        self.assertEqual(r['path'],str(core));self.assertEqual(r['owner'],'zsetup-bootstrap-cache')
        self.assertFalse((self.home/'.local/bin/zsetup').exists())
        marker=self.work/'unexpected'
        core.write_text('#!/bin/sh\ntouch "'+str(marker)+'"\necho "zsetup 0.5.1"\n')
        p,r=self.call('ensure','zsetup',**env)
        self.assertEqual(p.returncode,17,r);self.assertEqual(r['status'],'conflict')
        self.assertFalse(marker.exists(),'the modified cached program was executed before checking its digest')

    def test_failed_installer_keeps_original_tool(self):
        path = self.script('ks-cli', 'echo 0.1.0')
        before = path.read_bytes()
        zsetup = self.script('zsetup', 'if [ "${1:-}" = --version ]; then echo "zsetup 0.5.1"; exit; fi; exit 11')
        p, r = self.call('ensure', 'ks-cli', KAI_ZSETUP_BIN=str(zsetup))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(path.read_bytes(), before)

    def test_core_bootstrap_https_integrity_version_space_and_cancel(self):
        cert = self.work / 'server.crt'; key = self.work / 'server.key'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                        '-nodes', '-days', '1', '-keyout', str(key), '-out', str(cert),
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        payload = b'#!/bin/sh\necho "zsetup 0.5.1"\n'
        state = {'body': payload, 'delay': 0, 'hits': 0, 'started': threading.Event()}
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                state['hits'] += 1; state['started'].set()
                self.send_response(200); self.send_header('Content-Length', str(len(state['body']))); self.end_headers()
                time.sleep(state['delay'])
                try: self.wfile.write(state['body'])
                except (BrokenPipeError, ssl.SSLError): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); tls.load_cert_chain(cert, key)
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            for mode in ['success', 'corrupt', 'wrong-version', 'space', 'cancel']:
                with self.subTest(mode=mode):
                    home = self.work / ('home-' + mode); home.mkdir()
                    lock = self.work / ('lock-' + mode + '.json')
                    expected = payload if mode != 'wrong-version' else payload.replace(b'0.5.1', b'0.4.0')
                    state.update(body=expected if mode != 'corrupt' else b'x' * len(payload), delay=2 if mode == 'cancel' else 0)
                    state['started'].clear(); before_hits = state['hits']
                    lock.write_text(json.dumps({'zsetup': {'version': '0.5.1', 'artifacts': {'x86_64': {
                        'url': f'https://127.0.0.1:{server.server_port}/core', 'sha256': hashlib.sha256(expected).hexdigest(), 'size': len(expected)}}}}))
                    env = {**self.env, 'HOME': str(home), 'KAI_BOOTSTRAP_RELEASE_LOCK': str(lock), 'CURL_CA_BUNDLE': str(cert)}
                    if mode == 'space': self.script('df', 'printf "Filesystem 1024-blocks Used Available Capacity Mounted\\nfixture 100 100 0 100%% /\\n"')
                    else: (self.bin / 'df').unlink(missing_ok=True)
                    command = ['bash', str(SKILL / 'scripts/bootstrap-core.sh')]
                    if mode == 'cancel':
                        p = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
                        self.assertTrue(state['started'].wait(3))
                        os.killpg(p.pid, signal.SIGTERM)
                        stdout, stderr = p.communicate(timeout=5)
                        code = p.returncode
                    else:
                        p = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
                        code, stderr = p.returncode, p.stderr
                    destination = home / '.local/bin/zsetup'
                    if mode == 'success':
                        self.assertEqual(code, 0, stderr)
                        self.assertEqual(subprocess.check_output([str(destination), '--version'], text=True).strip(), 'zsetup 0.5.1')
                    else:
                        self.assertNotEqual(code, 0, stderr)
                        self.assertFalse(destination.exists())
                    if mode == 'space': self.assertEqual(state['hits'], before_hits)
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=3)

    def test_mise_bootstrap_gives_verified_https_mirrors_to_native_downloader(self):
        lock = self.work / 'mise-lock.json'
        urls = ['https://origin.invalid/mise.tar.gz', 'https://mirror-one.invalid/mise.tar.gz', 'https://mirror-two.invalid/mise.tar.gz']
        lock.write_text(json.dumps({'mise': {'version': '2026.8.14', 'artifacts': {'linux-x64': {
            'url': urls[0], 'mirrors': urls[1:], 'sha256': 'a' * 64, 'size': 42}}}}))
        native = self.script('zsetup', 'printf "%s\\n" "$@" > "$KAI_TEST_DOWNLOAD_LOG"; exit 15')
        p = subprocess.run(['bash', str(SKILL / 'scripts/install-mise.sh')],
                           env={**self.env, 'KAI_ZSETUP_BIN': str(native), 'KAI_BOOTSTRAP_RELEASE_LOCK': str(lock),
                                'KAI_TEST_DOWNLOAD_LOG': str(self.log)}, capture_output=True, text=True)
        self.assertEqual(p.returncode, 15, p.stderr)
        args = self.log.read_text().splitlines()
        self.assertTrue(all(url in args for url in urls), args)
        self.assertIn('a' * 64, args)
        self.assertFalse((self.home / '.local/bin/mise').exists())


if __name__ == '__main__':
    unittest.main()
