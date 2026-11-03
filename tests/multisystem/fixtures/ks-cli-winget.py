"""External ks-cli receipt/argv fixture for the public PowerShell adapter."""
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
state_path = Path(os.environ['KAI_WINGET_FIXTURE_STATE'])
state = json.loads(state_path.read_text(encoding='utf-8-sig'))
with Path(os.environ['KAI_WINGET_FIXTURE_LOG']).open('a') as log:
    log.write(json.dumps({'operation': 'ks-cli', 'arguments': args}) + '\n')
if args[:2] != ['--json', 'winget'] or any('proxy' in arg for arg in args):
    sys.exit(2)
if state.get('failure'):
    print(json.dumps({'status': 'failed', 'InstallerErrorCode': 37,
                      'ExtendedErrorCode': {'HResult': -123}}))
    sys.exit(37)
action = args[2]
if action == 'install':
    state['installed'] = args[args.index('--version') + 1]
    state_path.write_text(json.dumps(state))
mode = state.get('clientMode')
if mode == 'malformed':
    print('not a receipt')
else:
    receipt = {'schema_version': 1, 'status': 'passed',
                      'operation': 'wrong-operation' if mode == 'wrong-operation' else
                                   'source-update' if action == 'source' else action,
                      'metadata_validation': 'store-signed-index-sha256-and-native-winget',
                      'system_proxy_changed': mode == 'changed-proxy', 'native_exit_code': 0}
    if mode == 'proxy-string': receipt['system_proxy_changed'] = 'false'
    print(json.dumps([receipt, receipt] if mode == 'array' else receipt))
