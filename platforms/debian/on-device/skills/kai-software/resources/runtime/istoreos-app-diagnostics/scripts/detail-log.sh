#!/bin/sh
set -eu

phase="${1:-all}"
case "$phase" in
  all) cat ;;
  package) grep -Ei 'opkg|package|install|configur|depend|download|checksum|hash|architect|space|read-only' || : ;;
  autoconf) grep -Ei 'auto ?config|istorea|uci|/etc/config|path|permission|tracker|restart|enable' || : ;;
  runtime) grep -Ei 'docker|container|image|pull|volume|mount|port|address already|oom|out of memory|service|init.d' || : ;;
  *) echo 'invalid detail phase' >&2; exit 2 ;;
esac
