# Emit original JSON key tokens with their object identity. jq decodes escapes
# before comparing keys; this lexer never evaluates target data or writes files.
BEGIN { depth=0; object=0; quoted=0; escaped=0; candidate=0 }
{
  text=$0 "\n"
  for(i=1;i<=length(text);i++) {
    c=substr(text,i,1)
    if(quoted) {
      token=token c
      if(escaped) escaped=0
      else if(c=="\\") escaped=1
      else if(c=="\"") {quoted=0;candidate=1}
      continue
    }
    if(c ~ /[[:space:]]/) continue
    if(c==":" && candidate && kind[depth]=="object") printf "[%d,%s]\n", owner[depth], token
    candidate=0
    if(c=="\"") {quoted=1;token=c}
    else if(c=="{") {depth++;kind[depth]="object";owner[depth]=++object}
    else if(c=="[") {depth++;kind[depth]="array"}
    else if(c=="}" || c=="]") {delete kind[depth];delete owner[depth];depth--}
  }
}
END { if(quoted || depth!=0) exit 1; print "[-1,\"complete\"]" }
