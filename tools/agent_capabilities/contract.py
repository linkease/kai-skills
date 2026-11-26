"""Development-side validation of capability receipts; never authorizes execution.

This module has no runtime dependency on jsonschema, Python on a Target, or an
intent router. Target adapters emit the same JSON using their native facilities.
"""
from datetime import datetime
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT/'schemas/operation-result.schema.json').read_text())
DEFAULT_LIMIT = 8192


class ContractError(ValueError):
    pass


def _require(condition, message):
    if not condition:
        raise ContractError(message)


def _date(value):
    _require(isinstance(value, str) and re.fullmatch(
        r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})', value),
        'observedAt must be an RFC3339 timestamp')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except (ValueError, AttributeError):
        raise ContractError('observedAt must be an RFC3339 timestamp') from None
    _require(parsed.tzinfo is not None, 'observedAt must include timezone')


def _shape(value, rule):
    if '$ref' in rule:
        return _shape(value, SCHEMA['$defs'][rule['$ref'].split('/')[-1]])
    if 'const' in rule:
        _require(type(value) is type(rule['const']) and value == rule['const'], 'unsupported schemaVersion')
    if 'enum' in rule:
        _require(value in rule['enum'], 'invalid enum value')
    kind = rule.get('type')
    types = {'object': dict, 'array': list, 'string': str, 'boolean': bool,
             'integer': int, 'number': (int, float), 'null': type(None)}
    if isinstance(kind, list):
        matching = [k for k in kind if type(value) in (types[k] if isinstance(types[k], tuple) else (types[k],))]
        _require(bool(matching), 'invalid union type')
        return _shape(value, {**rule, 'type': matching[0]})
    if kind in types:
        _require(type(value) in (types[kind] if isinstance(types[kind], tuple) else (types[kind],)), 'invalid type for '+kind)
    if kind in ('integer', 'number'):
        _require(value >= rule.get('minimum', -float('inf')), 'value below minimum')
        _require(value <= rule.get('maximum', float('inf')), 'value above maximum')
    if kind == 'object':
        properties = rule.get('properties', {})
        _require(set(rule.get('required', [])) <= value.keys(), 'missing required fields')
        if rule.get('additionalProperties') is False:
            _require(value.keys() <= properties.keys(), 'unknown fields are not operation semantics')
        for key, child in properties.items():
            if key in value:
                _shape(value[key], child)
    elif kind == 'array':
        _require(len(value) >= rule.get('minItems', 0), 'too few array items')
        _require(len(value) <= rule.get('maxItems', 1 << 20), 'too many array items')
        for item in value:
            _shape(item, rule.get('items', {}))
    elif kind == 'string':
        _require(len(value) >= rule.get('minLength', 0), 'empty required string')
        _require(len(value) <= rule.get('maxLength', 1 << 20), 'string too long')
        if 'pattern' in rule:
            _require(re.fullmatch(rule['pattern'], value) is not None, 'invalid operation identity')
        if rule.get('format') == 'date-time':
            _date(value)


def _unique(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, 'duplicate JSON key')
        result[key] = value
    return result


def decode(raw, limit=DEFAULT_LIMIT):
    if isinstance(raw, str):
        raw = raw.encode('utf-8')
    _require(len(raw) <= limit, 'result limit exceeded; return a bounded receipt and explicit artifacts')
    try:
        return json.loads(raw.decode('utf-8'), object_pairs_hook=_unique,
                          parse_constant=lambda value: (_ for _ in ()).throw(ContractError('non-finite JSON value')))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ContractError('invalid UTF-8 JSON') from error


def _pointer(document, pointer):
    _require(pointer.startswith('/facts/'), 'evidence must point into facts')
    value = document
    for key in pointer[1:].split('/'):
        key = key.replace('~1', '/').replace('~0', '~')
        try:
            value = value[int(key)] if isinstance(value, list) else value[key]
        except (KeyError, IndexError, ValueError, TypeError):
            raise ContractError('evidence points to a missing fact') from None
    return value


def _leaves(value, prefix='/facts'):
    if isinstance(value, dict) and value:
        for key, child in value.items():
            yield from _leaves(child, prefix+'/'+key.replace('~','~0').replace('/','~1'))
    elif isinstance(value, list) and value:
        for index, child in enumerate(value):
            yield from _leaves(child, prefix+'/'+str(index))
    else:
        yield prefix


def _bounded_json(value):
    pending = [(value, 0)]
    while pending:
        item, depth = pending.pop()
        _require(depth <= 32, 'JSON nesting limit exceeded')
        if type(item) is dict:
            _require(all(type(key) is str for key in item), 'JSON keys must be strings')
            pending.extend((child, depth+1) for child in item.values())
        elif type(item) is list:
            pending.extend((child, depth+1) for child in item)
        else:
            _require(item is None or type(item) in (str, int, float, bool), 'invalid JSON value')
            _require(type(item) is not float or math.isfinite(item), 'non-finite JSON value')


def validate_result(result, expected_target=None, limit=DEFAULT_LIMIT):
    if isinstance(result, (str, bytes)):
        result = decode(result, limit)
    _bounded_json(result)
    _require(len(json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(',',':')).encode()) <= limit,
             'result limit exceeded')
    _shape(result, SCHEMA)
    if expected_target is not None:
        _require(result['targetId'] == expected_target, 'wrong Target receipt')
    evidence = {item['id']: item for item in result['evidence']}
    _require(len(evidence) == len(result['evidence']), 'duplicate evidence identity')
    attributed = set()
    for item in evidence.values():
        for pointer in item.get('factPaths', []):
            fact = _pointer(result, pointer)
            attributed.add(pointer)
            if item['status'] in {'denied', 'timeout', 'unsupported', 'unknown'}:
                _require(fact is None, 'unknown evidence cannot establish false or a version')
    if result['facts']:
        for path in _leaves(result['facts']):
            _require(any(path == source or path.startswith(source+'/') for source in attributed),
                     'fact lacks source evidence: '+path)
    for error in result['errors']:
        _require(not error.get('evidenceId') or error['evidenceId'] in evidence, 'unknown error evidence')
    effects = result['effects']
    requested = {effect['id']: effect for effect in effects['requested']}
    _require(len(requested) == len(effects['requested']), 'duplicate requested effect')
    for group in ('completed', 'unknown', 'remaining'):
        _require(len({e['id'] for e in effects[group]}) == len(effects[group]), 'duplicate effect receipt')
        for effect in effects[group]:
            request = requested.get(effect['id'])
            _require(request is not None and all(effect.get(key) == value for key,value in request.items()),
                     'effect receipt is outside requested scope')
    if result['readOnly']:
        _require(not any(effects.values()), 'read-only receipt contains mutation effects')
    if result['operationStatus'] == 'succeeded':
        _require(not result['errors'] and not result['truncated'], 'success cannot hide errors or truncation')
        _require(not effects['unknown'] and not effects['remaining'], 'success has incomplete effects')
        if not result['readOnly']:
            _require(bool(effects['requested']), 'mutation requires an explicit effect scope')
            _require({effect['id'] for effect in effects['completed']} == set(requested),
                     'success has uncompleted requested effects')
            _require(result['verification']['status'] == 'passed' and bool(result['verification']['checks']),
                     'mutation success requires actual verification')
            _require(all(c.get('status') == 'passed' for c in result['verification']['checks']),
                     'verification checks did not all pass')
    else:
        _require(bool(result['errors']), 'incomplete operation requires an explanation')
    return result


def validate_request(request, expected_target=None, operations=None):
    _require(type(request) is dict and set(request) == {'schemaVersion', 'operation', 'targetId', 'parameters'},
             'request must select an operation, not a business workflow')
    _require(type(request['schemaVersion']) is int and request['schemaVersion'] == 1, 'unsupported schemaVersion')
    _require(isinstance(request['operation'], str) and re.fullmatch(r'[a-z][a-z0-9._-]{0,95}', request['operation']),
             'invalid operation identity')
    _require(isinstance(request['targetId'], str) and 0 < len(request['targetId']) <= 200, 'invalid targetId')
    _require(type(request['parameters']) is dict, 'parameters must be explicit')
    if expected_target is not None:
        _require(request['targetId'] == expected_target, 'wrong Target request')
    if operations is not None:
        _require(request['operation'] in operations, 'unsupported operation')
    return request
