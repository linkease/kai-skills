#!/bin/sh
# Architecture is composable discovery, not a deterministic business router.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd -P)
cd "$root"
python3 -B -m unittest discover -s tests/agent_capabilities -p test_discovery.py
