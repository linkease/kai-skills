#!/bin/sh
# Use the real Reasonix loader without editing its checkout or Agent config.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
reasonix="${1:?usage: test-reasonix-consumer.sh REASONIX_SOURCE_ROOT}"
reasonix="$(CDPATH= cd -- "$reasonix" && pwd -P)"
[ -f "$reasonix/internal/skill/skill.go" ] || { echo 'failed: Reasonix skill loader source not found' >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for mode in on-device remote-control; do
  sh "$root/install.sh" --platform istoreos --mode "$mode" --consumer generic --target-skills "$tmp/$mode" --dry-run >"$tmp/plan-$mode"
  sh "$root/install.sh" --platform istoreos --mode "$mode" --consumer generic --target-skills "$tmp/$mode" >/dev/null
done
cat >"$tmp/consumer_test.go" <<'EOF'
package skill
import (
 "os"
 "path/filepath"
 "slices"
 "strings"
 "testing"
)
func TestLinkeaseGeneratedConsumer(t *testing.T) {
 for _, mode := range []string{"on-device", "remote-control"} {
  t.Run(mode, func(t *testing.T) {
   installed := filepath.Join(os.Getenv("LINKEASE_CONSUMER_FIXTURE"), mode)
   store := New(Options{HomeDir:t.TempDir(), CustomPaths:[]string{installed}, DisableBuiltins:true})
   download, ok := store.Read("kai-download-acceleration")
   if !ok { t.Fatal("download skill not discovered") }
   dependencies,found := store.Read("kai-project-dependencies")
   if !found || !slices.Contains(dependencies.Triggers,"pip install") || !slices.Contains(dependencies.Triggers,"go mod") { t.Fatal("dependency routes not parsed by actual loader") }
   if download.Owner!="system-pack/common" || !slices.Contains(download.Systems,"istoreos") || download.AutoUse!="prefer" || download.RoutingGroup!="system-primary" || !download.NeedsFreshData { t.Fatal("system/routing metadata lost") }
   if !strings.Contains(download.Body,filepath.Join(installed,"kai-download-acceleration","scripts","accelerate.sh")) { t.Fatal("actual script paths missing from loaded body") }
   runtime, ok := store.Read("kai-dev-environment")
   if !ok || !strings.Contains(runtime.Body,filepath.Join(installed,"kai-dev-environment","scripts","runtime.sh")) { t.Fatal("runtime execution reference missing") }
   if strings.Contains(runtime.Body,"## Reference:") { t.Fatal("detailed data eagerly inlined") }
   catalog:=CatalogBlock(store.List())
   if !strings.Contains(catalog,"kai-download-acceleration") { t.Fatal("primary missing from catalog") }
   if strings.Contains(catalog,"istoreos-app-diagnostics") { t.Fatal("manual helper leaked into catalog") }
  })
 }
}
EOF
jq -n --arg source "$reasonix/internal/skill/linkease_consumer_test.go" --arg replacement "$tmp/consumer_test.go" '{Replace:{($source):$replacement}}' >"$tmp/overlay.json"
cd "$reasonix"
LINKEASE_CONSUMER_FIXTURE="$tmp" go test -overlay "$tmp/overlay.json" ./internal/skill -run '^TestLinkeaseGeneratedConsumer$' -count=1
echo 'ok: actual Reasonix loader consumes both generated presets and routing metadata'
