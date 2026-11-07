import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'components/system-packs/common/skills/kai-software/scripts/software.sh'


class SoftwareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai software 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name); self.bin = self.work / 'bin'; self.bin.mkdir()
        self.log = self.work / 'provider.log'; self.state = self.work / 'installed'
        self.env = {**os.environ, 'HOME': str(self.work), 'KAI_PLATFORM': 'ubuntu',
                    'KAI_SOFTWARE_CACHE': str(self.work / 'cache'), 'PATH': str(self.bin) + ':' + os.environ['PATH'],
                    'KAI_TEST_LOG': str(self.log), 'KAI_TEST_STATE': str(self.state)}
        self.script('apt-cache', '''case "$1" in
policy) printf 'tree:\\n  Installed: (none)\\n  Candidate: 1.0.0\\n' ;;
search) printf 'tree - directory tree\\ntree-extra - extra\\ntree-two - second\\ntree-three - third\\n' ;;
*) exit 2 ;;
esac''')
        self.script('dpkg-query', '''case "$1" in
-W) if [ -f "$KAI_TEST_STATE" ]; then printf 'install ok installed\\t1.0.0\\n'; fi ;;
-S) printf 'tree: %s\\n' "$2" ;;
-L) printf '/usr/bin/tree\\n' ;;
*) exit 2 ;;
esac''')
        self.script('apt-get', '''printf '%s\\n' "$*" >> "$KAI_TEST_LOG"
if [ -n "${KAI_TEST_FAILURE:-}" ]; then exit "$KAI_TEST_FAILURE"; fi
case "$1" in install) touch "$KAI_TEST_STATE" ;; remove) rm -f "$KAI_TEST_STATE" ;; update) ;; *) exit 2 ;; esac''')

    def script(self, name, body):
        path = self.bin / name; path.write_text('#!/bin/bash\nset -eu\n' + body + '\n'); path.chmod(0o700)
        return path

    def call(self, *args, **env):
        p = subprocess.run(['bash', str(CLI), *args], env={**self.env, **env}, capture_output=True, text=True, timeout=10)
        self.assertTrue(p.stdout.strip(), p.stderr)
        return p, json.loads(p.stdout)

    def windows_environment(self):
        adapter = self.bin / 'powershell.exe'
        adapter.write_text('#!' + __import__('sys').executable + '\n' + r'''
import json, os, pathlib, sys
request = json.load(sys.stdin)
script = pathlib.Path(sys.argv[-1]).name
provider = 'scoop' if script == 'scoop.ps1' else 'winget'
with open(os.environ['KAI_TEST_LOG'], 'a') as out:
    out.write(json.dumps({'provider': provider, 'request': request}) + '\n')
if request['action'] == 'search':
    print(json.dumps([{'schemaVersion': 1, 'id': provider + (':main/tree' if provider == 'scoop' else ':Example.Tree'),
        'name': 'tree', 'title': 'Tree', 'type': 'cli-tool' if provider == 'scoop' else 'desktop-app',
        'source': provider, 'manager': provider, 'platform': 'windows', 'compatible': True,
        'availableVersion': '1.0.0', 'installedVersion': '', 'installed': False,
        'entrypoint': '', 'evidenceTime': '2026-11-07T00:00:00Z', 'matchReason': 'fixture'}]))
else:
    print(json.dumps({'schemaVersion': 1, 'status': 'passed', 'operation': request['action'],
        'id': provider + ':' + request['subject'], 'source': provider, 'policy': request.get('policy')}))
''')
        adapter.chmod(0o700)
        return {'KAI_PLATFORM': 'windows', 'KAI_POWERSHELL_BIN': str(adapter),
                'KAI_KSCLI_BIN': str(self.bin / 'ks-cli.exe'),
                'KAI_ZSETUP_BIN': str(self.bin / 'zsetup.exe')}

    def test_windows_search_preserves_same_name_scoop_and_winget_candidates(self):
        p, result = self.call('search', 'tree', **self.windows_environment())
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual([row['id'] for row in result], ['scoop:main/tree', 'winget:Example.Tree'])
        self.assertEqual([row['source'] for row in result], ['scoop', 'winget'])
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([row['provider'] for row in calls], ['scoop', 'winget'])

    def test_windows_source_qualified_ids_never_cross_provider_boundaries(self):
        env = self.windows_environment()
        for subject, expected in [('scoop:main/tree', 'scoop'), ('winget:Example.Tree', 'winget')]:
            p, result = self.call('info', subject, **env)
            self.assertEqual(p.returncode, 0, result)
            self.assertEqual(result['source'], expected)
        p, result = self.call('info', 'main/tree', **env)
        self.assertEqual((p.returncode, result['category']), (2, 'usage'))
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([row['provider'] for row in calls], ['scoop', 'winget'])

    def test_windows_scoop_policy_and_qualified_refresh_are_forwarded(self):
        env = self.windows_environment()
        p, result = self.call('install', 'scoop:main/tree', '1.0.0',
                              **{**env, 'KAI_SOFTWARE_ACCELERATION': 'required'})
        self.assertEqual(p.returncode, 0, result)
        p, result = self.call('refresh', 'scoop:main', **env)
        self.assertEqual(p.returncode, 0, result)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(calls[0]['request']['policy'], 'required')
        self.assertEqual(calls[1]['request']['subject'], 'main')

    def test_query_is_bounded_source_qualified_and_does_not_refresh(self):
        p, result = self.call('search', 'directory')
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual(len(result), 3)
        self.assertTrue(all(row['id'].startswith('apt:') for row in result))
        required = {'name','type','source','manager','platform','compatible','availableVersion','installedVersion','entrypoint','evidenceTime','matchReason'}
        self.assertTrue(required.issubset(result[0]))
        self.assertFalse(self.log.exists())

    def test_exact_package_name_does_not_trigger_unrelated_choices(self):
        p, result = self.call('search', 'tree')
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual([row['id'] for row in result], ['apt:tree'])
        _, info = self.call('info', 'apt:tree')
        self.assertEqual(info['availableVersion'], '1.0.0')
        self.assertFalse(self.log.exists())

    def test_explicit_refresh_and_exact_lifecycle_preserve_project_files(self):
        project = self.work / 'project.txt'; project.write_text('keep')
        p, _ = self.call('refresh', 'apt'); self.assertEqual(p.returncode, 0)
        p, installed = self.call('install', 'apt:tree', '1.0.0')
        self.assertEqual(p.returncode, 0, installed)
        self.assertEqual(installed['installedVersion'], '1.0.0')
        p, removed = self.call('remove', 'apt:tree')
        self.assertEqual(p.returncode, 0, removed)
        self.assertFalse(self.state.exists())
        self.assertEqual(project.read_text(), 'keep')
        self.assertIn('tree=1.0.0', self.log.read_text())

    def test_unknown_version_and_injection_are_rejected_before_mutation(self):
        p, result = self.call('install', 'apt:tree', '9.9.9')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['category'], 'version-unavailable')
        p, result = self.call('install', 'apt:tree;touch nope')
        self.assertEqual(p.returncode, 2, result)
        self.assertFalse(self.log.exists())

    def test_provider_failure_preserves_exit_and_existing_state(self):
        self.state.touch()
        p, result = self.call('install', 'apt:tree', '1.0.0', KAI_TEST_FAILURE='100')
        self.assertEqual((p.returncode, result['exitCode']), (100, 100))
        self.assertTrue(self.state.exists())

    def test_zsetup_queries_need_explicit_cached_index(self):
        zsetup = self.script('zsetup', 'printf "tree\\nlinkspace\\n"')
        p, result = self.call('search', 'tree', KAI_SOFTWARE_PROVIDER='zsetup', KAI_ZSETUP_BIN=str(zsetup))
        self.assertNotEqual(p.returncode, 0)
        cache = self.work / 'cache'; cache.mkdir(); (cache / 'zsetup-config.json').write_text('{}')
        p, result = self.call('search', 'tree', KAI_SOFTWARE_PROVIDER='zsetup', KAI_ZSETUP_BIN=str(zsetup))
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual(result[0]['id'], 'zsetup:tree')
        self.assertFalse(self.log.exists())

    def test_internal_removal_requires_existing_owner_runtime(self):
        marker = self.work / 'external-data'; marker.write_text('keep')
        p, result = self.call('remove', 'zsetup:linkspace')
        self.assertEqual(p.returncode, 127, result)
        self.assertEqual(result['category'], 'missing-executable')
        self.assertEqual(marker.read_text(), 'keep')

    def test_internal_info_reads_owner_metadata_without_executing_application(self):
        zsetup = self.script('zsetup', 'printf "linkspace\\n"')
        cache = self.work / 'cache'; cache.mkdir(); (cache / 'zsetup-config.json').write_text('{}')
        prefix = self.work / '.local/lib/linkease/linkspace'
        binary = prefix / 'versions/1.0.0/bin/linkspace'; binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\necho forbidden > "$KAI_TEST_LOG"\nexit 27\n'); binary.chmod(0o700)
        (prefix / '.managed').write_text('linkspace\n')
        (prefix / 'current').symlink_to('versions/1.0.0/bin/linkspace')
        command = self.work / '.local/bin/linkspace'; command.parent.mkdir(parents=True); command.symlink_to(prefix / 'current')
        p, result = self.call('info', 'zsetup:linkspace', KAI_ZSETUP_BIN=str(zsetup))
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual(result['installedVersion'], '1.0.0')
        self.assertIsNone(result['availableVersion'])
        self.assertFalse(self.log.exists(), 'a read-only query executed a business application')

    def test_internal_info_uses_the_installers_explicit_persistent_prefix(self):
        zsetup = self.script('zsetup', 'printf "linkspace\\n"')
        cache = self.work / 'cache'; cache.mkdir(); (cache / 'zsetup-config.json').write_text('{}')
        prefix = self.work / 'persistent disk/linkspace'
        binary = prefix / 'versions/1.2.3/bin/linkspace'; binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nexit 27\n'); binary.chmod(0o700)
        (prefix / '.managed').write_text('linkspace\n')
        (prefix / 'current').symlink_to('versions/1.2.3/bin/linkspace')
        command = self.work / '.local/bin/linkspace'; command.parent.mkdir(parents=True); command.symlink_to(prefix / 'current')
        p, result = self.call('info', 'zsetup:linkspace', KAI_ZSETUP_BIN=str(zsetup), ZSETUP_INSTALL_PREFIX=str(prefix))
        self.assertEqual(p.returncode, 0, result)
        self.assertTrue(result['installed'])
        self.assertEqual(result['installedVersion'], '1.2.3')

    def test_istore_portable_linkspace_does_not_enable_linux_service_installers(self):
        zsetup=self.script('zsetup','printf "linkspace\\nks-cli\\nkspeeder\\n"')
        cache=self.work/'cache';cache.mkdir();(cache/'zsetup-config.json').write_text('{}')
        env={'KAI_PLATFORM':'istoreos','KAI_TARGET_ARCH':'x64','KAI_SOFTWARE_PROVIDER':'zsetup','KAI_ZSETUP_BIN':str(zsetup)}
        p,rows=self.call('search','linkspace',**env)
        self.assertEqual(p.returncode,0,rows);self.assertEqual([r['id'] for r in rows],['zsetup:linkspace'])
        for term in ['ks-','kspeeder']:
            p,rows=self.call('search',term,**env)
            self.assertEqual(p.returncode,0,rows);self.assertEqual(rows,[])
        p,result=self.call('info','zsetup:ks-cli',**env)
        self.assertEqual(p.returncode,18,result)
        p,result=self.call('info','zsetup:linkspace',**{**env,'KAI_TARGET_ARCH':'mips'})
        self.assertEqual(p.returncode,18,result)


if __name__ == '__main__':
    unittest.main()
