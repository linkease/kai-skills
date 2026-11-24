#!/bin/sh
set -eu

input="${1:-/dev/stdin}"
root="${ISTORE_DIAG_ROOT:-}"

value_of() {
  awk -F '\t' -v key="$1" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' "$input"
}

app="$(value_of requested_app)"
target_path="$(value_of target_path)"
case "$app" in [A-Za-z0-9][A-Za-z0-9._+-]*) ;; *) app=unknown ;; esac
package="app-meta-$app"
status_file="${ISTORE_DIAG_OPKG_STATUS_FILE:-${root}/usr/lib/opkg/status}"

package_installed=null
if [ -f "$status_file" ]; then
  if awk -v package="$package" '
    BEGIN { RS=""; FS="\n" }
    $0 ~ "(^|\\n)Package: " package "(\\n|$)" && $0 ~ "(^|\\n)Status: .* installed(\\n|$)" { found=1 }
    END { exit !found }
  ' "$status_file"; then package_installed=true; else package_installed=false; fi
fi

bool_path() { if [ -e "${root}$1" ]; then printf true; else printf false; fi; }
meta_present="$(bool_path "/usr/lib/opkg/meta/$app.json")"
autoconf_present="$(bool_path "/usr/libexec/istorea/$app.sh")"
istorec_present="$(bool_path "/usr/libexec/istorec/$app.sh")"
init_script_present="$(bool_path "/etc/init.d/$app")"
config_present="$(bool_path "/etc/config/$app")"

target_path_available=null
case "$target_path" in /*) if [ -d "${root}${target_path}" ]; then target_path_available=true; else target_path_available=false; fi ;; esac

service_state=
container_state=
if [ -n "$root" ]; then
  [ -f "$root/run/istore-diag/service-$app.state" ] && service_state="$(head -n 1 "$root/run/istore-diag/service-$app.state")"
  [ -f "$root/run/istore-diag/container-$app.state" ] && container_state="$(head -n 1 "$root/run/istore-diag/container-$app.state")"
else
  if [ -x "/etc/init.d/$app" ]; then
    service_state="$(/etc/init.d/"$app" status 2>&1 | head -n 1 || :)"
  fi
  if [ "$istorec_present" = true ] && command -v docker >/dev/null 2>&1; then
    container_state="$(docker inspect -f '{{.State.Status}}' "$app" 2>/dev/null | head -n 1 || :)"
  fi
fi

printf 'package_installed\t%s\n' "$package_installed"
printf 'meta_present\t%s\n' "$meta_present"
printf 'autoconf_present\t%s\n' "$autoconf_present"
printf 'istorec_present\t%s\n' "$istorec_present"
printf 'init_script_present\t%s\n' "$init_script_present"
printf 'config_present\t%s\n' "$config_present"
printf 'target_path_available\t%s\n' "$target_path_available"
printf 'service_state\t%s\n' "$service_state"
printf 'container_state\t%s\n' "$container_state"
