import bz2
import ctypes
import json
import lzma
from pathlib import Path
import sqlite3
import ssl
import sys
import venv

root = Path(sys.argv[1]).resolve()
exe = Path(sys.executable).resolve()
assert root in exe.parents, (str(exe), str(root))
assert sys.version.split()[0] == sys.argv[2], sys.version
assert sqlite3.connect(':memory:').execute('select 7').fetchone()[0] == 7
assert bz2.decompress(bz2.compress(b'check')) == b'check'
assert lzma.decompress(lzma.compress(b'check')) == b'check'
context = ssl.create_default_context()
assert context.verify_mode == ssl.CERT_REQUIRED
assert context.check_hostname
assert ctypes.sizeof(ctypes.c_int) >= 2
# capath is loaded lazily. Module availability and context security settings do
# not prove trust-chain behavior; check-tls.py performs actual TLS handshakes.
print(json.dumps({'executable': str(exe), 'version': sys.version.split()[0], 'modules': 'passed',
                  'loadedCaCount': len(context.get_ca_certs()),
                  'defaultVerifyPaths': ssl.get_default_verify_paths()._asdict(),
                  'trustHandshake': 'not-tested'}))
