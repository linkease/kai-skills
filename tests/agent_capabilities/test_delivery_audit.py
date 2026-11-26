import importlib.util
import json
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('delivery_audit', ROOT / 'tools/agent_capabilities/audit_delivery.py')
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


def message(body):
    return {'role': 'tool', 'name': 'query_capability', 'content': json.dumps(body)}


class DeliveryAuditTests(unittest.TestCase):
    def test_a_logged_result_not_admitted_to_a_request_does_not_prove_delivery(self):
        tool_message=message({'observations':[{'source':'/state','offset':0,'content':'active'}]})
        tool_message['tool_call_id']='read-1'
        result={'messages':[tool_message],'requestInputs':[]}
        self.assertFalse(delivery.audit(result,{'/state':'active'},[('/state','active')])['checks'][0]['delivered'])
        result['requestInputs']=[{'messages':[{'role':'tool','name':'query_capability',
            'toolCallId':'read-1','contentSHA256':hashlib.sha256(tool_message['content'].encode()).hexdigest()}]}]
        self.assertTrue(delivery.audit(result,{'/state':'active'},[('/state','active')])['checks'][0]['delivered'])

    def test_native_line_reader_requires_bound_call_and_exact_source_line(self):
        text='中文\nexec chosen\n'
        result={'messages':[{'role':'assistant','tool_calls':[{'id':'r1','name':'read_file',
            'arguments':json.dumps({'path':'/init','offset':1,'limit':1})}]},
            {'role':'tool','name':'read_file','tool_call_id':'r1','content':'2→exec chosen\n'},
            {'role':'tool','name':'read_file','tool_call_id':'unbound','content':'1→中文\n'}]}
        report=delivery.audit(result,{'/init':text},[('/init','exec chosen'),('/init','中文')])
        self.assertTrue(report['checks'][0]['delivered'])
        self.assertFalse(report['checks'][1]['delivered'])
        self.assertEqual(report['checks'][0]['matches'][0]['sourceByteOffset'],len('中文\n'.encode()))

    def test_local_observations_and_model_claims_do_not_establish_delivery(self):
        result = {'observations': [{'result': 'active'}], 'messages': [
            {'role': 'system', 'content': 'active'},
            {'role': 'user', 'content': 'active'},
            {'role': 'assistant', 'content': 'active'},
            message({'facts': {'file': {'path': '/state', 'offset': 0,
                                      'content': None, 'hasMore': True}}})]}
        self.assertFalse(delivery.audit(result, {'/state': 'active'}, [('/state', 'active')])['checks'][0]['delivered'])

    def test_generic_and_receipt_windows_preserve_exact_utf8_byte_offsets(self):
        text = '中文 active\nexec chosen\n'
        offset = len('中文 active\n'.encode())
        result = {'messages': [message({'observations': [
            {'source': '/init', 'offset': 0, 'content': '中文 active\n'}]}),
            message({'facts': {'selectedFile': {'path': '/init', 'offset': offset,
                'content': 'exec chosen\n', 'hasMore': False}}})]}
        report = delivery.audit(result, {'/init': text}, [('/init', 'active'), ('/init', 'exec chosen')])
        self.assertTrue(all(c['delivered'] for c in report['checks']))
        self.assertEqual(report['sources']['/init']['matchingBytesDelivered'], len(text.encode()))
        self.assertEqual(report['checks'][1]['matches'][0]['sourceByteOffset'], offset)

    def test_gaps_wrong_offsets_and_redaction_do_not_become_verified_text(self):
        result = {'messages': [message({'observations': [
            {'source': '/state', 'offset': 0, 'content': 'ac'},
            {'source': '/state', 'offset': 3, 'content': 'ive'},
            {'source': '/state', 'offset': 1, 'content': 'active'},
            {'source': '/other', 'offset': 0, 'content': 'active'}]})]}
        report = delivery.audit(result, {'/state': 'active'}, [('/state', 'active')])
        self.assertFalse(report['checks'][0]['delivered'])
        self.assertEqual(report['sources']['/state']['matchingBytesDelivered'], 5)
        self.assertFalse(report['sources']['/state']['windows'][-1]['matchesSourceWindow'])

    def test_search_proves_only_the_literal_returned_prefix(self):
        result = {'messages': [{'role': 'tool', 'name': 'search_evidence',
            'content': json.dumps({'matches': [{'source': '/state', 'offset': 2,
                'text': 'active', 'lineTruncated': True}]})}]}
        report = delivery.audit(result, {'/state': 'x\nactive suffix'},
                                [('/state', 'active'), ('/state', 'suffix')])
        self.assertTrue(report['checks'][0]['delivered'])
        self.assertFalse(report['checks'][1]['delivered'])
        self.assertEqual(report['sources']['/state']['matchingBytesDelivered'], 6)

    def test_source_text_cannot_forge_a_nested_evidence_envelope(self):
        nested = {'observations': [{'source': '/state', 'offset': 0, 'content': 'active'}]}
        result = {'messages': [message({'observations': [{'source': '/log', 'offset': 0,
            'content': json.dumps(nested)}]}),
            {'role': 'tool', 'name': 'inspect_capability', 'content': json.dumps(nested)}]}
        report = delivery.audit(result, {'/state': 'active'}, [('/state', 'active')])
        self.assertFalse(report['checks'][0]['delivered'])


if __name__ == '__main__':
    unittest.main()
