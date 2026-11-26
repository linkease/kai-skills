"""Loopback TLS verification with a temporary test certificate, never insecure."""
import argparse
import json
import socket
import ssl
import threading

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('certificate')
parser.add_argument('key')
parser.add_argument('--capath')
parser.add_argument('--system-trust-host')
args = parser.parse_args()
certificate, key = args.certificate, args.key
server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_context.load_cert_chain(certificate, key)
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen(4)
listener.settimeout(5)
address = listener.getsockname()


def serve():
    for _ in range(4 if args.capath else 3):
        try:
            connection, _ = listener.accept()
        except OSError:
            return
        with connection:
            connection.settimeout(3)
            try:
                with server_context.wrap_socket(connection, server_side=True) as tls:
                    tls.sendall(b'TLS_OK')
            except ssl.SSLError:
                # A rejected CA or hostname causes an expected client alert.
                pass


worker = threading.Thread(target=serve)
worker.start()


def connect(context, hostname):
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.check_hostname
    with socket.create_connection(address, timeout=3) as connection:
        with context.wrap_socket(connection, server_hostname=hostname) as tls:
            assert tls.version() in ('TLSv1.2', 'TLSv1.3')
            return tls.recv(6)


try:
    default = ssl.create_default_context()
    try:
        connect(default, 'localhost')
    except ssl.SSLCertVerificationError:
        untrusted_rejected = True
    else:
        raise AssertionError('untrusted certificate was accepted')
    assert connect(ssl.create_default_context(cafile=certificate), 'localhost') == b'TLS_OK'
    capath_result = None
    if args.capath:
        directory_context = ssl.create_default_context(capath=args.capath)
        before = len(directory_context.get_ca_certs())
        assert connect(directory_context, 'localhost') == b'TLS_OK'
        capath_result = {'trustedHandshake': 'passed', 'loadedBefore': before,
                         'loadedAfter': len(directory_context.get_ca_certs())}
    try:
        connect(ssl.create_default_context(cafile=certificate), 'wrong.invalid')
    except ssl.SSLCertVerificationError:
        hostname_rejected = True
    else:
        raise AssertionError('wrong hostname was accepted')
finally:
    listener.close()
    worker.join(timeout=6)
    assert not worker.is_alive(), 'TLS test worker did not join'

system_trust = {'status': 'not-requested'}
if args.system_trust_host:
    # This is an explicit acceptance probe, never a prerequisite for offline
    # SDK inspection. Use the unmodified platform trust store and default SNI.
    context = ssl.create_default_context()
    assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname
    with socket.create_connection((args.system_trust_host, 443), timeout=20) as raw:
        with context.wrap_socket(raw, server_hostname=args.system_trust_host) as tls:
            assert tls.version() in ('TLSv1.2', 'TLSv1.3')
            assert tls.getpeercert()
            system_trust = {'status': 'passed', 'host': args.system_trust_host,
                            'protocol': tls.version(), 'loadedAfter': len(context.get_ca_certs()),
                            'defaultVerifyPaths': ssl.get_default_verify_paths()._asdict()}

print(json.dumps({'untrustedRejected': untrusted_rejected,
                  'hostnameMismatchRejected': hostname_rejected,
                  'trustedHandshake': 'passed', 'capath': capath_result,
                  'systemTrust': system_trust, 'openssl': ssl.OPENSSL_VERSION}))
