#!/bin/sh
set -u
umask 077
kai_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$kai_here/lib/receipt.sh"
kai_target= kai_sections=os,tools kai_deadline=5 kai_engine_context=
kai_facts= kai_evidence= kai_errors= kai_evidence_index=0 kai_status=succeeded
kai_observed=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kai_tmp=
kai_cleanup() { [ -z "$kai_tmp" ] || rm -rf -- "$kai_tmp"; }
trap kai_cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP
kai_invalid() {
  if [ -z "$kai_target" ] || [ "${#kai_target}" -gt 200 ]; then kai_target=unbound; fi
  kai_status=failed
  kai_error INVALID_ARGUMENT "$1"
  kai_emit_observation
  exit 2
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-id|--sections|--deadline-seconds|--engine-context)
      [ "$#" -ge 2 ] || kai_invalid 'An option value is missing.'
      case "$1" in
        --target-id) kai_target=$2 ;;
        --sections) kai_sections=$2 ;;
        --deadline-seconds) kai_deadline=$2 ;;
        --engine-context) kai_engine_context=$2 ;;
      esac
      shift 2 ;;
    *) kai_invalid 'Unknown option; select an explicit query scope.' ;;
  esac
done
[ -n "$kai_target" ] && [ "${#kai_target}" -le 200 ] || kai_invalid 'A bound target ID is required.'
case "$kai_deadline" in ''|*[!0-9]*) kai_invalid 'Deadline must be an integer from 1 to 30 seconds.' ;; esac
[ "$kai_deadline" -ge 1 ] && [ "$kai_deadline" -le 30 ] || kai_invalid 'Deadline must be from 1 to 30 seconds.'
case ",$kai_sections," in *,,*) kai_invalid 'Empty section.' ;; esac
kai_old_ifs=$IFS; IFS=,
for kai_section in $kai_sections; do
  case "$kai_section" in os|tools|docker) : ;; *) IFS=$kai_old_ifs; kai_invalid 'Unsupported section.' ;; esac
done
IFS=$kai_old_ifs
kai_tmp=$(mktemp -d "${TMPDIR:-/tmp}/kai-system-inspect.XXXXXX") || exit 2
kai_started=$(date +%s)
kai_has_section() { case ",$kai_sections," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Bound every external CLI probe; never install a timeout helper.
kai_probe() {
  kai_probe_rc=0 kai_probe_output= kai_probe_error=
  kai_remaining=$((kai_deadline-$(date +%s)+kai_started))
  if [ "$kai_remaining" -le 0 ]; then kai_probe_rc=124; return 0; fi
  [ "$kai_remaining" -le 2 ] || kai_remaining=2
  kai_probe_started=$(date +%s)
  if command -v timeout >/dev/null 2>&1; then
    (ulimit -f 16 || exit 125; exec timeout -k 1 "$kai_remaining" "$@") >"$kai_tmp/out" 2>"$kai_tmp/err" || kai_probe_rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    (ulimit -f 16 || exit 125; exec gtimeout -k 1 "$kai_remaining" "$@") >"$kai_tmp/out" 2>"$kai_tmp/err" || kai_probe_rc=$?
  elif command -v perl >/dev/null 2>&1; then
    (ulimit -f 16 || exit 125; exec perl -MPOSIX=setsid,WNOHANG -MTime::HiRes=time,sleep -e '
      my $seconds=shift; my $pid=fork(); defined($pid) or exit 125;
      if(!$pid){setsid()>=0 or exit 125; exec @ARGV; exit 127}
      $SIG{TERM}=$SIG{INT}=sub{kill "KILL",-$pid;waitpid($pid,0);exit 143};
      my $end=time()+$seconds;
      while(1){
        if(waitpid($pid,WNOHANG)==$pid){my $status=$?;exit(($status&127)?128+($status&127):$status>>8)}
        if(time()>=$end){kill "TERM",-$pid;sleep(0.1);kill "KILL",-$pid;waitpid($pid,0);exit 124}
        sleep(0.02)
      }' "$kai_remaining" "$@") >"$kai_tmp/out" 2>"$kai_tmp/err" || kai_probe_rc=$?
  else
    kai_probe_rc=125
    return 0
  fi
  case "$kai_probe_rc" in
    137|143) [ "$(( $(date +%s)-kai_probe_started ))" -lt "$kai_remaining" ] || kai_probe_rc=124 ;;
  esac
  if [ "$(wc -c < "$kai_tmp/out")" -gt 4096 ] || [ "$(wc -c < "$kai_tmp/err")" -gt 4096 ]; then
    kai_probe_rc=126
    return 0
  fi
  kai_probe_output=$(head -c 4096 "$kai_tmp/out")
  kai_probe_error=$(head -c 4096 "$kai_tmp/err")
}

kai_probe_unknown() {
  case "$kai_probe_rc:$kai_probe_error" in
    124:*|142:*) kai_fact "$1" null "$2" timeout; kai_error PROBE_TIMEOUT 'The selected probe reached its deadline.' ;;
    125:*) kai_fact "$1" null "$2" unsupported; kai_error BOUNDED_EXECUTION_UNAVAILABLE 'No existing bounded execution facility is available; nothing was installed or probed.' ;;
    126:*) kai_fact "$1" null "$2" unknown; kai_error PROBE_OUTPUT_LIMIT 'The external response exceeded the probe byte limit; no truncated value was accepted.' ;;
    *[Pp]ermission*[Dd]enied*|*access*denied*) kai_fact "$1" null "$2" denied; kai_error PROBE_ACCESS_DENIED 'The current identity could not read the selected fact.' ;;
    *) kai_fact "$1" null "$2" unknown; kai_error "$3" 'The selected fact could not be established.' ;;
  esac
}

kai_read_os_key() {
  if command -v awk >/dev/null 2>&1; then
    awk -v key="$1" 'index($0,key"=")==1 {v=substr($0,length(key)+2); if(v ~ /^".*"$/ || v ~ /^\047.*\047$/) v=substr(v,2,length(v)-2); print v; exit}' "$2" 2>/dev/null
    return
  fi
  while IFS= read -r kai_os_line || [ -n "$kai_os_line" ]; do
    case "$kai_os_line" in "$1="*)
      kai_os_value=${kai_os_line#*=}
      case "$kai_os_value" in
        \"*\") kai_os_value=${kai_os_value#\"}; kai_os_value=${kai_os_value%\"} ;;
        \'*\') kai_os_value=${kai_os_value#\'}; kai_os_value=${kai_os_value%\'} ;;
      esac
      printf '%s\n' "$kai_os_value"
      return
    esac
  done < "$2"
}

kai_uname=$(uname -s 2>/dev/null || :)
if kai_has_section os; then
  case "$kai_uname" in
    Linux)
      if [ -r /etc/os-release ]; then
        kai_id=$(kai_read_os_key ID /etc/os-release)
        kai_version=$(kai_read_os_key VERSION_ID /etc/os-release)
        kai_name=$(kai_read_os_key PRETTY_NAME /etc/os-release)
        kai_os_source=/etc/os-release
      elif [ -r /etc/openwrt_release ]; then
        kai_id=$(kai_read_os_key DISTRIB_ID /etc/openwrt_release)
        kai_version=$(kai_read_os_key DISTRIB_RELEASE /etc/openwrt_release)
        kai_name=$(kai_read_os_key DISTRIB_DESCRIPTION /etc/openwrt_release)
        kai_os_source=/etc/openwrt_release
      else
        kai_id= kai_version= kai_name= kai_os_source='uname; distribution files unavailable'
      fi
      kai_id_json=null kai_version_json=null kai_name_json=null
      [ -z "$kai_id" ] || kai_id_json=$(kai_json_string "$kai_id")
      [ -z "$kai_version" ] || kai_version_json=$(kai_json_string "$kai_version")
      [ -z "$kai_name" ] || kai_name_json=$(kai_json_string "$kai_name")
      [ -n "$kai_id" ] && [ -n "$kai_version" ] || kai_error OS_IDENTITY_PARTIAL 'Distribution identity or version could not be read; no package-manager inference was made.'
      kai_fact os "{\"family\":\"linux\",\"distribution\":$kai_id_json,\"version\":$kai_version_json,\"name\":$kai_name_json}" "$kai_os_source" observed
      kai_init=$(cat /proc/1/comm 2>/dev/null || :)
      kai_fact initProcess "$(kai_json_string "$kai_init")" /proc/1/comm observed
      case "$kai_init" in systemd|procd) kai_fact serviceManager "$(kai_json_string "$kai_init")" /proc/1/comm observed ;; *) kai_fact serviceManager null /proc/1/comm unknown ;; esac
      kai_markers=
      [ ! -e /.dockerenv ] || kai_markers='"/.dockerenv"'
      if [ -e /run/.containerenv ]; then [ -z "$kai_markers" ] || kai_markers="$kai_markers,"; kai_markers="$kai_markers\"/run/.containerenv\""; fi
      kai_release=$(uname -r 2>/dev/null || :)
      case "$kai_release" in *[Mm]icrosoft*|*WSL*) kai_wsl=true ;; *) kai_wsl=false ;; esac
      kai_fact environment "{\"containerMarkers\":[$kai_markers],\"wslKernelMarker\":$kai_wsl,\"hostDistribution\":null}" 'target marker files and uname; host distribution not probed' observed
      ;;
    Darwin)
      kai_probe sw_vers -productVersion
      if [ "$kai_probe_rc" -eq 0 ]; then kai_version_json=$(kai_json_string "$kai_probe_output"); else kai_version_json=null; kai_error OS_VERSION_UNAVAILABLE 'The native macOS version probe did not complete.'; fi
      kai_fact os "{\"family\":\"darwin\",\"distribution\":\"macos\",\"version\":$kai_version_json}" sw_vers observed
      kai_probe ps -p 1 -o comm=
      case "$kai_probe_rc:$kai_probe_output" in
        0:*/launchd|0:launchd) kai_fact serviceManager '"launchd"' 'native PID 1 process query' observed ;;
        *) kai_fact serviceManager null 'native PID 1 process query' unknown ;;
      esac
      ;;
    *)
      kai_fact os null uname unsupported
      kai_error UNSUPPORTED_PLATFORM 'Use the native Windows PowerShell entry for Windows; this Unix environment is unsupported.'
      ;;
  esac
  kai_fact architecture "$(kai_json_string "$(uname -m 2>/dev/null || :)")" 'uname -m' observed
  kai_fact kernel "{\"name\":$(kai_json_string "$kai_uname"),\"release\":$(kai_json_string "$(uname -r 2>/dev/null || :)") ,\"scope\":\"target-execution-environment\"}" uname observed
fi

kai_program_record() {
  kai_program_name=$1
  kai_program_path=$(command -v "$kai_program_name" 2>/dev/null || :)
  if [ -z "$kai_program_path" ] && [ "$kai_program_name" = brew ]; then
    for kai_brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$kai_brew" ]; then kai_program_path=$kai_brew; break; fi
    done
  fi
  [ -n "$kai_program_path" ] || return 1
  kai_program_type=application
  case "$kai_program_path" in /*) [ ! -L "$kai_program_path" ] || kai_program_type=symlink ;; *) kai_program_type=shell-command ;; esac
  if [ "$kai_program_type" = application ] && [ -f "$kai_program_path" ]; then
    [ "$(dd if="$kai_program_path" bs=2 count=1 2>/dev/null)" != '#!' ] || kai_program_type=script
  fi
  printf '{"name":%s,"path":%s,"commandType":%s}' "$(kai_json_string "$kai_program_name")" "$(kai_json_string "$kai_program_path")" "$(kai_json_string "$kai_program_type")"
}

if kai_has_section tools; then
  kai_programs=
  for kai_program in opkg is-opkg apk apt apt-get yum dnf brew winget scoop choco; do
    kai_record=$(kai_program_record "$kai_program") || continue
    [ -z "$kai_programs" ] || kai_programs="$kai_programs,"
    kai_programs="$kai_programs$kai_record"
  done
  kai_fact packageManagers "[$kai_programs]" 'command lookup and fixed Homebrew executable locations; presence does not establish database access or install privileges' observed
  kai_downloads=
  for kai_program in wget curl; do
    kai_record=$(kai_program_record "$kai_program") || continue
    [ -z "$kai_downloads" ] || kai_downloads="$kai_downloads,"
    kai_downloads="$kai_downloads$kai_record"
  done
  kai_fact downloadTools "[$kai_downloads]" 'command lookup; download programs are not package managers' observed
  kai_clients=
  for kai_program in docker podman nerdctl; do
    kai_record=$(kai_program_record "$kai_program") || continue
    [ -z "$kai_clients" ] || kai_clients="$kai_clients,"
    kai_clients="$kai_clients$kai_record"
  done
  kai_fact containerClients "[$kai_clients]" 'command lookup; client presence does not establish engine availability' observed
fi

if kai_has_section docker; then
  if ! command -v docker >/dev/null 2>&1; then
    kai_fact dockerClientAvailable false 'command lookup: docker' absent
  else
    kai_fact dockerClientAvailable true 'command lookup: docker' observed
    kai_probe docker context show
    if [ "$kai_probe_rc" -ne 0 ]; then
      kai_probe_unknown dockerContext 'docker context show' DOCKER_CONTEXT_UNAVAILABLE
    else
      kai_context=$kai_probe_output
      [ -z "$kai_engine_context" ] || kai_context=$kai_engine_context
      kai_fact dockerContext "$(kai_json_string "$kai_context")" 'docker context show or explicitly selected existing context' observed
      kai_probe docker context inspect "$kai_context" --format '{{.Endpoints.docker.Host}}'
      if [ "$kai_probe_rc" -ne 0 ]; then
        kai_probe_unknown dockerEndpoint 'docker context inspect' DOCKER_ENDPOINT_UNAVAILABLE
      else
        kai_endpoint=$kai_probe_output
        if [ -z "$kai_engine_context" ] && [ -z "${DOCKER_CONTEXT:-}" ] && [ -n "${DOCKER_HOST:-}" ]; then kai_endpoint=$DOCKER_HOST; fi
        kai_public_endpoint=$(printf '%s' "$kai_endpoint" | sed 's#://[^ /]*@#://[redacted]@#g;s#[?].*$#?[redacted]#')
        kai_fact dockerEndpoint "$(kai_json_string "$kai_public_endpoint")" 'selected Docker context and applicable DOCKER_HOST override; userinfo redacted' observed
        kai_query_engine=false
        case "$kai_endpoint" in unix://*|npipe://*|tcp://127.0.0.1:*|tcp://localhost:*) kai_query_engine=true ;; esac
        [ -z "$kai_engine_context" ] || kai_query_engine=true
        if [ "$kai_query_engine" != true ]; then
          kai_fact dockerApiReachable null 'remote endpoint not selected for probing' unknown
        else
          if [ -n "$kai_engine_context" ]; then kai_probe docker --context "$kai_engine_context" version --format '{{.Server.Version}}'; else kai_probe docker version --format '{{.Server.Version}}'; fi
          if [ "$kai_probe_rc" -eq 0 ] && [ -n "$kai_probe_output" ]; then
            kai_fact dockerApiReachable true 'Docker version API at the selected endpoint' observed
            kai_fact dockerServerVersion "$(kai_json_string "$kai_probe_output")" 'Docker version API' observed
          else
            case "$kai_probe_rc:$kai_probe_error" in
              124:*|142:*) kai_fact dockerApiReachable null 'Docker API probe deadline' timeout; kai_error DOCKER_TIMEOUT 'The engine probe reached its deadline.' ;;
              125:*) kai_fact dockerApiReachable null 'bounded execution unavailable' unsupported; kai_error BOUNDED_EXECUTION_UNAVAILABLE 'No existing bounded execution facility is available.' ;;
              126:*) kai_fact dockerApiReachable null 'Docker response byte limit' unknown; kai_error PROBE_OUTPUT_LIMIT 'The external response exceeded the probe byte limit; no truncated version was accepted.' ;;
              *[Pp]ermission*[Dd]enied*|*access*denied*) kai_fact dockerApiReachable null 'Docker API permission check' denied; kai_error DOCKER_ACCESS_DENIED 'The current identity cannot access the selected engine.' ;;
              *Cannot*connect*|*cannot*connect*|*connection*refused*) kai_fact dockerApiReachable false 'Docker API connection attempt failed' observed ;;
              *) kai_fact dockerApiReachable null 'Docker API probe failed without a confirmed connection verdict' unknown; kai_error DOCKER_PROBE_FAILED 'The engine response could not establish availability.' ;;
            esac
          fi
        fi
      fi
    fi
  fi
fi
kai_emit_observation
