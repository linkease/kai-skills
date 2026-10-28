package skill_test

import (
 "encoding/json"
 "os"
 "path/filepath"
 "slices"
 "strings"
 "testing"

 "reasonix/internal/capability"
 "reasonix/internal/skill"
 "reasonix/internal/tool"
)

func TestKaiMultisystemDistributionConsumer(t *testing.T) {
 var data struct {
  Roots []struct { Platform, Mode, Consumer, Path string }
  Aliases map[string]string
  Cases []struct { Platform, Task, Skill string }
 }
 body,err:=os.ReadFile(os.Getenv("KAI_DISTRIBUTION_INPUT"));if err!=nil {t.Fatal(err)}
 if err=json.Unmarshal(body,&data);err!=nil {t.Fatal(err)}
 common:=[]string{"kai-software","kai-dev-environment","kai-project-dependencies","kai-download-acceleration","kai-storage-files","kai-tool-bootstrap"}
 for _,root:=range data.Roots {
  t.Run(root.Platform+"/"+root.Mode+"/"+root.Consumer,func(t *testing.T) {
   store:=skill.New(skill.Options{HomeDir:t.TempDir(),CustomPaths:[]string{root.Path},DisableBuiltins:true,DisableDefaultRoots:true})
   for _,name:=range common {
    value,ok:=store.Read(name);if !ok {t.Fatalf("missing %s",name)}
    if value.Owner!="system-pack/common" {t.Fatalf("%s owner=%q",name,value.Owner)}
    if name=="kai-tool-bootstrap" && len(value.Requires)!=0 {t.Fatal("bootstrap is hidden behind a missing Bash prerequisite")}
    if !slices.Contains(value.Systems,root.Platform) {t.Fatalf("%s lost target system metadata",name)}
   }
   for old,current:=range data.Aliases {
    value,ok:=store.Read(old);if !ok || value.Name!=current {t.Errorf("alias %s did not resolve uniquely to %s",old,current)}
   }
   listed:=store.List()
   for _,value:=range listed {if _,retired:=data.Aliases[value.Name];retired {t.Fatalf("retired primary is active: %s",value.Name)}}
   entries:=capability.SkillEntries(listed,[]tool.ContractEntry{{Name:"run_skill"}})
   for _,test:=range data.Cases {
    if test.Platform!=root.Platform {continue}
    decision:=capability.Route(test.Task,entries);var primary []string
    for _,candidate:=range decision.Candidates {if candidate.Entry.RoutingGroup=="system-primary" {primary=append(primary,candidate.Entry.ID)}}
    if len(primary)!=1 || primary[0]!="skill:"+test.Skill {t.Errorf("%q primary=%v want %s",test.Task,primary,test.Skill)}
   }
   runtime,_:=store.Read("kai-dev-environment")
   if !strings.Contains(runtime.Body,filepath.Join(root.Path,"kai-dev-environment","scripts","runtime.sh")) {t.Error("SDK script path was not expanded to the installed bundle")}
   for _,value:=range listed {
    if root.Mode=="on-device" && strings.HasPrefix(value.Name,"target-") {t.Fatal("third-party Transport leaked into on-device composition")}
    if root.Platform!="istoreos" && strings.HasPrefix(value.Name,"istoreos-") {t.Fatal("iStore primary leaked into another target")}
   }
  })
 }
}
