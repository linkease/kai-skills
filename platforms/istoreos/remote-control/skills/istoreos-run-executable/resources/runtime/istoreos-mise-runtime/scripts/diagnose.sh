#!/bin/sh
# Classify evidence; the caller keeps responsibility for the original exit code.
set -eu
log="${1:?a log file is required}"
[ -f "$log" ] || { echo 'failed: missing log file' >&2; exit 2; }
if grep -Eiq 'realpath.*(not found|No such file)|realpath:.*not found' "$log"; then
  echo 'diagnosis=pip-launcher-realpath: inspect pip executable; create and activate a project venv, then test ks-cli pip itself'
elif grep -Eiq 'no (precompiled|compatible).*python|precompiled.*(not found|unavailable)|no precompiled' "$log"; then
  echo 'diagnosis=precompiled-unavailable: check exact version, arch, libc and release artifacts; do not fall back to source compilation'
elif grep -Eiq 'no acceptable C compiler|gcc.*not found|cc:.*not found|configure: error' "$log"; then
  echo 'diagnosis=source-build: inspect compile settings and compiler evidence; retry verified precompiled selection, not an automatic compiler install'
elif grep -Eiq 'not.*virtualenv|externally.managed|VIRTUAL_ENV|venv.*activat' "$log"; then
  echo 'diagnosis=venv-not-active: verify VIRTUAL_ENV, pip path and interpreter prefix in the same shell'
elif grep -Eiq 'checksum|attestation|signature|certificate|TLS|SSL' "$log"; then
  echo 'diagnosis=integrity-or-tls: inspect time, DNS, certificate, expected checksum/signature and actual gateway; preserve verification'
elif grep -Eiq 'version.*(not found|invalid)|latest|3\.9\.9' "$log"; then
  echo 'diagnosis=version-selection: record mise/backend/version listing and sort implementation; use an explicitly verified compatible version'
elif grep -Eiq 'download|timed out|connection|resolve|404|403' "$log"; then
  echo 'diagnosis=download: check service health, capabilities, actual ports, source artifact and client/gateway logs'
else
  echo 'diagnosis=unclassified: preserve the original exit code and inspect bounded current evidence'
fi
