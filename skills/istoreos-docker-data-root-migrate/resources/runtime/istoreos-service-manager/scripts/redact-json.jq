def secret_name:
  ascii_downcase | gsub("[-_]"; "") |
  test("(password|passwd|token|secret|apikey|authorization|privatekey)");
def secret_text:
  test("(://[^/@[:space:]]+:[^/@[:space:]]+@|[?&](token|password|secret|key|auth)=|(password|passwd|token|secret|api[_-]?key|authorization|private[_-]?key)[[:space:]]*[:=])"; "i");
if length != 1 then error("one structured document required")
else .[0] as $original | $original |
  walk(if type == "object" then
         with_entries(if (.key | secret_name) then .value = "[REDACTED]" else . end)
       elif type == "string" then (if secret_text then "[REDACTED]" else . end)
       else . end) |
  if . == $original then empty else . end
end
