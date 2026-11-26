#!/bin/sh
# Bounded observation subprocesses; requires receipt.sh and caller-owned temporary directory.
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

