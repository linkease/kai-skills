"""Lab/controller execution boundary; not a replacement for a target Transport.

SSH targets need only their native POSIX shell. Controller Python is not an
iStoreOS package prerequisite. Public skill adapters remain in canonical packs.
"""
import argparse
import base64
import json
import ntpath
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid

CANCELLED = threading.Event()


def classify(raw):
    kernel = str(raw.get('kernel', '')).lower()
    release = {}
    for line in raw.get('osRelease', '').splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            try:
                words = shlex.split(value)
                release[key] = ' '.join(words)
            except ValueError:
                continue
    distribution = release.get('ID', 'unknown').lower()
    environment = 'native'
    if kernel.startswith(('mingw', 'msys', 'cygwin')) or (kernel == 'windows' and raw.get('msystem')):
        system, distribution, environment = 'windows', 'windows', 'git-bash'
    elif kernel == 'windows':
        system, distribution = 'windows', 'windows'
    elif kernel == 'darwin':
        system, distribution = 'macos', 'macos'
    elif kernel == 'linux':
        system = 'istoreos' if distribution == 'istoreos' else 'linux'
        if raw.get('wslDistro') or 'microsoft' in str(raw.get('kernelRelease', '')).lower():
            environment = 'wsl'
    else:
        system = 'unknown'
    arch = str(raw.get('architecture', '')).lower()
    arch = {'x86_64': 'x64', 'amd64': 'x64', 'x64': 'x64', 'aarch64': 'arm64', 'arm64': 'arm64'}.get(arch, 'unknown')
    manager = {'ubuntu': 'apt', 'debian': 'apt', 'istoreos': 'opkg', 'openwrt': 'opkg', 'windows': 'winget', 'macos': 'brew'}.get(distribution, 'unknown')
    shell = raw.get('shell') or ('bash' if environment == 'git-bash' else 'powershell' if system == 'windows' else 'sh')
    return {'schemaVersion': 1, 'platform': system, 'distribution': distribution, 'architecture': arch,
            'shell': shell, 'home': raw.get('home') or 'unknown', 'environment': environment,
            'packageManager': manager, 'commands': raw.get('commands', {})}


def local_facts():
    release = Path('/etc/os-release')
    return classify({'kernel': platform.system(), 'kernelRelease': platform.release(),
                     'architecture': platform.machine(), 'osRelease': release.read_text() if release.exists() else '',
                     'home': str(Path.home()), 'wslDistro': os.environ.get('WSL_DISTRO_NAME'),
                     'msystem': os.environ.get('MSYSTEM'),
                     'commands': {name: shutil.which(name) for name in ['bash', 'apt-get', 'opkg', 'brew', 'winget', 'mise', 'zsetup', 'ks-cli']}})


def validate(request):
    argv = request.get('argv')
    if not isinstance(argv, list) or not argv or any(not isinstance(x, str) or '\0' in x for x in argv) or not argv[0]:
        raise ValueError('argv must be a nonempty array of strings without NUL')
    env = request.get('env', {})
    if not isinstance(env, dict) or any(not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) or not isinstance(v, str) or '\0' in v for k, v in env.items()):
        raise ValueError('invalid environment increment')
    cwd = request.get('cwd')
    if cwd is not None and (not isinstance(cwd, str) or not cwd or '\0' in cwd):
        raise ValueError('invalid cwd')
    stdin = request.get('stdin', '')
    if not isinstance(stdin, str):
        raise ValueError('stdin must be a string')
    timeout = request.get('timeoutSeconds', 120)
    if isinstance(timeout, bool) or not isinstance(timeout, (float, int)) or not 0 < timeout <= 3600:
        raise ValueError('timeoutSeconds must be in (0,3600]')
    limit = request.get('outputLimitBytes', 65536)
    if isinstance(limit, bool) or not isinstance(limit, int) or not 256 <= limit <= 1024**2:
        raise ValueError('outputLimitBytes must be in [256,1048576]')


def windows_launcher(request):
    target = request.get('target', {})
    shell = target.get('shell', 'native')
    if shell == 'git-bash':
        bash = target.get('bashPath', '')
        normalized = bash.replace('\\', '/').lower()
        if not ntpath.isabs(bash) or not normalized.endswith('/bash.exe') or re.search(r'/(system32|sysnative)/bash.exe$', normalized):
            raise ValueError('an absolute Git Bash/MSYS bash.exe path is required; WSL launchers are not Bash')
        command = 'exec "$@"'
        if ntpath.basename(request['argv'][0]).lower() in ['docker', 'docker.exe']:
            # Docker's container paths and mount specifications are its own
            # protocol. Override MSYS conversion for this child alone.
            command = 'exec env MSYS2_ARG_CONV_EXCL="*" "$@"'
        return [bash, '--noprofile', '--norc', '-c', command, 'kai-argv', *request['argv']]
    if shell not in ['native', 'powershell', 'cmd']:
        raise ValueError('unsupported Windows shell; WSL must be a separate Linux target')
    payload = dict(request)
    payload['windowsArguments'] = subprocess.list2cmdline(request['argv'][1:])
    if shell == 'cmd':
        if not request['argv'][0].lower().endswith(('.cmd', '.bat')):
            raise ValueError('the explicit batch bridge accepts .cmd/.bat programs only')
        # cmd /s removes exactly the enclosing first/last quotes. Its expansion
        # language cannot represent every literal argv value; use a native
        # executable (e.g. node.exe plus npm-cli.js) for such arguments.
        if any(re.search(r'[\x00-\x1f"%!?^&|<>]', value) for value in request['argv']):
            raise ValueError('batch shell expansion characters require a native executable bridge')
        payload['windowsArguments'] = '/d /v:off /s /c "' + ' '.join('"' + value + '"' for value in request['argv']) + '"'
    encoded = base64.b64encode(json.dumps(payload, ensure_ascii=False).encode()).decode()
    script = """$ErrorActionPreference='Stop'
$data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PAYLOAD'))|ConvertFrom-Json
if ($data.cwd) { Set-Location -LiteralPath $data.cwd }
if ($data.env) { foreach ($entry in $data.env.PSObject.Properties) { [Environment]::SetEnvironmentVariable($entry.Name,[string]$entry.Value,'Process') } }
START
""".replace('PAYLOAD', encoded)
    if shell == 'powershell':
        script = script.replace('START', '& $data.argv[0] @($data.argv | Select-Object -Skip 1)\nif ($null -ne $LASTEXITCODE) {exit $LASTEXITCODE}; if (!$?) {exit 1}')
    else:
        if shell != 'cmd' and request['argv'][0].lower().endswith(('.cmd', '.bat')):
            raise ValueError('batch files require an explicit cmd bridge, not native argv execution')
        executable = "if ($env:ComSpec) {$info.FileName=$env:ComSpec} else {$info.FileName='cmd.exe'}" if shell == 'cmd' else '$info.FileName=[string]$data.argv[0]'
        script = script.replace('START', "$info=New-Object Diagnostics.ProcessStartInfo\n" + executable + "\n$info.Arguments=[string]$data.windowsArguments\n$info.UseShellExecute=$false\n$info.WorkingDirectory=(Get-Location).Path\n$p=[Diagnostics.Process]::Start($info)\n$p.WaitForExit()\nexit $p.ExitCode")
    return ['powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', base64.b64encode(script.encode('utf-16le')).decode()]


def make_plan(request):
    validate(request)
    transport = request.get('transport', {'kind': 'local'})
    kind = transport.get('kind', 'local')
    if kind == 'local':
        target = request.get('target', {})
        launcher = windows_launcher(request) if target.get('platform') == 'windows' else request['argv']
        return {'schemaVersion': 1, 'transport': kind, 'launcher': launcher,
                'cwd': request.get('cwd'), 'env': request.get('env', {}), 'exitMarker': None}
    if kind != 'ssh':
        raise ValueError('unsupported transport')
    if request.get('target', {}).get('platform') == 'windows':
        raise ValueError('use the PowerShell Target Transport for native Windows SSH')
    host, user = transport.get('host', ''), transport.get('user', '')
    if not re.fullmatch(r'[A-Za-z0-9_.:-]+', host) or host.startswith('-') or not re.fullmatch(r'[A-Za-z0-9_.-]+', user):
        raise ValueError('invalid SSH identity')
    port = transport.get('port', 22)
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError('invalid SSH port')
    known = transport.get('knownHosts', '')
    if not known or not Path(known).is_file():
        raise ValueError('pinned knownHosts file required')
    lookup = host if port == 22 else f'[{host}]:{port}'
    pin = subprocess.run(['ssh-keygen', '-F', lookup, '-f', known], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if pin.returncode:
        raise ValueError('unknown SSH host key')
    marker = 'KAI_REMOTE_' + uuid.uuid4().hex + ':'
    command = shlex.join(['env', *[f'{k}={v}' for k, v in request.get('env', {}).items()], *request['argv']])
    if request.get('cwd'):
        command = 'cd ' + shlex.quote(request['cwd']) + ' && ' + command
    script = command + '; kai_rc=$?; printf ' + shlex.quote('\n' + marker + '%s\n') + ' "$kai_rc" >&2; exit 0'
    launcher = [transport.get('sshBin', 'ssh'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                '-o', 'UserKnownHostsFile=' + known, '-o', 'ConnectTimeout=10', '-p', str(port)]
    if transport.get('identity'):
        launcher += ['-o', 'IdentitiesOnly=yes', '-i', transport['identity']]
    launcher += [user + '@' + host, shlex.join(['sh', '-c', script])]
    return {'schemaVersion': 1, 'transport': kind, 'launcher': launcher,
            'cwd': None, 'env': {}, 'exitMarker': marker}


def stop_tree(process):
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            time.sleep(0.1)
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()


def run(request):
    plan = make_plan(request)
    if request.get('target', {}).get('platform') == 'windows' and os.name != 'nt':
        raise ValueError('Windows plans cannot be executed on a Linux/macOS controller as local commands')
    env = {**os.environ, **plan['env']}
    options = {'start_new_session': True} if os.name != 'nt' else {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
    started = time.monotonic()
    result = {'schemaVersion': 1, 'exitCode': 0, 'category': 'success', 'stdout': '', 'stderr': '',
              'stdoutTruncated': False, 'stderrTruncated': False, 'facts': local_facts()}
    try:
        child = subprocess.Popen(plan['launcher'], cwd=plan['cwd'], env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, **options)
    except FileNotFoundError as error:
        result.update(exitCode=127, category='missing-executable', stderr=str(error))
        return result
    except PermissionError as error:
        result.update(exitCode=126, category='permission', stderr=str(error))
        return result
    limit = request.get('outputLimitBytes', 65536)
    streams = {'stdout': bytearray(), 'stderr': bytearray()}
    tails = {'stderr': bytearray()}

    def drain(name, stream):
        with stream:
            while True:
                chunk = stream.read(8192)
                if not chunk:
                    break
                if name == 'stderr':
                    tails[name].extend(chunk)
                    del tails[name][:-256]
                room = limit - len(streams[name])
                streams[name].extend(chunk[:room])
                if len(chunk) > room:
                    result[name + 'Truncated'] = True

    def feed():
        try:
            child.stdin.write(request.get('stdin', '').encode())
            child.stdin.close()
        except (BrokenPipeError, OSError):
            pass

    readers = [threading.Thread(target=drain, args=(name, getattr(child, name)), daemon=True) for name in streams]
    for thread in readers:
        thread.start()
    writer = threading.Thread(target=feed, daemon=True); writer.start()
    deadline = started + request.get('timeoutSeconds', 120)
    while child.poll() is None:
        if CANCELLED.is_set() or time.monotonic() >= deadline:
            result.update(exitCode=130 if CANCELLED.is_set() else 124, category='cancelled' if CANCELLED.is_set() else 'timeout')
            stop_tree(child)
            break
        try:
            child.wait(timeout=0.03)
        except subprocess.TimeoutExpired:
            continue
    for thread in [*readers, writer]:
        thread.join(timeout=1)
    for name, content in streams.items():
        result[name] = content.decode(errors='replace')
        # Decoding an incomplete UTF-8 character must not exceed the byte budget.
        result[name] = result[name].encode()[:limit].decode(errors='ignore')
    if result['category'] == 'success':
        result['exitCode'] = child.returncode
        if plan['transport'] == 'ssh':
            tail = tails['stderr'].decode(errors='replace')
            match = re.search(r'\n' + re.escape(plan['exitMarker']) + r'(\d+)\n$', tail)
            if child.returncode != 0 or not match:
                result['category'] = 'transport'
                result['exitCode'] = child.returncode or 255
            else:
                result['exitCode'] = int(match.group(1))
                result['stderr'] = re.sub(r'\n' + re.escape(plan['exitMarker']) + r'\d+\n$', '', result['stderr'])
        if result['category'] == 'success' and result['exitCode']:
            result['category'] = 'command-failed'
    result['elapsedSeconds'] = round(time.monotonic() - started, 3)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['facts', 'classify', 'plan', 'run'])
    args = parser.parse_args()
    for signum in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(signum, lambda signum, frame: CANCELLED.set())
    try:
        request = json.loads(sys.stdin.read(5*1024**2) or '{}') if args.action != 'facts' else {}
        if not isinstance(request, dict):
            raise ValueError('request must be an object')
        if args.action == 'facts':
            result = local_facts()
        elif args.action == 'classify':
            result = classify(request)
        elif args.action == 'plan':
            result = make_plan(request)
        else:
            result = run(request)
    except (ValueError, TypeError, OSError) as error:
        result = {'schemaVersion': 1, 'category': 'usage', 'exitCode': 2, 'stderr': str(error)}
    print(json.dumps(result, ensure_ascii=False))
    code = result.get('exitCode', 0)
    return code if 0 <= code <= 255 else 1


if __name__ == '__main__':
    sys.exit(main())
