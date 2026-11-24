# 有界软件查询验收

2026-11-24。候选业务版本 1.2.11；common 1.1.7、iStoreOS 2.0.4。未公开发布，未部署服务器。

## 目标和任务树

- [x] 软件目录留在提供者/脚本内部，search / detail / inspect 分离。
- [x] 默认 3 项、最多 10 项；摘要 240 个 Unicode 字符；完整查询 JSON 至多 8192 字节。身份不截断，超限返回明确失败。
- [x] 复用 apt/opkg、iStore、Scoop/WinGet；提供原生 Brew Formula/Cask 读适配和 APK 缓存名字查询。Docker 仅显式查询本机镜像/容器，不推断远端候选。
- [x] Windows 原生 PowerShell 查询不要求 Bash/jq；Unix 缺工具明确阻塞，不自动准备、安装或刷新源。
- [x] 精确名称优先，同名跨来源保留；附属资源作为数据/运行时分发，不增加自动激活的技能入口。
- [x] 原 task-entry 的 plan/apply、来源校验、权限/保护、Transport/取消语义继续保留；查询投影不是执行计划。
- [x] 大目录、独立技能重定位、Unicode/字节边界、来源身份与缺口、Docker 字段隔离、原 PowerShell 与 Bash 3.2 检查。
- [x] 同步 32 个独立包、10 个预设、12 个集合锁；消费者源码锁由 KaiPlus 仓库记录。

## 三轮记录

| 轮次 | 结果 |
| --- | --- |
| 1 | 新查询路径初测通过；跨平台全套首次 163 项有两项因 Bash 3.2 环境变量名称错误而未执行业务断言。旧 Go 输出结构断言及模块依赖清单同步到查询投影合同。 |
| 2 | 正确测试环境下 163 项回归通过（15 项原生平台条件跳过）；新增独立安装测试复现子目录脚本重定位错误，不能交付。 |
| 3 | 入口移至打包机制支持的位置；补充真实 Scoop 搜索模块、APK、opkg、Brew 核心/容器身份和输出边界检查。文档结构检查改为验证按需引用及被引用的原网络归属规则。最终结果见下。 |

技能入口由 4009 字节缩至 2827 字节；Homebrew 默认阅读资料由 14865 字节缩至 3154 字节，保留的操作/私有运行时资料按需读取。这是字节测量，不是模型 token 或端到端耗时基准。

## 实现范围

`query-entry.sh` / `query-entry.ps1` 为普通脚本入口，不规定 Agent 工具名。分派脚本约 60 行，平台/投影拆成小文件；search 先过滤再输出，不把完整目录或 raw manifest 放进模型上下文。已知软件可以直接 inspect，模型按完整任务继续决定是否需要其他证据；没有引入宿主业务意图路由或任务终结器。

独立包包含所需 iStore 搜索/离线目录资源，只有根 SKILL.md 是可发现技能。资源清单不代表查询时加载全部 GUIDANCE 或数据。既有完整目录、安装器、来源锁与其他生命周期仍由原 owner 管理。

新查询保留原生登记、商店登记和运行版本的不同含义。未执行程序版本探测就不宣称验证运行版本；没有缓存候选不宣称在线最新。APK 名字检索显式禁止网络，依照 [apk-search](https://raw.githubusercontent.com/alpinelinux/apk-tools/master/doc/apk-search.8.scd) 和 [全局网络选项](https://raw.githubusercontent.com/alpinelinux/apk-tools/master/doc/apk.8.scd)；候选比较仍复用 owner，未构造新的安装策略。

Docker 结果区分 docker-image 与 docker-container；iStore Docker 应用仍保留 istore 身份。只读查询不支持任意远端 daemon/镜像仓库，也不把标签当作更新证明。Windows Docker 查询当前明确不支持，保留使用其他已有能力的空间。

## 验证证据

- 新增查询用例 16 项通过：上万条目录、精确/部分匹配、同名来源、原生 PowerShell 无 Bash/jq、Scoop 多 bucket 精确优先、Bash 3.2、APK 禁止网络、opkg 分派、iStore Top-N、Brew Cask/core 完整身份、Docker 私密字段隔离、独立包无兄弟目录、过长身份/JSON 明确失败。
- 原跨平台套件 163 项：148 通过，15 按原生设备/条件跳过；未关闭测试。
- 业务全套初次 123 项中有两项缺 TEST_NATIVE_ZSETUP、一项仍按旧正文位置检查网络归属规则，一项原生校验和集成被环境条件跳过。补齐环境并将检查沿显式引用追到原规则后，对应检查通过；最终完整业务套件 125 项全部通过，无跳过。
- 生成一致性、模块摘要同步和独立技能 Codex 校验通过；最终消费者构建结果见 KaiPlus 验收记录。

不把 Linux 上的 PowerShell/Bash 测试或协议夹具称为原生 Windows/macOS 全流程验收。没有在本轮启动真实模型、修改目标软件或触发设备恢复点，也未解决此前 .93 的保护收尾/重启问题。
