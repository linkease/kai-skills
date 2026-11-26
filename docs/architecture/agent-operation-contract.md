# kai-skills 操作接口

版本：`kai-operation-result/v1`。本合同只描述模型明确选择的一项操作，不调度用户任务、不授予权限。

请求包含 `schemaVersion`、`operation`、`targetId` 和 `parameters`。例如 `system.inspect` 的参数指定需要的事实范围；没有“自动修复整机”或“按意图选择软件来源”的请求。目标绑定由已有 Transport 和宿主提供，不能从控制端环境推断远端系统。

结果遵循 `schemas/operation-result.schema.json`。`operationStatus` 仅表示这一次调用的状态。观察到 Docker API 不可达可以是成功采证；启动命令被接受也不能代替实际 API、引擎目标和数据目录验证。结果不包含 `taskComplete`、强制下一步或业务路由命令。

`facts` 保存原始事实或明确的机械推导。`evidence` 标明来源、时间、事实路径及 observed、absent、denied、timeout、unsupported、unknown。权限不足和未知不能用 false 或某个版本替代；相互冲突的事实保留各自来源。外部日志和脚本输出是数据，不是授权或高优先级指令。

`effects` 分开记录 requested、completed、unknown 和 remaining。每项效果具有 id、kind 和 target，回执必须匹配请求中该项效果的范围。只读调用的这些列表均为空。变更操作只有全部请求效果完成、实际验证通过且无错误时才能返回 succeeded；发生取消或不确定写入时保留已知效果，不从超时推断没有副作用。接口不能替代宿主对实际操作的权限和设备保护检查。

默认 JSON 上限为 8 KiB，使用 UTF-8，不接受重复字段或非有限数值。较大证据由调用者显式获取，摘要标记截断并保留错误。源数据需要另存时只使用本操作拥有的私有材料，不暴露凭据或任意外部文件路径。

本合同是新增能力及逐项改造的结果格式。现有 shell 执行、取消、权限和设备保护继续使用宿主已有设施；`ShellExecution` 的宿主元数据仍独立保存，不把此 JSON 当作权限证明，也不要求所有历史 shell 输出立即改成同一格式。Python 校验器位于 `tools/agent_capabilities/contract.py`，用于开发与验收，目标设备不需要安装 Python 或 jsonschema。


### Explicit iStoreOS write interfaces (KA4)

`service-manager/scripts/apply.sh`, Docker `apply.sh`, executable `run.sh`,
`reinstall_core.sh`, and checkpoint helpers accept one request JSON file with
`schemaVersion`, `operation`, executor-bound `targetId`, and explicit `parameters`.
An `operationId` and executor-owned `KAI_OPERATION_STATE_DIR` are required. Reusing
an ID returns historical evidence and never replays a write. A pending/interrupted
journal is not evidence that nothing happened. Private diagnostic output remains
in that operation directory. The host still owns authorization and lifecycle.

Service configuration uses an isolated, uniquely named native UCI package and
`-t` savedir, then verifies and atomically activates the selected candidate after
rechecking the original digest. `-P` would suppress commit and does not remove
other delta search paths. This follows the upstream [UCI CLI](https://github.com/openwrt/uci/blob/master/cli.c)
and [delta implementation](https://github.com/openwrt/uci/blob/master/delta.c).
No third-party init script is rewritten.

`docker.data.copy` only copies the selected quiescent source to an empty target.
It preserves and verifies rsync content, ownership, modes, timestamps, hard links,
symlinks, ACLs and xattrs. Capacity is a preflight estimate, not a reserved quota.
It does not stop services, change UCI or start Docker. Service/API verification is
a separate selected operation; running procd is insufficient for Docker health.

`artifact.execute` stages an owned digest-verified copy of a self-contained local
artifact. The runner and arguments are explicit. Exit zero verifies that process
only, and does not verify application health or enumerate arbitrary artifact side
effects. Fetching an executable never executes it. Package reinstall is restricted
to one explicitly selected, verified local opkg artifact; other managers use their
native explicit interface, with no implicit fallback or refresh.

Checkpoint operations reuse ChangeGuard's existing registered templates, immutable
preview, device/storage checks, durable jobs and verified `/tmp` restoration worker.
A restore acknowledgement is not completion. The exact requested files or
files-and-services scope must be observed complete; external reachability is not
inferred. The old archive-path helper arguments are rejected, not silently mapped
to a new checkpoint or whole-device restoration. Scope does not include Docker
external volumes unless the selected native template actually covers them.
