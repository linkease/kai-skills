// Run the checked-out OpenCode parser against the actual published directory shape.
import { readFileSync } from "node:fs"
import { dirname } from "node:path"

const { parse } = await import(process.argv[2])
const inputs = JSON.parse(readFileSync(0, "utf8"))
const results = inputs.map((input: { path: string; id: string; manual: boolean }) => {
  const value = parse(dirname(dirname(input.path)), input.path, readFileSync(input.path, "utf8"))
  if (value._tag !== "Parsed" || value.skill.id !== input.id || !value.skill.description) {
    throw new Error(`OpenCode rejected ${input.id}: ${JSON.stringify(value)}`)
  }
  if (input.manual && value.skill.autoinvoke !== false) throw new Error(`Manual invocation lost for ${input.id}`)
  return { id: value.skill.id, autoinvoke: value.skill.autoinvoke, status: "passed" }
})
process.stdout.write(JSON.stringify(results))
