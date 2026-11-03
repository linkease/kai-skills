#!/bin/sh
set -eu

escape_json() {
  LC_ALL=C awk 'BEGIN { ORS="" } { gsub(/\\/, "\\\\"); gsub(/\"/, "\\\""); gsub(/[[:cntrl:]]/, " "); if (NR > 1) printf "\\n"; printf "%s", $0 }'
}

product_name="$(sw_vers -productName 2>/dev/null | head -c 128 || true)"
product_version="$(sw_vers -productVersion 2>/dev/null | head -c 64 || true)"
build_version="$(sw_vers -buildVersion 2>/dev/null | head -c 64 || true)"
architecture="$(uname -m 2>/dev/null | head -c 64 || true)"
uptime_text="$(uptime 2>/dev/null | head -c 512 || true)"
root_disk="$(df -Pk / 2>/dev/null | tail -n 1 | head -c 512 || true)"
memory_pressure="$(vm_stat 2>/dev/null | head -n 12 | head -c 2048 || true)"
launchd_jobs="$(launchctl list 2>/dev/null | awk 'NR > 1 { count++ } END { print count + 0 }')"

printf '{"schemaVersion":1,"platform":"macos","productName":"%s","productVersion":"%s","buildVersion":"%s","architecture":"%s","uptime":"%s","rootDisk":"%s","memoryPressure":"%s","launchdJobs":%s}\n' \
  "$(printf '%s' "$product_name" | escape_json)" \
  "$(printf '%s' "$product_version" | escape_json)" \
  "$(printf '%s' "$build_version" | escape_json)" \
  "$(printf '%s' "$architecture" | escape_json)" \
  "$(printf '%s' "$uptime_text" | escape_json)" \
  "$(printf '%s' "$root_disk" | escape_json)" \
  "$(printf '%s' "$memory_pressure" | escape_json)" \
  "$launchd_jobs" | head -c 8192
