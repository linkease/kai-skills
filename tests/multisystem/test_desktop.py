"""Desktop public CLI contracts; native desktop kernels remain separate gates."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import signal
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXECUTION = ROOT / 'tools/multisystem/execution.py'
PWSH = os.environ.get('KAI_DESKTOP_PWSH') or shutil.which('pwsh')
BASH32 = os.environ.get('KAI_DESKTOP_BASH32')


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kai desktop 中文 ')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def plan(self, request):
        result = subprocess.run([sys.executable, str(EXECUTION), 'plan'],
                                input=json.dumps(request), text=True, capture_output=True)
        return result, json.loads(result.stdout)

    def test_explicit_cmd_bridge_executes_via_external_executor_and_preserves_exit(self):
        request = {'argv': [r'C:\Tools 中文\npm.cmd', '--version', 'with space', ''],
                   'cwd': str(self.work), 'target': {'platform': 'windows', 'shell': 'cmd'}}
        result, plan = self.plan(request)
        self.assertEqual(result.returncode, 0, plan)
        script = base64.b64decode(plan['launcher'][-1]).decode('utf-16le')
        encoded = script.split("FromBase64String('", 1)[1].split("')", 1)[0]
        payload = json.loads(base64.b64decode(encoded))
        self.assertEqual(payload['windowsArguments'],
                         '/d /v:off /s /c ""C:\\Tools 中文\\npm.cmd" "--version" "with space" """')
        self.assertTrue(PWSH, 'PowerShell parser/executor unavailable: set KAI_DESKTOP_PWSH')
        # The real PowerShell script executes a protocol fixture for the
        # external Windows command processor, not a mocked internal planner.
        processor = self.work / 'cmd.exe'
        processor.write_text('#!' + sys.executable + '\nimport json,sys\n'
                             'print(json.dumps(sys.argv[1:]));sys.exit(37)\n')
        processor.chmod(0o700)
        run = subprocess.run([PWSH, *plan['launcher'][1:]], text=True, capture_output=True,
                             env={**os.environ, 'ComSpec': str(processor)}, timeout=15)
        self.assertEqual(run.returncode, 37, run.stderr)
        # Linux .NET argv splitting is not Windows cmd parsing. Assert the
        # process protocol here; native cmd quote behavior stays pending.
        self.assertEqual(json.loads(run.stdout)[:4], ['/d', '/v:off', '/s', '/c'])

    def test_batch_bridge_rejects_shell_expansion_and_requires_explicit_selection(self):
        for value in ['%PATH%', 'a&b', 'a"b', 'line\nbreak', 'a!b']:
            result, response = self.plan({'argv': [r'C:\tools\example.cmd', value],
                'target': {'platform': 'windows', 'shell': 'cmd'}})
            self.assertEqual(result.returncode, 2, response)
            self.assertIn('batch', response['stderr'].lower())
        result, _ = self.plan({'argv': [r'C:\tools\example.cmd'],
                              'target': {'platform': 'windows', 'shell': 'native'}})
        self.assertEqual(result.returncode, 2)

    def test_git_bash_docker_paths_use_only_a_child_conversion_override(self):
        arguments = ['run', '--rm', '-v', '/var/run/docker.sock:/var/run/docker.sock',
                     '-v', 'C:/项目 空格:/src', '--workdir', '/src', 'image:tag']
        for filename, expected in [('docker.exe', '*'), ('node.exe', 'outer-rule')]:
            program = self.work / filename
            program.write_text('#!' + sys.executable + '\nimport json,sys,os\n'
                               'print(json.dumps({"argv":sys.argv[1:],"conversion":os.getenv("MSYS2_ARG_CONV_EXCL")}))\n')
            program.chmod(0o700)
            request = {'argv': [str(program), *arguments], 'target': {
                'platform': 'windows', 'shell': 'git-bash', 'bashPath': r'C:\Git\bin\bash.exe'}}
            result, plan = self.plan(request)
            self.assertEqual(result.returncode, 0, plan)
            self.assertNotIn('MSYS2_ARG_CONV_EXCL', plan['env'])
            run = subprocess.run([shutil.which('bash'), *plan['launcher'][1:]],
                env={**os.environ, 'MSYS2_ARG_CONV_EXCL': 'outer-rule'}, text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout), {'argv': arguments, 'conversion': expected})

    def winget_environment(self):
        self.assertTrue(PWSH, 'PowerShell executor unavailable: set KAI_DESKTOP_PWSH')
        modules = self.work / 'modules'
        module = modules / 'Microsoft.WinGet.Client'
        module.mkdir(parents=True)
        shutil.copyfile(ROOT / 'tests/multisystem/fixtures/Microsoft.WinGet.Client.psm1',
                        module / 'Microsoft.WinGet.Client.psm1')
        state = self.work / 'winget-state.json'
        state.write_text(json.dumps({'installed': '', 'failure': False}))
        return {**os.environ, 'PSModulePath': str(modules),
                'KAI_WINGET_FIXTURE_STATE': str(state),
                'KAI_WINGET_FIXTURE_LOG': str(self.work / 'winget-events.jsonl')}

    def winget(self, env, action, subject, version=''):
        adapter = ROOT / 'components/system-packs/common/skills/kai-software/scripts/winget.ps1'
        result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(adapter)],
            input=json.dumps({'action': action, 'subject': subject, 'version': version}),
            text=True, capture_output=True, env=env, timeout=15)
        self.assertTrue(result.stdout.strip(), result.stderr)
        return result, json.loads(result.stdout)

    def test_winget_structured_search_exact_install_reuse_and_remove(self):
        env = self.winget_environment()
        result, rows = self.winget(env, 'search', 'Tree 中文')
        self.assertEqual(result.returncode, 0, rows)
        self.assertEqual([row['id'] for row in rows], ['winget:Example.Tree'])
        self.assertFalse(rows[0]['installed'])
        result, value = self.winget(env, 'install', 'Example.Tree', '1.0.0')
        self.assertEqual(result.returncode, 0, value)
        self.assertEqual(value['installedVersion'], '1.0.0')
        self.assertEqual(value['availableVersion'], '2.0.0')
        result, _ = self.winget(env, 'install', 'Example.Tree', '1.0.0')
        self.assertEqual(result.returncode, 0)
        marker = self.work / 'project-marker'; marker.write_text('keep')
        result, value = self.winget(env, 'remove', 'Example.Tree')
        self.assertEqual(result.returncode, 0, value)
        self.assertEqual(value['status'], 'passed')
        self.assertEqual(marker.read_text(), 'keep')
        events = [json.loads(line) for line in Path(env['KAI_WINGET_FIXTURE_LOG']).read_text(encoding='utf-8-sig').splitlines()]
        installs = [event for event in events if event['operation'] == 'install']
        self.assertEqual(len(installs), 1)
        self.assertEqual(installs[0]['arguments']['Id'], 'Example.Tree')
        self.assertEqual(installs[0]['arguments']['MatchOption'], 'Equals')
        self.assertEqual(installs[0]['arguments']['Source'], 'winget')
        self.assertEqual(installs[0]['arguments']['Version'], '1.0.0')
        self.assertNotIn('AllowHashMismatch', installs[0]['arguments'])

    def test_common_software_entry_dispatches_to_structured_windows_adapter(self):
        env = self.winget_environment()
        env.update(KAI_PLATFORM='windows', KAI_POWERSHELL_BIN=PWSH)
        helper = ROOT / 'components/system-packs/common/skills/kai-software/scripts/software.sh'
        result = subprocess.run(['bash', str(helper), 'info', 'winget:Example.Tree'],
                                env=env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['id'], 'winget:Example.Tree')

    def test_winget_conflicts_versions_and_native_failure_never_report_success(self):
        env = self.winget_environment()
        state = Path(env['KAI_WINGET_FIXTURE_STATE'])
        for mode in ['missing', 'ambiguous', 'wrong-source']:
            state.write_text(json.dumps({'installed': '', 'failure': False, 'catalogMode': mode}))
            result, value = self.winget(env, 'install', 'Example.Tree', '2.0.0')
            self.assertEqual(result.returncode, 4, value)
        state.write_text(json.dumps({'installed': '', 'failure': False}))
        result, value = self.winget(env, 'install', 'Example.Tree', '99.0.0')
        self.assertEqual((result.returncode, value['category']), (4, 'version-unavailable'))
        state.write_text(json.dumps({'installed': '', 'failure': True}))
        result, value = self.winget(env, 'install', 'Example.Tree', '2.0.0')
        self.assertEqual((result.returncode, value['status']), (11, 'failed'))
        self.assertEqual(value['nativeResult']['InstallerErrorCode'], 37)
        self.assertEqual(value['nativeResult']['ExtendedErrorCode']['HResult'], -123)
        self.assertEqual(json.loads(state.read_text())['installed'], '')
        result, value = self.winget(env, 'install', 'Example.Tree; echo bad', '2.0.0')
        self.assertEqual((result.returncode, value['category']), (2, 'usage'))
        missing_env = {**env, 'PSModulePath': str(self.work / 'absent-module')}
        result, value = self.winget(missing_env, 'info', 'Example.Tree')
        self.assertEqual((result.returncode, value['category']), (18, 'native-adapter-unavailable'))

    def test_winget_incomplete_catalog_is_unavailable_and_never_mutates(self):
        env = self.winget_environment()
        for mode in ['incomplete', 'null-versions', 'blank-versions']:
            Path(env['KAI_WINGET_FIXTURE_STATE']).write_text(json.dumps(
                {'installed': '', 'failure': False, 'catalogMode': mode}))
            for action in ['info', 'install', 'search']:
                with self.subTest(mode=mode, action=action):
                    result, value = self.winget(env, action, 'Example.Tree')
                    self.assertEqual((result.returncode, value['category']), (11, 'catalog-unavailable'))
        events = [json.loads(line) for line in Path(env['KAI_WINGET_FIXTURE_LOG']).read_text(encoding='utf-8-sig').splitlines()]
        self.assertTrue(all(row['operation'] == 'find' for row in events))

    def test_native_powershell_drive_path_is_converted_before_executable_probe(self):
        env = self.winget_environment()
        bin_dir = self.work / 'bin'; bin_dir.mkdir()
        converter = bin_dir / 'cygpath'
        converter.write_text('#!' + sys.executable + '\nimport os,sys\n'
            'value=sys.argv[-1]\nprint(os.environ["KAI_DESKTOP_PWSH"] if value.startswith("C:\\\\") else value)\n')
        converter.chmod(0o700)
        env.update(KAI_PLATFORM='windows', KAI_POWERSHELL_BIN=r'C:\Program Files\PowerShell\pwsh.exe',
                   PATH=str(bin_dir) + ':' + env['PATH'])
        helper = ROOT / 'components/system-packs/common/skills/kai-software/scripts/software.sh'
        result = subprocess.run(['bash', str(helper), 'info', 'winget:Example.Tree'],
                                env=env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_macos_system_bash_never_uses_a_foreign_apt_ownership_query(self):
        bin_dir = self.work / 'bin'; bin_dir.mkdir()
        foreign = bin_dir / 'dpkg-query'
        marker = self.work / 'foreign-manager-called'
        foreign.write_text('#!/bin/sh\nprintf called > "$KAI_FOREIGN_MARKER"\nexit 0\n')
        foreign.chmod(0o700)
        helper = ROOT / 'components/system-packs/common/skills/kai-tool-bootstrap/scripts/tool.sh'
        result = subprocess.run(['bash', str(helper), 'probe', 'bash'], text=True, capture_output=True,
            env={**os.environ, 'KAI_PLATFORM': 'macos', 'KAI_FOREIGN_MARKER': str(marker),
                 'PATH': str(bin_dir) + ':/bin:/usr/bin', 'HOME': str(self.work)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['owner'], 'apple')
        self.assertFalse(marker.exists())

    def test_bash_bootstrap_rejects_slash_separated_wsl_launcher_before_running_it(self):
        self.assertTrue(PWSH)
        directory = self.work / 'System32'; directory.mkdir()
        program = directory / 'bash.exe'; marker = self.work / 'wsl-executed'
        program.write_text('#!/bin/sh\nprintf wrong > "$KAI_WSL_MARKER"\nprintf 5.2.0\n')
        program.chmod(0o700)
        bootstrap = ROOT / 'components/system-packs/common/skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1'
        result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
            str(bootstrap), '-Action', 'Probe', '-TrustedPath', str(program)],
            env={**os.environ, 'KAI_WSL_MARKER': str(marker)}, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 18, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'unavailable')
        self.assertFalse(marker.exists())

    def test_first_bash_bootstrap_keeps_installer_output_outside_json_and_reports_failure(self):
        self.assertTrue(PWSH and BASH32, 'Set KAI_DESKTOP_PWSH and KAI_DESKTOP_BASH32')
        bootstrap=ROOT/'components/system-packs/common/skills/kai-tool-bootstrap/scripts/bootstrap-bash.ps1'
        for failure in [0,37]:
            directory=self.work/str(failure);directory.mkdir();bin_dir=directory/'bin';bin_dir.mkdir()
            program=bin_dir/'winget.exe'
            program.write_text('#!'+sys.executable+'\nimport os,pathlib,shutil,sys\n'
                'print("native installer output")\n'
                'code=int(os.environ["TEST_INSTALLER_EXIT"])\n'
                'if code: sys.exit(code)\n'
                'target=pathlib.Path(os.environ["ProgramFiles"])/"Git/bin/bash.exe"\n'
                'target.parent.mkdir(parents=True);shutil.copy2(os.environ["KAI_DESKTOP_BASH32"],target)\n')
            program.chmod(0o700)
            result=subprocess.run([PWSH,'-NoLogo','-NoProfile','-NonInteractive','-File',str(bootstrap),'-Action','Ensure'],
                env={**os.environ,'ProgramFiles':str(directory/'Program Files 中文'),'LOCALAPPDATA':str(directory/'Local'),
                     'PATH':str(bin_dir)+':'+os.environ['PATH'],'TEST_INSTALLER_EXIT':str(failure)},
                text=True,capture_output=True,timeout=15)
            self.assertEqual(result.returncode,failure,result.stdout+result.stderr)
            value=json.loads(result.stdout)
            self.assertEqual(value['status'],'failed' if failure else 'installed')
            self.assertEqual(value['exitCode'],failure)
            self.assertIn('native installer output',result.stderr)

    def test_windows_npm_uses_selected_node_and_js_entry_with_literal_arguments(self):
        bin_dir=self.work/'bin';bin_dir.mkdir();sdk=self.work/'Node SDK 中文';sdk.mkdir()
        cli=sdk/'node_modules/npm/bin/npm-cli.js';cli.parent.mkdir(parents=True);cli.write_text('// external fixture')
        calls=self.work/'node-calls.jsonl';foreign=self.work/'foreign-npm-called'
        programs={
            'mise':'case "$1" in where) printf "%s\\n" "$TEST_SDK";; exec) shift; while [ "$1" != -- ]; do shift; done; shift; exec "$@";; *) exit 29;; esac',
            'cygpath':'printf "%s\\n" "$2"',
            'npm':'touch "$TEST_FOREIGN"; exit 99',
            'ks-cli':'''case "$1" in doctor) printf '{"schema_version":1,"overall":"pass","tool":"npm"}';;
--explain) printf '{"schema_version":1,"command":["npm"],"environment":{"npm_config_registry":"https://dl-npm.linkease.net:5443/"}}';;
*) exit 98;; esac'''}
        for name,body in programs.items():
            program=bin_dir/name;program.write_text('#!/bin/sh\nset -eu\n'+body+'\n');program.chmod(0o700)
        node=sdk/'node.exe'
        node.write_text('#!'+sys.executable+'\nimport json,sys,os\n'
            'if sys.argv[2:]==["config","get","strict-ssl"]: print("true");sys.exit(0)\n'
            'with open(os.environ["TEST_NODE_CALLS"],"a") as f:f.write(json.dumps({"argv":sys.argv[1:],"registry":os.getenv("npm_config_registry"),"conversion":os.getenv("MSYS2_ARG_CONV_EXCL")})+"\\n")\n'
            'sys.exit(37)\n');node.chmod(0o700)
        project=self.work/'project';project.mkdir();(project/'package.json').write_text('{"name":"fixture"}')
        arguments=['run','literal;$(not-a-command)','',r'C:\项目\x','/literal']
        env={**os.environ,'KAI_PLATFORM':'windows','HOME':str(self.work),'PATH':str(bin_dir)+':'+os.environ['PATH'],
             'TEST_SDK':str(sdk),'TEST_FOREIGN':str(foreign),'TEST_NODE_CALLS':str(calls),'KAI_DEP_ACCELERATION':'required'}
        helper=ROOT/'components/system-packs/common/skills/kai-project-dependencies/scripts/dependencies.sh'
        result=subprocess.run(['bash',str(helper),'run','npm','22.14.0',str(project),'--',*arguments],
                              env=env,text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,37,result.stdout+result.stderr)
        observed=json.loads(calls.read_text())
        self.assertEqual(observed,{'argv':[str(cli),*arguments],'registry':'https://dl-npm.linkease.net:5443/','conversion':'*'})
        self.assertFalse(foreign.exists())

    def test_macos_both_architectures_reuse_brew_and_use_launchd(self):
        for arch,canonical in [('x86_64','x64'),('arm64','arm64')]:
            directory=self.work/arch;directory.mkdir();bin_dir=directory/'bin';bin_dir.mkdir()
            prefix=directory/'brew prefix';(prefix/'bin').mkdir(parents=True)
            mise=prefix/'bin/mise';mise.write_text('#!/bin/sh\necho "2026.8.14"\n');mise.chmod(0o700)
            log=directory/'commands.jsonl'
            programs={
                'uname':'case "$1" in -s) echo Darwin;; -m) printf "%s\\n" "$TEST_ARCH";; esac',
                'brew':'''case "$1" in --prefix) printf '%s\\n' "$TEST_PREFIX";; search) echo jq;;
info) printf '{"formulae":[{"versions":{"stable":"1.8.2"},"installed":[{"version":"1.8.2"}]}]}';; *) exit 91;; esac''',
                'log':'printf "known launchd log\\n"'}
            for name,body in programs.items():
                path=bin_dir/name;path.write_text('#!/bin/sh\nset -eu\n'+body+'\n');path.chmod(0o700)
            control=bin_dir/'launchctl';control.write_text('#!'+sys.executable+'\nimport sys,json,os\n'
                'with open(os.environ["TEST_CONTROL_LOG"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("state = running")\n');control.chmod(0o700)
            env={**os.environ,'KAI_PLATFORM':'macos','HOME':str(directory),'TEST_ARCH':arch,'TEST_PREFIX':str(prefix),
                 'TEST_CONTROL_LOG':str(log),'PATH':str(prefix/'bin')+':'+str(bin_dir)+':'+os.environ['PATH']}
            helper=ROOT/'components/system-packs/common/skills/kai-tool-bootstrap/scripts/tool.sh'
            result=subprocess.run(['bash',str(helper),'probe','mise'],env=env,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(json.loads(result.stdout)['owner'],'homebrew')
            classify=subprocess.run([sys.executable,str(EXECUTION),'classify'],input=json.dumps({
                'kernel':'Darwin','architecture':arch,'home':str(directory)}),text=True,capture_output=True)
            identity=json.loads(classify.stdout);self.assertEqual(identity['architecture'],canonical)
            self.assertEqual(identity['home'],str(directory));self.assertEqual(identity['packageManager'],'brew')
            software=ROOT/'components/system-packs/common/skills/kai-software/scripts/software.sh'
            result=subprocess.run(['bash',str(software),'search','jq'],env=env,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(json.loads(result.stdout)[0]['id'],'brew:jq')
            service=ROOT/'components/system-packs/macos/skills/macos-launchd-logs/scripts'
            result=subprocess.run(['sh',str(service/'inspect.sh'),'gui/501','com.example.agent'],env=env,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run(['sh',str(service/'apply.sh'),'gui/501','com.example.agent','kickstart'],env=env,text=True,capture_output=True)
            self.assertEqual(result.returncode,3)
            result=subprocess.run(['sh',str(service/'apply.sh'),'gui/501','com.example.agent','kickstart'],
                                  env={**env,'TARGET_CHANGE_APPROVED':'YES'},text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual([json.loads(row) for row in log.read_text().splitlines()],
                             [['print','gui/501/com.example.agent'],['kickstart','-k','gui/501/com.example.agent']])

    def test_python_scripts_venv_runs_its_real_interpreter_and_pip_module(self):
        project=self.work/'Python 项目';project.mkdir();venv=project/'.venv'
        subprocess.run([sys.executable,'-m','venv',str(venv)],check=True,capture_output=True)
        scripts=venv/'Scripts';scripts.mkdir();python=scripts/'python.exe'
        python.symlink_to(venv/'bin/python')
        bin_dir=self.work/'bin';bin_dir.mkdir()
        for name,body in {
            'mise':'case "$1" in where) printf "%s\\n" "$TEST_SDK";; exec) shift; while [ "$1" != -- ]; do shift; done; shift; exec "$@";; esac',
            'cygpath':'printf "%s\\n" "$2"'}.items():
            program=bin_dir/name;program.write_text('#!/bin/sh\nset -eu\n'+body+'\n');program.chmod(0o700)
        helper=ROOT/'components/system-packs/common/skills/kai-project-dependencies/scripts/dependencies.sh'
        result=subprocess.run(['bash',str(helper),'run','pip',sys.version.split()[0],str(project),'--','debug'],
            env={**os.environ,'KAI_PLATFORM':'windows','HOME':str(self.work),'TEST_SDK':sys.base_prefix,
                 'PATH':str(bin_dir)+':'+os.environ['PATH'],'PIP_CONFIG_FILE':os.devnull,'PIP_TRUSTED_HOST':'',
                 'PIP_DISABLE_PIP_VERSION_CHECK':'1'},text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('sys.executable: '+str(python),result.stdout)

    def test_windows_sdk_verification_launches_npm_through_selected_node(self):
        bin_dir=self.work/'bin';bin_dir.mkdir();sdk=self.work/'Node SDK';sdk.mkdir()
        cli=sdk/'node_modules/npm/bin/npm-cli.js';cli.parent.mkdir(parents=True);cli.write_text('// fixture')
        marker=self.work/'npm-cmd-executed';node_calls=self.work/'node-calls'
        programs={
            'mise':'case "$1" in where) printf "%s\\n" "$TEST_SDK";; exec) shift; while [ "$1" != -- ]; do shift; done; shift; exec "$@";; esac',
            'cygpath':'printf "%s\\n" "$2"',
            'node':'''case "$1" in *check-node.cjs) echo '{}';;
*npm-cli.js) printf '%s\\n' "$1" > "$TEST_NODE_CALLS"; echo 10.9.2;; *) exit 98;; esac''',
            'npm':'touch "$TEST_FOREIGN"; exit 99'}
        for name,body in programs.items():
            path=bin_dir/name;path.write_text('#!/bin/sh\nset -eu\n'+body+'\n');path.chmod(0o700)
        helper=ROOT/'components/system-packs/common/skills/kai-dev-environment/scripts/runtime.sh'
        result=subprocess.run(['bash',str(helper),'verify','node','22.14.0'],text=True,capture_output=True,
            env={**os.environ,'KAI_PLATFORM':'windows','PATH':str(bin_dir)+':'+os.environ['PATH'],
                 'TEST_SDK':str(sdk),'TEST_FOREIGN':str(marker),'TEST_NODE_CALLS':str(node_calls)})
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(node_calls.read_text().strip(),str(cli));self.assertFalse(marker.exists())

    def test_windows_developer_cli_converts_known_paths_and_preserves_literal_args(self):
        bin_dir=self.work/'bin';bin_dir.mkdir();sdk=self.work/'UV 中文 SDK';sdk.mkdir()
        uv=sdk/'uv.exe';mise=bin_dir/'mise.exe'
        native_mise=r'C:\Program Files\mise.exe';native_root=r'C:\Tools\uv';native_uv=native_root+r'\uv.exe'
        mapping={native_mise:str(mise),native_root:str(sdk),native_uv:str(uv)}
        converter=bin_dir/'cygpath';converter.write_text('#!'+sys.executable+'\nimport json,os,sys\n'
            'print(json.loads(os.environ["TEST_PATH_MAPPING"]).get(sys.argv[-1],sys.argv[-1]))\n');converter.chmod(0o700)
        mise.write_text('#!'+sys.executable+'\nimport os,sys,json,subprocess\n'
            'a=sys.argv[1:];mapping=json.loads(os.environ["TEST_PATH_MAPPING"])\n'
            'if a[0]=="where":print(os.environ["TEST_NATIVE_ROOT"])\n'
            'elif a[0]=="which":print(os.environ["TEST_NATIVE_UV"])\n'
            'elif a[0]=="exec":\n'
            ' a=a[a.index("--")+1:];sys.exit(subprocess.run([mapping.get(a[0],a[0]),*a[1:]]).returncode)\n'
            'else:sys.exit(98)\n');mise.chmod(0o700)
        uv.write_text('#!'+sys.executable+'\nimport json,sys,os\n'
            'if sys.argv[1:]==["--version"]:print("uv 0.8.22")\n'
            'else:print(json.dumps({"argv":sys.argv[1:],"conversion":os.getenv("MSYS2_ARG_CONV_EXCL")}))\n');uv.chmod(0o700)
        helper=ROOT/'components/system-packs/common/skills/kai-dev-environment/scripts/dev-cli.sh'
        arguments=['cache','dir','/literal',r'C:\中文 空格\path','literal;$()','']
        result=subprocess.run(['bash',str(helper),'exec','uv','0.8.22','--',*arguments],
            env={**os.environ,'KAI_PLATFORM':'windows','KAI_MISE_BIN':native_mise,'TEST_PATH_MAPPING':json.dumps(mapping),
                 'TEST_NATIVE_ROOT':native_root,'TEST_NATIVE_UV':native_uv,'MSYS2_ARG_CONV_EXCL':'outer-rule',
                 'PATH':str(bin_dir)+':'+os.environ['PATH']},text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(json.loads(result.stdout),{'argv':arguments,'conversion':'*'})

    def test_powershell_transport_sends_script_to_pinned_external_executor(self):
        self.assertTrue(PWSH)
        key=self.work/'key';subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)],check=True)
        known=self.work/'known_hosts';known.write_text('windows.example '+key.with_suffix('.pub').read_text())
        ssh=self.work/'ssh-executor';sent=self.work/'sent-script'
        ssh.write_text('#!'+sys.executable+'\nimport os,pathlib,subprocess,sys\n'
            'data=sys.stdin.buffer.read();pathlib.Path(os.environ["TEST_SENT"]).write_bytes(data)\n'
            'offset=sys.argv.index("powershell.exe")\n'
            'code=subprocess.run([os.environ["KAI_DESKTOP_PWSH"],*sys.argv[offset+1:]],input=data).returncode\n'
            'sys.exit(0 if code == 0 else 1)\n')
        ssh.chmod(0o700)
        transport=ROOT/'components/transports/ssh/skills/target-ssh-powershell-controller/scripts/target-ssh-powershell.sh'
        script="param([string]$value = 'ready')\nif ($value -ne 'ready') { throw 'param block changed' }\n[Console]::WriteLine('中文 $() literal'); exit 37\n"
        env={**os.environ,'TARGET_ID':'desktop-contract','TARGET_SSH_HOST':'windows.example','TARGET_SSH_USER':'operator',
             'TARGET_SSH_KNOWN_HOSTS':str(known),'TARGET_SSH_BIN':str(ssh),'TEST_SENT':str(sent)}
        result=subprocess.run(['sh',str(transport),'inspect'],input=script,env=env,text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,37,result.stderr);self.assertIn('中文 $() literal',result.stdout)
        wire=sent.read_text()
        payload=wire.split("$kaiPayload = '",1)[1].split("'",1)[0]
        self.assertEqual(base64.b64decode(payload).decode(),script)
        known.write_text('other.example '+key.with_suffix('.pub').read_text());sent.unlink()
        result=subprocess.run(['sh',str(transport),'inspect'],input=script,env=env,text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,4,result.stderr);self.assertFalse(sent.exists())

    def test_powershell_transport_timeout_reaps_descendants(self):
        self.assertTrue(PWSH)
        key=self.work/'key';subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)],check=True)
        known=self.work/'known_hosts';known.write_text('windows.example '+key.with_suffix('.pub').read_text())
        executor=self.work/'ssh-executor'
        executor.write_text('#!'+sys.executable+'\nimport os,subprocess,sys\n'
            'offset=sys.argv.index("powershell.exe")\n'
            'sys.exit(subprocess.run([os.environ["KAI_DESKTOP_PWSH"],*sys.argv[offset+1:]],input=sys.stdin.buffer.read()).returncode)\n')
        executor.chmod(0o700)
        marker=self.work/'escaped-child';child=self.work/'child.ps1'
        child.write_text("Start-Sleep -Seconds 5;[IO.File]::WriteAllText('"+str(marker).replace("'","''")+"','escaped')")
        encoded=base64.b64encode(("& '"+str(child).replace("'","''")+"'").encode('utf-16le')).decode()
        script="$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName='"+PWSH+"';$s.Arguments='-NoProfile -EncodedCommand "+encoded+"';$s.UseShellExecute=$false;$p=[Diagnostics.Process]::Start($s);Start-Sleep -Seconds 30"
        transport=ROOT/'components/transports/ssh/skills/target-ssh-powershell-controller/scripts/target-ssh-powershell.sh'
        process=subprocess.Popen(['sh',str(transport),'inspect'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            env={**os.environ,'TARGET_ID':'deadline-contract','TARGET_SSH_HOST':'windows.example','TARGET_SSH_USER':'operator',
                 'TARGET_SSH_KNOWN_HOSTS':str(known),'TARGET_SSH_BIN':str(executor),'TARGET_TIMEOUT_SECONDS':'2'},start_new_session=True)
        try:
            stdout,stderr=process.communicate(script.encode(),timeout=12)
            self.assertEqual(process.returncode,124,stderr.decode())
            time.sleep(5)
            self.assertFalse(marker.exists(),'timed-out remote descendant escaped')
        finally:
            try:os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            process.wait()

    def test_real_bash_32_syntax_and_common_behavior(self):
        self.assertTrue(BASH32,'Bash 3.2 unavailable: set KAI_DESKTOP_BASH32')
        version=subprocess.check_output([BASH32,'-c','printf %s "$BASH_VERSION"'],text=True)
        self.assertTrue(version.startswith('3.2.'),version)
        for path in (ROOT/'components').rglob('*.sh'):
            result=subprocess.run([BASH32,'-n',str(path)],text=True,capture_output=True)
            self.assertEqual(result.returncode,0,str(path)+result.stderr)
        helper=ROOT/'components/system-packs/common/skills/kai-tool-bootstrap/scripts/tool.sh'
        result=subprocess.run([BASH32,str(helper),'probe','bash'],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout)['tool'],'bash')

    def test_powershell_parser_executes_on_every_canonical_script(self):
        self.assertTrue(PWSH,'PowerShell parser unavailable: set KAI_DESKTOP_PWSH')
        script='''$failures=@();$count=0
foreach($path in (Get-ChildItem -LiteralPath $env:KAI_PARSE_ROOT -Filter *.ps1 -Recurse)) {
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
 $count++;foreach($error in $errors){$failures+=@{path=$path.FullName;message=$error.Message}}
}
@{count=$count;failures=$failures}|ConvertTo-Json -Depth 5 -Compress
if($failures.Count){exit 1}
'''
        encoded=base64.b64encode(script.encode('utf-16le')).decode()
        result=subprocess.run([PWSH,'-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',encoded],
            env={**os.environ,'KAI_PARSE_ROOT':str(ROOT/'components')},text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        value=json.loads(result.stdout);self.assertGreaterEqual(value['count'],6);self.assertEqual(value['failures'],[])


if __name__ == '__main__':
    unittest.main()
