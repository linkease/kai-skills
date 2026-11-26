---
name: istoreos-systools
description: 查询明确的系统范围，或执行所选原生 systools 动作；返回原生退出结果。
owner: system-pack/istoreos
systems: istoreos
triggers: IPv6 模式, IPv6 PD, IPv6 relay, IPv6 NAT, 硬盘不休眠, 硬盘唤醒, 应用商店损坏, iStore 修复, 升级后异常, 内核模块不兼容
negative-triggers: 网络测速, 网速慢, NAT 类型, 局域网测速, 普通软件安装, Docker 镜像下载, overlay 空间不足
auto-use: suggest
needs-fresh-data: true
cost: low
resource-discovery: explicit
---

`sh scripts/inspect.sh SCOPE` 返回所选事实，支持范围以参数说明为准。`KAIPLUS_CONFIRMED=1 sh scripts/apply.sh ACTION [ARGUMENT]` 仅执行已登记的具体动作：ipv6_pd、ipv6_relay、ipv6_nat、ipv6_half、ipv6_off、istore-reinstall、reinstall_incompatible_kmods。

这些动作可修改网络、包或服务并中断连接，需要既有目标授权；标记不是宿主授权。原生动作内部可能是固定事务，其成功只代表该接口结果。未支持的动作、缺 dispatcher 和原生失败均明确返回，不替换为源码树中同名脚本，不安装持久守卫。
