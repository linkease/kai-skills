#!/usr/bin/env python3
"""Prepare signed auxiliary PKI material on a trusted controller; never import roots."""
import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import socket
import ssl
import urllib.parse
import urllib.request

from cryptography import x509
from cryptography.exceptions import InvalidSignature, UnsupportedAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import AuthorityInformationAccessOID


def der(cert):
    return cert.public_bytes(serialization.Encoding.DER)


def fingerprint(cert):
    return hashlib.sha256(der(cert)).hexdigest()


def valid(cert):
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if not cert.not_valid_before <= now < cert.not_valid_after:
        raise ValueError('Certificate expired or not yet valid')


def issued(child, parent):
    try:
        valid(parent)
        child.verify_directly_issued_by(parent)
        return True
    except (ValueError, TypeError, InvalidSignature, UnsupportedAlgorithm):
        return False


class Preparation:
    def __init__(self, roots, extra_urls):
        self.roots = [x509.load_der_x509_certificate(base64.b64decode(value, validate=True))
                      for value in roots]
        self.extra_urls = extra_urls
        self.objects = {}
        self.downloads = {}
        self.sources = {}

    def fetch(self, url):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError('Only credential-free HTTP(S) PKI URLs are supported')
        if url not in self.downloads:
            request = urllib.request.Request(url, headers={'User-Agent': 'Kai-PKI/1'})
            with urllib.request.urlopen(request, timeout=20) as response:
                if urllib.parse.urlsplit(response.url).scheme not in ('http', 'https'):
                    raise ValueError('Unsupported PKI redirect')
                data = response.read(2 * 1024 * 1024 + 1)
                if len(data) > 2 * 1024 * 1024:
                    raise ValueError('PKI object exceeds 2 MiB')
                self.downloads[url] = data
        return self.downloads[url]

    def certificates(self, url):
        data = self.fetch(url)
        candidates = []
        for loader in (x509.load_der_x509_certificate, x509.load_pem_x509_certificate):
            try:
                candidates = [loader(data)]
                break
            except ValueError:
                pass
        if not candidates:
            for loader in (pkcs7.load_der_pkcs7_certificates, pkcs7.load_pem_pkcs7_certificates):
                try:
                    candidates = loader(data)
                    break
                except ValueError:
                    pass
        if not candidates or len(candidates) > 64:
            raise ValueError('No bounded certificate set in PKI response')
        for cert in candidates:
            self.objects[fingerprint(cert)] = cert
            self.sources[fingerprint(cert)] = url

    def path(self, child, seen=()):
        if len(seen) >= 8 or fingerprint(child) in seen:
            raise ValueError('Certificate path depth/cycle limit reached')
        if any(issued(child, root) for root in self.roots):
            return []
        try:
            aia = child.extensions.get_extension_for_class(x509.AuthorityInformationAccess).value
            urls = [entry.access_location.value for entry in aia
                    if entry.access_method == AuthorityInformationAccessOID.CA_ISSUERS]
        except x509.ExtensionNotFound:
            urls = []
        if not urls:
            raise ValueError('No path to an existing target root; root import is not supported')
        for url in urls[:4]:
            try:
                self.certificates(url)
            except (OSError, ValueError):
                continue
        candidates = [cert for cert in self.objects.values()
                      if cert.subject != cert.issuer and issued(child, cert)]
        candidates.sort(key=lambda cert: not any(issued(cert, root) for root in self.roots))
        for parent in candidates:
            try:
                constraints = parent.extensions.get_extension_for_class(x509.BasicConstraints).value
                if not constraints.ca:
                    continue
                return [parent, *self.path(parent, (*seen, fingerprint(child))) ]
            except (ValueError, x509.ExtensionNotFound):
                continue
        raise ValueError('No valid intermediate path to an existing target root')

    def crl(self, subject, candidates, issuers):
        try:
            points = subject.extensions.get_extension_for_class(x509.CRLDistributionPoints).value
            urls = [name.value for point in points for name in (point.full_name or ())
                    if isinstance(name, x509.UniformResourceIdentifier)]
        except x509.ExtensionNotFound:
            urls = []
        for url in [*urls[:8], *self.extra_urls]:
            try:
                crl = x509.load_der_x509_crl(self.fetch(url))
                now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
                if crl.issuer != subject.issuer or not crl.next_update or not crl.last_update <= now < crl.next_update:
                    continue
                if not any(issuer.subject == crl.issuer and crl.is_signature_valid(issuer.public_key())
                           for issuer in issuers):
                    continue
                if crl.get_revoked_certificate_by_serial_number(subject.serial_number):
                    raise RuntimeError('Certificate is revoked')
                data = crl.public_bytes(serialization.Encoding.DER)
                candidates[hashlib.sha256(data).hexdigest()] = {
                    'der': base64.b64encode(data).decode(), 'source': url,
                    'nextUpdateUtc': crl.next_update.isoformat() + 'Z'}
                return
            except (OSError, ValueError):
                continue
        raise ValueError('No valid CRL; OCSP-only issuers need an explicit published CRL URL')

    def bundle(self, hosts):
        leaves = []
        intermediates = {}
        parsed_leaves = []
        context = ssl.create_default_context()
        for host in hosts:
            if urllib.parse.urlsplit('//' + host).hostname != host or ':' in host or '/' in host:
                raise ValueError('Expected a DNS hostname')
            with socket.create_connection((host, 443), timeout=20) as connection:
                with context.wrap_socket(connection, server_hostname=host) as secured:
                    cert = x509.load_der_x509_certificate(secured.getpeercert(binary_form=True))
            valid(cert)
            parsed_leaves.append(cert)
            leaves.append({'host': host, 'der': base64.b64encode(der(cert)).decode()})
            for parent in self.path(cert):
                intermediates[fingerprint(parent)] = parent
        crls = {}
        issuers = [*intermediates.values(), *self.roots]
        for subject in [*parsed_leaves, *intermediates.values()]:
            self.crl(subject, crls, issuers)
        return {'schemaVersion': 1, 'leaves': leaves,
                'certificates': [{'der': base64.b64encode(der(cert)).decode(),
                                  'source': self.sources[key]} for key, cert in intermediates.items()],
                'crls': list(crls.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--roots', type=Path, required=True, help='Private JSON from native windows-pki.ps1 -Action Roots')
    parser.add_argument('--host', action='append', required=True)
    parser.add_argument('--crl-url', action='append', default=[], help='Explicit published CRL for an OCSP-only issuer')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise ValueError('Preserve existing bundle output')
    if not 1 <= len(args.host) <= 16 or len(args.crl_url) > 16:
        raise ValueError('Too many hosts or supplemental CRL URLs')
    roots = json.loads(args.roots.read_text())
    if roots.get('schemaVersion') != 1:
        raise ValueError('Unsupported roots snapshot')
    bundle = Preparation(roots['roots'], args.crl_url).bundle(args.host)
    encoded = json.dumps(bundle, separators=(',', ':')).encode()
    if len(encoded) > 4194304:
        raise ValueError('Bundle exceeds native 4 MiB limit')
    with args.output.open('xb') as output:
        output.write(encoded)
    print(json.dumps({'status': 'prepared', 'hosts': args.host,
                      'certificates': len(bundle['certificates']), 'crls': len(bundle['crls']),
                      'sha256': hashlib.sha256(encoded).hexdigest()}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'status': 'failed', 'category': 'pki-material-unavailable',
                          'message': str(error)}))
        raise SystemExit(11)
