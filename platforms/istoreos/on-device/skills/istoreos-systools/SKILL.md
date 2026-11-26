---
name: istoreos-systools
description: 查询明确的系统范围，或执行所选原生 systools 动作；返回原生退出结果。
resource-discovery: explicit
---

This directory is an independent skill. Resolve paths relative to this SKILL.md,
and run commands on the selected target through its existing authorized Transport.
Other Kai skills named below are optional specialists; this directory contains
the executable resources for its explicitly selected operations. The model decides analysis, composition and task completion.

## Local supporting resources

- `istoreos-package-manager`: [local instructions](resources/runtime/istoreos-package-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `istoreos-service-manager`: [local instructions](resources/runtime/istoreos-service-manager/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-system-information`: [local instructions](resources/runtime/kai-system-information/GUIDANCE.md); executable helpers under that resource’s `scripts/`.
- `kai-tool-bootstrap`: [local instructions](resources/runtime/kai-tool-bootstrap/GUIDANCE.md); executable helpers under that resource’s `scripts/`.

Optional tool preparation: `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`
or the separately authorized `ensure TOOL` operation. The native Windows preparation interface is
use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`
through existing native PowerShell. Querying this skill does not install missing tools.

## Operation interfaces
`sh scripts/inspect.sh SCOPE` 返回所选事实，支持范围以参数说明为准。`KAIPLUS_CONFIRMED=1 sh scripts/apply.sh ACTION [ARGUMENT]` 仅执行已登记的具体动作：ipv6_pd、ipv6_relay、ipv6_nat、ipv6_half、ipv6_off、istore-reinstall、reinstall_incompatible_kmods。

这些动作可修改网络、包或服务并中断连接，需要既有目标授权；标记不是宿主授权。原生动作内部可能是固定事务，其成功只代表该接口结果。未支持的动作、缺 dispatcher 和原生失败均明确返回，不替换为源码树中同名脚本，不安装持久守卫。
