#!/bin/sh
# Prepare the isolated lab image; preserve the firmware's downloader and policy.
set -eu

evidence=/usr/share/kai-lab
mkdir -p /tmp /var/lock /etc/dropbear "$evidence"
sha256sum /usr/bin/curl /usr/lib/libcurl.so.* /usr/lib/libzstd.so.* \
    /usr/lib/opkg/info/curl.control /usr/lib/opkg/info/libcurl4.control \
    /etc/opkg.conf > "$evidence/system-curl.sha256"
curl --version > "$evidence/system-curl.version"
grep -q '^option check_signature' /etc/opkg.conf

# curl, CA certificates and Dropbear already belong to the firmware. Python and
# Git are not required for MS1: the controller runs Python outside the target.
opkg update
opkg install bash jq
is-opkg install mise

# Abort the image build if a dependency resolver changes the system downloader.
sha256sum -c "$evidence/system-curl.sha256"
curl --version > "$evidence/system-curl.after-version"
cmp "$evidence/system-curl.version" "$evidence/system-curl.after-version"
test -x /usr/bin/mise
test -x /usr/sbin/mise-exec
test -f /lib/functions/mise.sh
