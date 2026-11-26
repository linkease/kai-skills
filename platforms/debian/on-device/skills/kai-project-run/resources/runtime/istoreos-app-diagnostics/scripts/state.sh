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
opkg_installed=null
apk_installed=null
apk_status="${ISTORE_DIAG_APK_STATUS_FILE:-${root}/lib/apk/db/installed}"
[ -f "$apk_status" ] || apk_status="${root}/usr/lib/apk/db/installed"
if [ -r "$status_file" ]; then
  if awk -v package="$package" '
    BEGIN { RS=""; FS="\n" }
    index("\n" $0 "\n", "\nPackage: " package "\n") && $0 ~ "(^|\\n)Status: .* installed(\\n|$)" { found=1 }
    END { exit !found }
  ' "$status_file"; then opkg_installed=true; else opkg_installed=false; fi
fi
if [ -r "$apk_status" ]; then
  if awk -v package="$package" '$0 == "P:" package {found=1} END {exit !found}' "$apk_status"; then apk_installed=true; else apk_installed=false; fi
fi
case "$opkg_installed:$apk_installed" in
  null:null) package_database=unavailable ;;
  null:*) package_database=apk; package_installed=$apk_installed ;;
  *:null) package_database=opkg; package_installed=$opkg_installed ;;
  *) package_database=ambiguous ;;
esac

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
# Live service/API health is not inferred or probed through an arbitrary init wrapper.
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

printf 'package_database\t%s\n' "$package_database"
printf 'opkg_package_installed\t%s\n' "$opkg_installed"
printf 'apk_package_installed\t%s\n' "$apk_installed"
