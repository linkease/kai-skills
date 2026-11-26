import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('operation_contract', ROOT/'tools/agent_capabilities/contract.py')
contract = importlib.util.module_from_spec(spec); spec.loader.exec_module(contract)


def observation():
    return {'schemaVersion':1,'operation':'docker.inspect','operationStatus':'succeeded',
            'targetId':'fixture-target','readOnly':True,'observedAt':'2026-11-26T00:00:00Z',
            'facts':{'dockerApiReachable':False},
            'evidence':[{'id':'docker-api','source':'docker API probe','status':'observed',
                         'observedAt':'2026-11-26T00:00:00Z','factPaths':['/facts/dockerApiReachable']}],
            'effects':{'requested':[],'completed':[],'unknown':[],'remaining':[]},
            'verification':{'status':'not_required','checks':[]},'errors':[],'truncated':False}


class ContractTests(unittest.TestCase):
    def rejected(self, value):
        with self.assertRaises(contract.ContractError):
            contract.validate_result(value, expected_target='fixture-target')

    def test_request_selects_explicit_operation_and_correct_target(self):
        value={'schemaVersion':1,'operation':'system.inspect','targetId':'fixture-target','parameters':{'sections':['os']}}
        self.assertEqual(contract.validate_request(value,'fixture-target',{'system.inspect'}),value)
        for update in [{'intent':'fix docker'}, {'targetId':'other'}, {'schemaVersion':True}, {'operation':'repair-everything'}]:
            with self.subTest(update=update), self.assertRaises(contract.ContractError):
                contract.validate_request({**value,**update},'fixture-target',{'system.inspect'})

    def test_successful_observation_can_show_unhealthy_service_without_completing_task(self):
        value=observation(); self.assertFalse(contract.validate_result(value)['facts']['dockerApiReachable'])
        for key in ['taskComplete','nextAction','requiredSkill']:
            self.rejected({**value,key:True})
        self.rejected({**value,'targetId':'control-host'})

    def test_unknown_denied_timeout_and_absent_are_distinct(self):
        for status in ['denied','timeout','unsupported','unknown']:
            with self.subTest(status=status):
                value=observation();value['facts']['dockerApiReachable']=None
                value['evidence'][0]['status']=status
                contract.validate_result(value)
                value['facts']['dockerApiReachable']=False; self.rejected(value)
        value=observation();value['evidence'][0]['status']='absent';contract.validate_result(value)

    def test_conflicting_versions_keep_sources_and_unknown_does_not_become_latest(self):
        value=observation();value['facts']={'packageVersion':'1.0','runtimeVersion':'2.0','latestVersion':None}
        value['evidence']=[{'id':key,'source':key,'status':status,'observedAt':value['observedAt'],'factPaths':['/facts/'+key]}
                           for key,status in [('packageVersion','observed'),('runtimeVersion','observed'),('latestVersion','timeout')]]
        contract.validate_result(value)
        value['facts']['latestVersion']='2.0';self.rejected(value)

    def test_receipt_cannot_hide_writes_failures_or_unverified_success(self):
        value=observation();value['effects']['completed']=[{'id':'copy','kind':'copy','target':'/etc/example'}];self.rejected(value)
        value=observation();value['readOnly']=False;value['effects']['requested']=[{'id':'copy','kind':'copy','target':'/tmp/owned-fixture'}]
        self.rejected(value)
        value['effects']['completed']=copy.deepcopy(value['effects']['requested'])
        value['verification']={'status':'passed','checks':[{'id':'read-back','status':'passed'}]}
        contract.validate_result(value)
        for status in ['partial','unknown','cancelled','failed']:
            incomplete=copy.deepcopy(value);incomplete['operationStatus']=status
            incomplete['effects']['unknown']=copy.deepcopy(value['effects']['requested'])
            incomplete['errors']=[{'code':status,'message':'Actual effects require reconciliation'}]
            contract.validate_result(incomplete)
        value['effects']['unknown']=copy.deepcopy(value['effects']['requested']);self.rejected(value)

    def test_size_utf8_json_and_evidence_integrity_are_checked(self):
        value=observation();value['facts']['text']='中文 \n " \\'
        value['evidence'][0]['factPaths'].append('/facts/text')
        self.assertEqual(contract.validate_result(json.dumps(value,ensure_ascii=False))['facts']['text'],value['facts']['text'])
        for body in [b'\xff', b'{"x":1,"x":2}', b'{"x":NaN}', b'x'*8193]:
            with self.subTest(body=body[:20]),self.assertRaises(contract.ContractError):contract.decode(body)
        self.rejected({**value,'truncated':True})
        value['evidence'][0]['factPaths']=['/facts/absent'];self.rejected(value)
        value=observation();value['evidence'].append(copy.deepcopy(value['evidence'][0]));self.rejected(value)

    def test_each_fact_requires_evidence_instead_of_an_unattributed_claim(self):
        value=observation();value['facts']['latestVersion']='9.9'
        self.rejected(value)

    def test_effect_receipt_cannot_claim_unrequested_scope(self):
        value=observation();value['readOnly']=False
        value['effects']['requested']=[{'id':'copy','kind':'copy','target':'/tmp/owned'}]
        value['effects']['completed']=[{'id':'copy','kind':'copy','target':'/etc/other'}]
        value['verification']={'status':'passed','checks':[{'id':'read-back','status':'passed'}]}
        self.rejected(value)

    def test_wire_byte_limit_and_json_depth_do_not_depend_on_pretty_printing(self):
        value=observation();value['facts']['text']=''
        value['evidence'][0]['factPaths'].append('/facts/text')
        encode=lambda:json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
        value['facts']['text']='x'*(8192-len(encode()))
        self.assertEqual(len(encode()),8192)
        contract.validate_result(encode())
        value['facts']['text']+='x';self.rejected(value)
        value=observation();nested=None
        for _ in range(40):nested=[nested]
        value['facts']['nested']=nested;self.rejected(value)
        for bad in ['2026-11-26 00:00:00+00:00','2026-11-26T00:00:00','not-a-date']:
            self.rejected({**observation(),'observedAt':bad})


if __name__=='__main__':unittest.main()
