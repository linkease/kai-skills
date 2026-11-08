import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
ENTRY=ROOT/'components/system-packs/common/skills/kai-project-run/scripts/project.sh'
OWNER=Path(os.environ.get('KAI_TEST_SOFTWARE_OWNER',ROOT.parent.parent/'zsetup-scripts'))/'software/task.sh'

class ProjectTask(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.base=Path(self.temp.name).resolve();self.project=self.base/'project';self.project.mkdir();self.sdk=self.base/'sdk';self.sdk.mkdir()
        (self.project/'package.json').write_text(json.dumps({'name':'sample','scripts':{'start':'node main.js'}}))
        (self.project/'package-lock.json').write_text(json.dumps({'name':'sample','lockfileVersion':3,'packages':{}}))
        (self.project/'main.js').write_text('console.log("project ready")')
        self.runtime=self.base/'runtime.sh';self.runtime.write_text('#!/bin/bash\nif [ "$1" = probe ]; then printf '{"schemaVersion":1,"status":"passed","installRoot":"%s"}\\n' "$SIM_SDK"; else exit 7; fi\n')
        self.req={'software':'project','targetId':'project-test','project':{'path':str(self.project),'runtimeVersion':'24.18.0','sourceFiles':['main.js'],'expectedOutput':'project ready','budgetBytes':33554432}}
        self.env={**os.environ,'ZSETUP_TASK_TARGET_ID':'project-test','KAI_SOFTWARE_TASK_ENTRY':str(OWNER),'KAI_PROJECT_RUNTIME_ENTRY':str(self.runtime),'SIM_SDK':str(self.sdk)}
    def call(self,op='project-plan'):
        f=self.base/'request.json';f.write_text(json.dumps(self.req));r=subprocess.run(['bash',str(ENTRY),op,str(f)],env=self.env,text=True,capture_output=True);return r,json.loads(r.stdout)
    def test_plan_binds_sources_lock_sdk_and_storage_without_writes(self):
        before=set(self.project.iterdir());r,b=self.call();self.assertEqual(r.returncode,0,r.stdout+r.stderr);p=b['details'];self.assertEqual(p['kind'],'node');self.assertEqual(p['runtime']['version'],'24.18.0');self.assertEqual(p['runtime']['installRoot'],str(self.sdk));self.assertTrue(p['storagePlan']['volumes']);self.assertEqual(set(self.project.iterdir()),before)
    def test_unrecognized_project_returns_ai_handoff_before_sdk(self):
        (self.project/'package.json').unlink();(self.project/'package-lock.json').unlink();r,b=self.call();self.assertEqual(r.returncode,20,r.stdout+r.stderr);self.assertEqual(b['reason'],'project-recipe-required');self.assertIn('manifest-detection',b['details']['attempted'])
    def test_changed_source_invalidates_reviewed_plan_before_dependencies(self):
        r,b=self.call();self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.req['plan']=b['details'];(self.project/'main.js').write_text('changed');r,b=self.call('project-apply');self.assertEqual(r.returncode,21,r.stdout+r.stderr);self.assertEqual(b['reason'],'project-plan-changed');self.assertFalse((self.project/'.kai-project').exists())
    def test_external_source_file_is_refused(self):
        outside=self.base/'outside.js';outside.write_text('foreign');(self.project/'aliased.js').symlink_to(outside);self.req['project']['sourceFiles']=['aliased.js'];r,b=self.call();self.assertEqual(r.returncode,21,r.stdout+r.stderr);self.assertEqual(b['reason'],'unsafe-project-source')
    def test_missing_native_lock_is_handoff_and_does_not_generate_one(self):
        (self.project/'package-lock.json').unlink();r,b=self.call();self.assertEqual(r.returncode,20,r.stdout+r.stderr);self.assertEqual(b['reason'],'project-lock-required');self.assertFalse((self.project/'package-lock.json').exists())
    def test_target_mismatch_does_not_probe_sdk_or_create_work_directory(self):
        self.req['targetId']='different';r,b=self.call();self.assertEqual(r.returncode,21,r.stdout+r.stderr);self.assertEqual(b['reason'],'target-mismatch');self.assertFalse((self.project/'.kai-project').exists())

if __name__=='__main__':unittest.main()
