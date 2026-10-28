import idna
from pathlib import Path
import sys
assert sys.prefix != sys.base_prefix
assert Path(sys.prefix).resolve() == Path(sys.argv[1]).resolve()
assert idna.__version__ == '3.10'
assert idna.encode('例子.测试') == b'xn--fsqu00a.xn--0zwm56d'
print('idna:3.10:venv-functional')
