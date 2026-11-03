# Conservative verifier for the maintained idna/is-number/uuid smoke recipes.
function metadata(p) {
  if (tool == "pip") return p == "/simple/idna/"
  if (tool == "npm") return p == "/is-number"
  return p == "/github.com/google/uuid/@v/v1.6.0.mod" || p == "/github.com/google/uuid/@v/v1.6.0.info"
}
function artifact(p) {
  if (tool == "pip") return p ~ /\/idna-3\.10-[^\/]+\.whl$/
  if (tool == "npm") return p == "/is-number/-/is-number-7.0.0.tgz"
  return p == "/github.com/google/uuid/@v/v1.6.0.zip"
}
function urlpath(u) {
  sub(/^https?:\/\/[^\/]+/, "", u)
  sub(/[?#].*$/, "", u)
  sub(/:$/, "", u)
  return u
}
function field(key,    i,value) {
  for (i=1; i<=NF; i++) if (index($i,key "=") == 1) { value=substr($i,length(key)+2); return value }
  return ""
}
FILENAME == ARGV[1] {
  if ($0 ~ /cache hit/) next
  if ($0 ~ /npm http fetch GET.*https:\/\/registry\.npmjs\.org/ ||
      $0 ~ /Downloading.*https:\/\/(files\.pythonhosted\.org|pypi\.org)/ ||
      $0 ~ /^# get https:\/\/(github\.com|proxy\.golang\.org)\// ||
      $0 ~ /git (ls-remote|fetch|clone)/) direct=1
  if ($0 !~ /(GET|get|Downloading|Fetching|fetch)/) next
  line=$0
  while (match(line,/https:\/\/dl-[a-z-]+\.linkease\.net(:[0-9]+)?[^[:space:]"]*/)) {
    u=substr(line,RSTART,RLENGTH)
    line=substr(line,RSTART+RLENGTH)
    authority=u; sub(/^https:\/\//,"",authority); sub(/\/.*$/, "", authority)
    expected="dl-" (tool == "pip" ? "pypi" : tool == "go" ? "golang" : "npm") ".linkease.net:" port
    p=urlpath(u)
    # urllib may log the host separately from a quoted GET path.
    if (p == "" && match($0,/GET \/[^[:space:]]+/)) p=substr($0,RSTART+4,RLENGTH-4)
    if (authority == expected && metadata(p)) cm[p]=1
    if (tool == "pip") expected="dl-pypi-files.linkease.net:" port
    if (authority == expected && artifact(p)) ca[p]=1
  }
  next
}
FILENAME == ARGV[2] {
  if ($0 !~ /download gateway/) next
  if ($0 ~ /download gateway pypi-index/ && tool == "pip" && field("status") == "ok" && field("http_status") ~ /^2[0-9][0-9]$/ && field("host") == "dl-pypi.linkease.net:" port) {
    p=field("path"); if (metadata(p)) gm[p]=1
    next
  }
  mirror=field("mirror")
  expected=(tool == "pip" ? "pypi-files" : tool == "go" ? "golang" : "npm")
  if (mirror != expected) next
  if ($0 ~ /download gateway GET/) {
    # GET events alone do not prove a completed download.
  }
  if ($0 ~ /download gateway done/) {
    # done is emitted only for StatusOK, including races without GET events.
    p=urlpath(field("url")); if (field("bytes")+0 > 0) completed[p]=1
  }
}
END {
  for (p in cm) if (gm[p] || completed[p]) meta=1
  for (p in ca) if (completed[p]) art=1
  print "gateway_metadata=" (meta ? "matched" : "missing")
  print "gateway_artifact=" (art ? "matched" : "missing")
  if (direct) { print "result=client-direct-observed"; exit 4 }
  if (meta && art) { print "result=gateway-confirmed"; exit 0 }
  print "result=insufficient-evidence"; exit 4
}
