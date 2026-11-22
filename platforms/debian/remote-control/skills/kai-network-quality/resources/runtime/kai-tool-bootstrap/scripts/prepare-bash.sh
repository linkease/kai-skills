#!/bin/sh
# Called before Bash exists. Native managers retain download/integrity policy.
set -u
action=$1
manager=unavailable
if command -v opkg >/dev/null 2>&1; then manager=opkg
elif command -v apk >/dev/null 2>&1; then manager=apk
elif command -v apt-get >/dev/null 2>&1; then manager=apt-get
elif command -v brew >/dev/null 2>&1; then manager=brew
fi
if [ "$action" != ensure ]; then
    printf '{"schemaVersion":1,"protocol":"kai-runtime/v1","ready":false,"status":"preparation-required","stage":"bash","provider":"%s","reason":"compatible-bash-missing","exitCode":0}\n' "$manager"
    exit 0
fi
code=0
case "$manager" in
    opkg) opkg install bash >&2 || code=$? ;;
    apk) apk add bash >&2 || code=$? ;;
    apt-get) apt-get install -y bash >&2 || code=$? ;;
    brew) brew install bash >&2 || code=$? ;;
    *) code=18 ;;
esac
# Successful installation continues in prepare.sh; never emit two JSON objects.
[ "$code" = 0 ] && exit 0
printf '{"schemaVersion":1,"protocol":"kai-runtime/v1","ready":false,"status":"blocked","stage":"bash","provider":"%s","reason":"native-bash-preparation-failed","exitCode":%s}\n' "$manager" "$code"
exit "$code"
