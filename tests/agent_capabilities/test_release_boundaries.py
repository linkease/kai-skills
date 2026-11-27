import json,os,signal,subprocess,time,unittest
from pathlib import Path
from test_writes import WriteFixture,ROOT,contract
class ReleaseBoundaryTests(WriteFixture,unittest.TestCase):
 def test_host_target_mismatch_has_no_observed_facts(self):
  scripts=[('common/skills/kai-system-information/scripts/inspect.sh',['--sections','os']),('common/skills/kai-system-information/scripts/observe.sh',['--source','filesystems']),('istoreos/skills/istoreos-service-manager/scripts/inspect.sh',['--service','dockerd'])]
  for name,args in scripts:
   with self.subTest(script=name):
    p=subprocess.run(['sh',str(ROOT/'components/system-packs'/name),'--target-id','different-target',*args],env=self.env,capture_output=True,text=True,timeout=10)
    value=json.loads(p.stdout)
    self.assertNotEqual(p.returncode,0)
    self.assertEqual(value['targetId'],'test-target')
    self.assertEqual(value['facts'],{})
    self.assertIn('TARGET_MISMATCH',[e['code']for e in value['errors']])
 def test_duplicate_json_keys_are_rejected_before_any_journal_or_native_call(self):
  for replacement in ['"targetId":"other","targetId":"test-target"','"targetId":"other","\\u0074argetId":"test-target"']:
   request=self.request();request.write_text(request.read_text().replace('"targetId": "test-target"',replacement))
   p,result=self.apply(request)
   self.assertNotEqual(p.returncode,0)
   self.assertEqual(result['errors'][0]['code'],'INVALID_ARGUMENT')
   self.assertEqual(list(self.state.iterdir()),[])
   self.assertFalse(self.calls.exists())
  request=self.request();request.write_text(request.read_text().replace('"action": "start"','"action":"stop","action":"start"'))
  p,result=self.apply(request);self.assertEqual(result['errors'][0]['code'],'INVALID_ARGUMENT');self.assertFalse(self.calls.exists())
 def test_unicode_escaped_unique_keys_remain_valid(self):
  request=self.request()
  request.write_text(request.read_text().replace('"targetId"','"\\u0074argetId"'))
  p,result=self.apply(request)
  self.assertEqual(p.returncode,0,result)
  self.assertEqual(result['operationStatus'],'succeeded')
 def test_cancelled_launchd_preserves_unknown_effect(self):
  marker=self.root/'native-started'
  self.fake('launchctl','''import os,sys,time
from pathlib import Path
if sys.argv[1]=='print':print('state = running')
else:Path(os.environ['START_MARKER']).touch();time.sleep(20)
''')
  script=ROOT/'components/system-packs/macos/skills/macos-launchd-logs/scripts/apply.sh'
  proc=subprocess.Popen(['sh',str(script),'system','org.example.fixture','stop','running'],env={**self.env,'TARGET_CHANGE_APPROVED':'YES','START_MARKER':str(marker)},stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
  try:
   deadline=time.monotonic()+10
   while not marker.exists():
    self.assertIsNone(proc.poll());self.assertLess(time.monotonic(),deadline);time.sleep(.01)
   os.killpg(proc.pid,signal.SIGTERM);stdout,stderr=proc.communicate(timeout=10)
   value=contract.validate_result(stdout,expected_target='test-target')
   self.assertEqual(proc.returncode,143)
   self.assertEqual(value['operationStatus'],'cancelled')
   self.assertEqual([e['id']for e in value['effects']['unknown']],['service-command'])
   self.assertFalse(value['effects']['completed'])
  finally:
   if proc.poll()is None:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
if __name__=='__main__':unittest.main()
