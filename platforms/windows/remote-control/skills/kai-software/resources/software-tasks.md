# Scripted software tasks

`bash scripts/software-task.sh OP REQUEST.json` runs in the selected target. Set
`ZSETUP_TASK_TARGET_ID` from trusted target metadata; request `targetId` must match.
This package verifies its owner resource lock before executing rules. It needs Bash and
full jq; tool preparation returns the explicit zsetup/jq paths. Set ZSETUP_BIN and
KAI_JQ_BIN (or ZSETUP_TASK_JQ) to those verified target paths.

A basic request: `{ "targetId":"local", "software":"linkspace", "method":"release",
"version":"0.2.0-sim.3", "features":["backup-file-level"], "prefixBase":"/chosen/data/tools" }`.
The path must already exist on a persistent writable executable filesystem. Do not copy
example paths blindly. Query storage-plan first when choosing locations. Full owner
protocol and supported fields are in [owner rules](owner/software/README.md).

- plan returns a read-only `details` object; apply requires that object in request.plan.
- Native packages: explicit storage.paths with physical path, role, bytes and inodes;
  reserveBytes is counted once per volume. Reuse compatible installed packages without
  implicit upgrade; query reports registration separately from functional validation.
- Releases: app-owned exact platform/URL/SHA/size, verified download through zsetup; no
  guessed GitHub name. Linkspace backup candidate supports file-level backups, not whole
  disk images, live database consistency, Windows ACL recovery or a Windows directory
  durability barrier. Verify reports the actual feature contract.
- artifact: AI-reviewed local build with exact digest/platform/typed self-test; same
  storage, immutable versions, command activation, rollback and ownership rules.
- container: curated nginx-static image digest, explicit start and data budget; separate
  daemon readiness, old/new health gate, private bridge; preserve data/images on removal.
- Removal requires a fresh plan with intent remove and the original installation method.
  Remove program resources only; native hooks retain their own policy.
- backup-plan/run/restore: choose actual file scope and separate persistent repository;
  check integrity, restore to a new directory, then compare. Never infer database safety.

stdout is one software-task/v1 JSON. Exit 0 success,20 needs-ai,21 blocked,22 failed,
2 invalid. Keep nativeExitCode and effects. Unknown recipes/functional checks need AI;
network/integrity/permissions are explicit failures and must not silently change source.
AI output can return as a reviewed artifact; never overwrite an unowned user command.

## Agent 调用绑定

`inspect` / `plan` / `apply` 是软件业务动作，`software-task/v1` 是脚本输入输出合同，不规定 Agent 的工具 API。共享技能源不嵌入某个 Agent 的技能加载工具；技能发现、加载及授权属于实际宿主。

宿主提供绑定时，按它声明的真实工具、参数包装和目标范围调用；没有绑定时用已选 Transport 执行随技能分发的 task-entry 脚本。Windows 可从原生 PowerShell 进入，不要求预装 Bash/jq。两条路径保持 software、intent、plan、targetId 和结构化状态/效果的语义，未知来源、审批和取消不会因更换 Agent 而放宽。
