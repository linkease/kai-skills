#!/usr/bin/env python3
"""Audit text actually delivered to an evaluated Agent, without grading answers.

Only model-visible tool messages establish delivery. Local observation logs,
user claims and final answers cannot supply evidence on the model's behalf.
This diagnostic never executes scenario files or changes runtime prompts.
"""
import argparse
import hashlib
import json
from pathlib import Path


def delivered_windows(result):
    """Yield source windows from supported tool result envelopes, not prose."""
    for index, message in enumerate(result.get('messages', [])):
        if (message.get('role') != 'tool' or message.get('name') not in
                {'read_evidence', 'query_capability', 'search_evidence'}):
            continue
        try:
            body = json.loads(message.get('content', ''))
        except (ValueError, TypeError):
            continue
        if not isinstance(body, dict):
            continue
        windows = list(body.get('observations', []))
        # Literal search results expose only their returned line prefix. A
        # clipped line does not establish delivery of the missing suffix.
        if message['name'] == 'search_evidence':
            windows.extend({**match, 'content': match.get('text'),
                            'hasMore': match.get('lineTruncated')}
                           for match in body.get('matches', []) if isinstance(match, dict))
        # service.inspect emits text windows as direct facts. Never treat an
        # arbitrary nested string (such as a source comment) as a new envelope.
        facts = body.get('facts', {})
        if isinstance(facts, dict):
            windows.extend(v for v in facts.values() if isinstance(v, dict))
        for window in windows:
            if not isinstance(window, dict):
                continue
            source = window.get('source', window.get('path'))
            content = window.get('content')
            offset = window.get('offset')
            if (not isinstance(source, str) or not isinstance(content, str)
                    or type(offset) is not int or offset < 0):
                continue
            yield {'messageIndex': index, 'tool': message.get('name'),
                   'source': source, 'offset': offset, 'content': content,
                   'hasMore': window.get('hasMore')}


def audit(result, documents, needles=()):
    windows = list(delivered_windows(result))
    sources = {}
    for source, text in documents.items():
        expected = text.encode('utf-8')
        spans = []
        covered = set()
        for window in windows:
            if window['source'] != source:
                continue
            content = window['content'].encode('utf-8')
            start = window['offset']
            end = start + len(content)
            matches = expected[start:end] == content
            spans.append({k: v for k, v in window.items() if k != 'content'} | {
                'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest(),
                'matchesSourceWindow': matches})
            if matches:
                covered.update(range(start, end))
        sources[source] = {'sourceBytes': len(expected), 'matchingBytesDelivered': len(covered),
                           'windows': spans}
    checks = []
    for source, needle in needles:
        # A match must occur in a single delivered window, not in a synthetic
        # concatenation across gaps or unrelated files.
        matches = []
        for window in windows:
            if window['source'] != source:
                continue
            index = window['content'].find(needle)
            if index < 0:
                continue
            prefix_bytes = len(window['content'][:index].encode('utf-8'))
            source_offset = window['offset'] + prefix_bytes
            expected = documents.get(source, '').encode('utf-8')
            actual = needle.encode('utf-8')
            if expected[source_offset:source_offset + len(actual)] == actual:
                matches.append({'messageIndex': window['messageIndex'],
                                'sourceByteOffset': source_offset})
        checks.append({'source': source, 'needle': needle, 'delivered': bool(matches),
                       'matches': matches})
    return {'schemaVersion': 1, 'card': result.get('card'), 'model': result.get('model'),
            'condition': result.get('condition'), 'sources': sources, 'checks': checks,
            'scope': 'Model-visible text delivery only; no reasoning, diagnosis or native-platform grade.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cards', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--needle', nargs=2, action='append', default=[], metavar=('SOURCE', 'TEXT'))
    args = parser.parse_args()
    result = json.loads(args.result.read_text())
    card = next(c for c in json.loads(args.cards.read_text())['cards'] if c['id'] == result['card'])
    report = audit(result, card['documents'], args.needle)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if any(not check['delivered'] for check in report['checks']):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
