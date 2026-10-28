# Kai Skills 多系统实施记录

逐阶段状态见 [multisystem-status.json](multisystem-status.json)，验收范围见 [scope.json](../../tests/multisystem/scope.json)。TDD 中为新增行为建立的预期失败不计为阶段优化轮次；完整阶段自检未通过后的修正计为一轮，最多三轮。

## MS0 范围与基线

任务树：冻结平台与工具来源；逐项登记旧 Skill 去向；定义任务路由用例；实现统一测试入口；执行现有回归并记录证据。

验收标准：MS0 至 MS10 每项目标都有 ID、预期与证据类型；至少 30 条路由输入分别声明所属任务；现有回归有独立结果，失败不能被跳过。

结果：通过，阶段优化 0 轮。冻结了五个平台、35 条路由用例、20 个旧 Skill 的迁移决策。统一入口公开全部测试清单，拒绝空选择和源码目录内的证据目录；缺失测试和非零退出码按失败记录。既有 architecture、canonical、Transport、generated、discovery、context、Windows/macOS、lifecycle、release、Agent bundle、recommendations、runtime gate 与实际 Reasonix loader 共 15 项回归，加上新的范围清单契约，共 16 项通过。

证据：[MS0 基线结果](multisystem-ms0-baseline.json)。35 条路由在此阶段是冻结的验收输入，实际任务路由行为由后续实现与综合验收验证。

## MS1 隔离测试实验室

任务树：实现配置与执行器；固定真实镜像/rootfs 来源；创建带 run 所有权的容器和网络；验证容器内命令与 SSH；执行失败和超时后的定向清理；在每个平台重复两轮。

验收标准：三个实际系统身份、包数据库与制品摘要明确；iStoreOS 具备真实 mise 集成；工作目录使用试验所有的持久存储；普通测试容器不挂载宿主根目录或 Docker socket，不使用 privileged；两轮运行及错误清理通过，宿主 Docker data_root 不变。

上一轮结果：阻塞。离线接口契约 3 项通过，Ubuntu 和 Debian 均通过两轮本机/SSH 执行及两类失败清理。iStoreOS 使用只读固件 ROM 导出的完整 rootfs，排除 SSH 主机密钥后导入 Docker；真实软件包安装构建未通过。包安装构建步骤使用 host 网络获取发布物，运行时使用本次试验的独立 bridge 网络；此差异记录在镜像锁中。

| 自检轮次 | 调整 | 实际结果 |
| --- | --- | --- |
| 初次 | 直接安装测试所需的软件包 | 新 curl 请求旧 libcurl 未提供的符号，后续下载失败 |
| 优化 1 | 先更新 libcurl4，再更新 curl | 更新 libcurl 后 opkg 自动移除 libzstd，旧 curl 无法继续下载 |
| 优化 2 | 先设置 libzstd 的 user 标记，再配套更新 | 此版本仍将 libzstd 作为自动依赖移除，失败相同 |
| 优化 3 | 在容器内设置 use_curl 0，保持签名检查，尝试切换下载后端并配套更新 | 日志仍显示 curl 被实际调用，curl 下载新包时因缺少 libzstd 返回 127 |

按照用户指定的最多三轮优化规则，达到上限后停止 MS1，未进入 MS2。原 iStoreOS 宿主的软件包和配置未修改；Docker data_root 仍为迁移后的目录。本次标签下没有遗留的运行/停止容器或 bridge 网络，保留 Ubuntu/Debian 可复用镜像、iStoreOS 原始 rootfs 和诊断证据以便继续排查。

2026-10-27 用户授权专项修复，并明确不需要修改 iStoreOS 自带 curl。根因是实验室初始依赖清单显式请求了已有 curl；围绕此升级继续修补扩大了问题。专项修复移除 curl/libcurl 升级及 opkg 下载后端修改，仅补齐 Bash、jq 和原生 mise 集成，增加构建前后系统 curl、libcurl、libzstd、包元数据和 opkg 配置摘要与版本不变断言。宿主机也核验 curl、动态库与 opkg 配置未变。初次专项自检中镜像构建及摘要验证通过，随后发现 SSH 公钥路径不适配 OpenWrt Dropbear；优化 1 使用其原生 `/etc/dropbear/authorized_keys`，SSH 通过。补充 SIGTERM 取消清理后再跑完整 MS1，自检 4/4 通过；其中离线契约包含 4 个行为测试，每个真实目标均完成两轮执行以及注入失败、超时、实际取消信号三类清理。MS1 当前状态为通过，旧三轮失败历史保留，不重写为成功。

证据：[MS1 各轮结果](multisystem-ms1-results.json)、[镜像与 rootfs 来源锁](../../tests/multisystem/environment-lock.json)。MS2 至 MS10 的 required 用例仍保留在清单中，后续按原计划继续推进。

## MS2 执行与平台接口

任务树：平台事实识别；控制端执行接口；argv/cwd/env/stdin 传递；退出码和传输错误区分；输出限制；进程树超时和信号取消；Windows 原生命令与 Git Bash 离线计划。

验收标准：复杂参数不变且无命令注入；各次环境隔离；保留业务退出码；SSH 传输失败单独分类；超时和取消阻止后代进程写入标记；Linux/macOS/iStoreOS/Windows/WSL fixture 识别正确。

结果：7 项公共 CLI 行为测试通过，优化 0 轮。控制端实现位于 tools/multisystem，不向 iStoreOS 安装 Python，不替换 Kai Target Transport；后续公开任务 helper 继续由 canonical System Pack 所有。SSH 契约通过实际 POSIX shell 的参数序列化边界验证，并区分远端业务返回 255 与 SSH 自身失败。Windows 原生命令与 Git Bash 为离线计划验证，未连接 Windows，macOS/Windows 原生验收 pending。测试证据见 [MS2 结果](multisystem-ms2-results.json)。

## MS3 工具发现与引导

任务树：探测版本与原管理者；生成平台计划；按需引导 zsetup/mise/ks-cli；验证重复调用复用；验证外部冲突与下载失败；保留原系统下载工具；提供 Windows 首次 Bash 原生入口。

验收标准：兼容工具不重装；未知外部来源不覆盖；Linux 实际执行 zsetup install ks-cli --foreground；iStoreOS 使用独立 ks-cli 包；客户端安装不改变服务清单或启动网关；iStoreOS mise 具备集成文件和容器持久 runtime_dir；桌面端缺内部产物明确不可用。

结果：三系统真实工具安装及重复复用通过。Ubuntu/Debian 实际安装 zsetup 0.5.1、ks-cli 0.8.5、mise 2026.8.14；iStoreOS 使用正式 ks-cli 0.8.5-1 包与原生 mise 集成。系统 curl、库与 opkg 配置保持不变；服务文件不变，无网关进程启动。新控制端不安装到宿主。

优化 1 解决 Debian merged-/usr 的包所有权路径差异，但误给 download 使用了 capture 的 --timeout，实际返回 2；优化 2 按实际 CLI 合约使用 --overall-timeout/--probe-timeout/--connect-timeout/--read-idle-timeout，小文件 HTTPS 对照通过后，三系统完整 MS3 通过。初次 GitHub mise 下载超时与该参数错误历史均保留。

当前离线契约 12 项，另覆盖 Homebrew 文件所有权与系统 shasum、已有 macOS zsetup 0.4.0 复用、Windows 原生信任路径转换、真实临时 HTTPS 的摘要/版本/空间/取消等场景。Windows Bash 首次入口为原生 PowerShell + winget Git.Git；本机无 PowerShell 解析器，语法/内核行为仍待 MS9 与后续原生验收，不把静态脚本存在视为运行成功。jq 是公开 JSON helper 的显式原生包前置条件。证据见 [MS3 结果](multisystem-ms3-results.json)。

## MS4 软件搜索与生命周期

任务树：统一来源限定的软件 ID 与结果；只读缓存查询；显式索引刷新；精确版本系统包安装；命令功能与文件归属；幂等安装；保留项目文件的卸载；内部软件原安装者路径。

验收标准：三系统各完成一个系统包和一个内部软件的查询、安装、实际执行和卸载；无隐式刷新；同名不同源不合并；原生错误和配置/项目文件保留；内部产品缺能力时不以负向用例替代正向验收。

首次运行结果（历史）：等待产品决策，当时阶段未通过。离线公共 CLI 契约 8 项通过。优化 1 修正精确包名应优先于模糊候选；该轮 iStoreOS 还暴露 tree 的文件路径为 /usr/sbin/tree。优化 2 从实际包文件清单定位程序，不再假设 bin 目录；三个系统均完成真实 tree 查询、精确版本安装、重复安装、已知文件树枚举、归属、卸载和项目文件保留。Ubuntu 使用 2.1.1-2ubuntu3.24.04.2，Debian 使用 2.1.0-1，iStoreOS 使用 2.2.1-r1。

iStoreOS 另通过正式独立 ks-cli 包的查询、安装、帮助入口、文件清单和卸载；curl/库/包元数据/opkg 配置摘要未变。Ubuntu/Debian 实际安装 Linkspace v0.1.0 并执行 capabilities --json；内部软件卸载因已发布的原安装器无该接口而明确 blocked，未删除程序，也未把此负向结果记为通过。软件查询的追加回归确保不执行业务程序来探测版本，而读取安装者的受管版本布局；未公开产品版本时 availableVersion 为 null。

按照用户允许因产品语义决策暂停的条件，已询问卸载应删除受管版本、仅移除入口，还是缩小验收范围。建议由 zsetup-scripts 所有者提供完整程序卸载并保留用户数据和缓存；见 [卸载范围决策](../architecture/internal-software-removal-decision.md)。当时该问题未答复，相关删除实现与 MS5–MS10 的自动阶段推进停止；确认后的继续实施见下节。其余独立验证已经完成，阶段优化预算使用 2 轮，未虚报为三轮优化失败。证据见 [MS4 结果](multisystem-ms4-results.json)。

### MS4 确认卸载范围后的实施

任务树：zsetup-scripts 所有者入口 → 同字节资源及来源锁 → Kai 调用 → 保护性行为测试 → 三系统真实生命周期验收。验收标准：仅删除完整性核验的受管程序、标记和链接；保留配置、项目数据、缓存和冲突；curl/库不变。

用户已确认删除受管版本并保留数据。所有者新增自包含 remove-managed.sh 候选，Kai 通过 zsetup run 调用带来源摘要锁的资源；不更改公开安装器。所有者 5 项测试及 Kai 8 项契约通过，三系统 MS4 required 4/4 通过。Ubuntu/Debian 真实 Linkspace v0.1.0 功能、卸载、重复卸载和配置/缓存保留通过；iStoreOS 原生包生命周期及宿主 curl 保护通过。此前两轮优化和产品决策等待历史保留，不记为新增失败轮。公开发布不在本轮范围。

## MS5 开发工具与运行时

任务树：通用 mise 执行入口 → iStore 集成适配 → 精确版本/来源及功能验证 → none/project/exec/global 作用域 → 九个 SDK 实测。验收标准：三系统分别验证 Python/Node/Go 精确 SDK，Python 模块和 venv/pip、Node 脚本及 Go 编译运行通过；只读 probe 不安装；默认不改全局；不关闭校验、不回退源码编译。SDK 版本锁在 tests/multisystem/sdk-lock.json。

MS5 结果：未通过，已用满 3 轮优化，按用户约定停止自动推进。Ubuntu/Debian 六个 SDK 的版本、来源、模块/执行、venv/pip、Go 编译及四种作用域通过。首轮为 GitHub 下载连接超时；优化1 增加官方摘要不变的三源引导与隔离网关，Linux通过，iStoreOS缺客户端UCI配置；优化2补充仅容器内侧车端口，Python制品证明和安装通过，但 SSLContext 报 CONF UNKNOWN_MODULE_NAME；优化3添加仅识别固件默认摘要的 Python 进程级配置副本及真实证书/主机名验证器，但保护检查将默认 legacy.cnf 的非注释段也拒绝，故原生 TLS 验证尚未运行。没有第四轮修复。

只读检查确认默认扩展含 legacy_sect 段；现有保护规则尚不能区分“定义段”与“实际启用的 provider 引用”。后续应先追踪有效引用，再判断兼容副本；不能简单跳过所有扩展。此次未更改系统 curl、其库、opkg 配置或系统 openssl.cnf；受保护宿主摘要保持一致。所有本轮容器、网关和网络已清理，缓存镜像保留。公开预设和业务发布均未激活。完整历史与部分通过矩阵见 [MS5 结果](multisystem-ms5-results.json)。

MS4 追加：显式 ZSETUP_INSTALL_PREFIX 的软件查询已修正，公共契约9项通过，所有者资源同字节核验通过。默认安装路径及已验收的卸载行为保持一致。

最终自检：48项多系统离线行为测试全部通过；所有者受管卸载5项测试通过。原生MS5仍失败，离线通过不替代SDK验收。清理复核：本run容器0、网络0；宿主curl/相关库/opkg.conf及openssl.cnf摘要不变。

### MS5 追加授权：Python/OpenSSL 专项修复 1

任务树：冻结镜像只读核实有效引用 → 公共 runtime CLI 红绿回归 → 精确摘要限定默认未引用 legacy 段 → 原生 SDK 与真实 TLS → 系统摘要和清理自检。验收标准：原样默认固件可用；启用 legacy provider、自定义 engine、未知扩展继续拒绝自动转换；显式 OPENSSL_CONF 原样保留；证书与主机名校验有效；系统 curl/库/opkg/OpenSSL 文件不变。原三轮优化历史保留，本次专项单独计一轮，未通过即停止。

只读镜像证据：legacy.cnf SHA256 44772f93dd6faec414b8921b1da7ef5337086dc123a48d5bed6e2b9e4552ce6e，原样 28 字节，仅声明 legacy_sect；生成的 engines.cnf/providers.cnf 均不存在。公共 CLI 加入该默认文件后实际返回 4，修复后通过；开启 provider/engine 和修改默认扩展仍返回冲突，显式配置不改写。48 项离线行为测试通过，原生验收进行中。

专项 1 结果：iStoreOS required 2/2 通过，原生场景 364.129 秒，Python3.13.7、Node22.14.0、Go1.24.1 全部成功，Python 模块、venv/pip、真实 TLS 三项断言、Node 脚本、Go 编译和四类作用域均通过。原系统 OpenSSL 配置、curl/相关库/opkg 配置不变，容器和网络清理通过。

随后用当前增强验收代码复跑 Ubuntu，契约通过，原生 236.301 秒后失败：Python 下载、GitHub 制品证明及安装成功，但新增的 get_ca_certs 非空断言返回失败（helper 11）。这不是已证实的证书库缺失：同一冻结 Ubuntu 镜像中系统 CA bundle 存在，系统 Python 默认加载 120 个 CA；受管 GNU SDK 的实际默认路径和有效信任握手仍需确认。

只读最小诊断实际复现 capath 延迟加载：初始 get_ca_certs 数量0，CERT_REQUIRED/check_hostname 均开启，TLS1.3 正确信任握手收到 TLS_OK，随后数量1。Python 官方文档也明确说明目录 CA 仅在连接需要时加载：[get_ca_certs](https://docs.python.org/3/library/ssl.html#ssl.SSLContext.get_ca_certs)。因此该断言本身过强，不能单凭它判断信任根不可用。check-python.py 和 check-tls.py 中的断言均需改为行为验证，再复跑三系统；本轮没有继续修改它们。Debian 未复跑，历史通过记录保留。

原三轮优化与本次一轮专项已用尽，MS5 整体保持 failed，MS6–MS10 未推进。48 项离线行为测试通过不替代当前原生失败。最终清理审计：本 run 容器0、网络0；缓存镜像保留，宿主保护摘要不变。此次未发布、未修改用户 Agent 技能目录、未连接 Windows。

### MS5 追加授权：CA 验收修复 1

任务树：capath 误判公共回归 → 模块检查去除过强断言 → 实际目录/文件信任、拒绝不受信任证书及错误主机名 → 三系统默认信任库公开 HTTPS 握手 → 九个 SDK 和清理自检。验收标准：不关闭 TLS 验证、不替换系统证书/配置；默认信任、延迟目录信任和负向握手均实际验证；九个 SDK 功能及作用域通过。原三轮优化和专项 1 历史保留，本次追加一轮独立记录。

先通过公开 check-python.py 调用复现目录 CA 初始列表0导致失败，再去除非空列表假设；check-tls.py 同样先复现后修复。模块检查仅报告 CA 路径与已加载数量，不将其冒充握手证明。TLS 检查增加哈希目录真实握手和显式的系统信任 HTTPS 握手，原有不受信任证书/主机名负向保持。49 项离线行为测试通过，原生三系统验收进行中。

CA 修复 1 最终结果：MS5 通过。49 项离线契约通过；当前原生 Debian 418.449 秒、iStoreOS 374.053 秒、Ubuntu 原码复测283.962 秒均通过。初次 Ubuntu 的 TLS 命令60秒超时和整轮 failed 报告保留；同容器公网对照和所选 GNU SDK 的 API HTTPS 对照表明存在站点连通性差异，随后不修改源码、不换探针、不放宽校验的 Ubuntu 复测通过。复测不计新增优化轮。预备的未应用探针目标修改方案已丢弃。

三系统九个 SDK 当前均通过：Python 模块、venv/pip、文件/延迟目录信任、不受信任证书和错误主机名拒绝、默认系统信任库 pypi.org TLS握手；Node实际脚本、Go实际编译、四类mise作用域均通过。系统 curl/库/opkg/OpenSSL 文件未改，最终本run容器0、网络0。原三轮优化、专项1失败和本次CA修复1的历史分别保留，不改写为一次全绿。按原授权自动进入 MS6。

## MS6 项目依赖

任务树：项目公共CLI → npm锁/venv-pip/精确mise uv/Go modules → 来源识别与原生错误保留 → 冻结样例和失败场景 → 三系统实测与自检。验收标准：三系统各四类依赖，共12个正向用例，每个在cold/repeat两个新项目目录、客户端缓存运行；实际导入/执行、既有锁和全局配置不变；显式npm新增仅更新预期manifest/lock；缺SDK、锁不匹配、依赖不存在、缺原生库和网络失败有真实断言。公共CLI/目标程序/项目文件是MS0已冻结的验收边界。

已完成11项公共依赖CLI契约的逐项红绿实现，含真实离线venv和pip重入；所选uv来源和版本校验、Doctor只读预检、Go sumdb保留、来源提示不冒充加速。包元数据与哈希取自npm/PyPI/Go校验服务及uv官方GitHub发布，冻结于dependencies-lock.json。pyzbar实际导入需要libzbar，用于缺原生库场景。新Skill结构、Bash和实验室Python语法检查通过。原生场景实现前公开MS6入口明确失败（未实现），不计实现后优化轮；接下来运行首轮完整验收。

MS6 初次原生结果：Ubuntu 852.145秒后失败，npm/pip的cold和repeat四项实际导入/运行及锁不变通过；uv已安装，但mise exec uv会停用之前Python环境，下一层缺python，helper返回4。Debian刚进入前置步骤时停止旧输入，原生测试收到取消信号后清理成功；iStoreOS未执行该旧输入。本run容器0、网络0，没有把取消或未跑记为通过。

优化1：外部mise协议回归先复现44，再改为同一次mise exec显式选择Python和uv，回归通过。自检还用200KB真实JSON锁文件复现参数长度错误，再改为jq直接读文件；源码不再通过单个argv搬运整份锁。依赖CLI契约13项通过。UV默认后端实际为Aqua，尽管安装缓慢，本次已成功，未误改后端，也未关闭任何验证。下一轮重新执行完整三系统矩阵。

优化1结果：未通过。Ubuntu的uv前置安装超时（600秒，整场景1137.676秒）。Debian 521.464秒：八个依赖运行、UV锁生成/冻结同步、npm显式添加全部通过，证明Python/UV共同选择修复有效；锁不匹配负例因999.0.0根本不存在而先报ETARGET，未触及预期EUSAGE。iStoreOS 213.047秒：Node制品SHA不匹配，正确停止安装；期望6b50f327...、实际12bb782c...，未绕过。

优化2：锁负例改用已经实际安装验证过的6.0.0与锁7.0.0相冲突；汇总独立负向结果，保留各SDK/UV前置日志和失败制品的有界数据诊断。原站SHASUMS256.txt仍给出同一6b50f327...；同一URL成功轮网关55537378字节，本次28266496字节，推断不完整传输，尚未定位具体负责组件。KSpeeder干净源码d3f62f8的现有HTTP断流测试本轮通过，未修改或发布KS代码。下一轮保留版本、期望摘要和全部验证策略，使用全新沙箱及网关重试。

优化2结果：未通过。Ubuntu Go SDK网关502，上游dl.google.com连接超时（场景345.07秒）；Debian 931.622秒，全部八个实际依赖运行、UV锁同步、npm新增、全局配置与系统Python不变通过，缺SDK/锁冲突/依赖不存在/缺libzbar四负例通过，网络负例返回正确1但pip默认日志只显示无候选包，未显示底层连接拒绝；iStoreOS 286.926秒，Node重新下载校验通过，Go目录API失败后fallback缺Git。后续原站诊断遇到临时DNS失败，没有获得可复用完整SDK fixture，未预热或恢复任何SDK。

优化3（最后一轮）：网络负例启用-vv以保存底层连接拒绝证据；隔离Git前置小测试实际刷新签名索引后安装git/git-http 2.50.1-r1，HTTPS传输返回预期连接拒绝128，curl/libcurl/zstd/OpenSSL库及配置摘要不变。完整场景增加原生包预检，拒绝升级任何已有或受保护包。新增KAI_GO_GIT_METADATA=required公共接口回归先失败后通过：只读Doctor/Explain提供安装进程的Git环境，保留客户端凭据隔离和端口，不写全局Git配置，原退出码保留。63项离线行为测试通过。下一步完整三系统自检；若仍未达成，按用户三轮上限停止。


优化3最终结果：未通过，按三轮上限停止，未进入MS7。63项离线行为测试和当前MS6的13项依赖契约通过。Ubuntu完整817.699秒、Debian完整1298.778秒均通过：各八个实际依赖运行、UV锁生成/冻结同步、npm显式新增、五类原生失败场景，以及全局配置/系统Python保护均满足验收。Debian Node下载缓慢、UV请求502后由原生重试恢复，未改变版本、校验或超时策略。

iStoreOS 256.415秒后失败：原生Git前置安装和保护摘要检查、Python与Node安装均通过；Go Git环境计划校验使用jq test()，固件自带jq未编译ONIGURUMA，返回“match/test/sub and related functions are not available”，helper返回4。尚未运行本轮iStoreOS项目依赖用例，不将其记为通过。此为已复现的精简jq兼容问题，不是系统curl故障。只读盘点还发现npm来源分类和Linux mise引导镜像检查使用同一可选特性；后两处是静态风险发现，未冒充本轮原生失败。

当前完整结果、各目标部分结果、原始日志摘要和历史失败均归档于multisystem-ms6-results.json。最终清理复核：本run容器0、网络0、宿主curl/相关库/opkg.conf/OpenSSL配置摘要不变；实验室分区可用20.61GiB。额外保留609259520字节GNU SDK归档，SHA256 8feaca978aa40b3423f8104b352682282d86a6f535ba8d4516474b665dae2b16，验证Python/Node/Go版本及功能入口、uv版本；不含依赖缓存/项目/全局配置，位置在私有实验室状态中，本轮未恢复或消费该归档。未连接Windows、未发布或修改用户Agent目录。

下一步建议范围为“一轮iStoreOS精简jq兼容性专项”：通过可用的JSON基本运算或Bash验证消除上述可选正则依赖，以真实精简jq执行公共接口回归，保留环境键白名单、NUL拒绝、来源识别与TLS保护，再复跑iStoreOS并执行相关Linux回归。此仅为待授权范围，本轮没有实现第四轮修复。MS7–MS10保持planned。


### MS6 追加授权：zsetup 受管 jq 专项 1

任务树：官方制品锁与所有者安装器 → jq-independent引导/桌面入口 → Kai按功能选择 → 保护性CLI回归 → 三系统实际安装/依赖验收 → 自检与清理。验收标准：安装器不依赖jq，原生zsetup SHA256/size校验，JSON/regex/Unicode实际通过，重复安装和卸载保护，全局/系统jq/curl/库不变；Windows/macOS离线分支明确区别原生待验。公开安装索引不激活；候选同字节资源从zsetup-scripts同步，Kai不复制维护安装策略。本专项单独一轮，原三轮失败保留，最终未达成即停止。

截至实现自检：所有者7项行为用例、Kai新增3项以及完整66项离线行为测试通过。所有者全量检查初次因新目录超过已有128条上限而失败，调整为首轮五类Linux目标及桌面共126条后重跑；没有放宽原生协议上限，未改变其他应用目录记录。原生完整验收尚未执行，不以离线结果替代。


专项1实现自检更新：所有者9项、Kai完整67项离线行为测试通过；新增目标平台不匹配时在安装前停止的公共回归，避免Windows请求在Linux安装。所有者第一次全量检查在发布包阶段暴露单应用仅允许一个脚本的限制；改为jq专属的shell入口与原生PowerShell桥接，打包器保留其他应用原约束。对应发布包回归通过（源字节/摘要、历史、可重复性、不可变冲突）；全量再次运行中。无PowerShell解析器，解析/Windows内核与macOS原生仍待验。

独立原生jq检查：Ubuntu官方源安装1.8.2、功能、重复安装及系统保护通过；Debian官方源原生下载超时15，批次清理后结束，未绕过SHA；两个候选公共镜像403，未登记。随后通过已授权的独立KSpeeder网关remap API获取HTTPS地址，Debian实际制品SHA256 b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f，与官方锁相同，DNS映射127.0.0.1；iStoreOS公开ensure jq实际完成无受管jq的引导、功能检查和重复复用，同一制品SHA匹配，系统jq/curl/相关库/配置摘要不变。安装器下载仍完全由zsetup执行，网关不由安装器安装或启动。

接下来执行本专项一次完整MS6三系统矩阵。保留前述微测试的网络失败和打包自检失败；这些结果没有冒充完整阶段通过。镜像、HOME、项目及SDK均重新创建，不消费已保留的SDK归档。


受管jq专项1最终结果：jq功能验收通过，但MS6整体仍未通过。所有者9项、Kai完整68项离线测试通过；所有者全量check.sh通过，包含既有安装器和包发布回归。jq本地候选安装器、制品锁、Windows PowerShell到Git Bash桥接及Kai同字节所有者资源已实现，三个系统实际jq1.8.2的版本、JSON/正则/Unicode、重复调用及系统原jq保护均通过。实际x64制品SHA256为b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f。桌面仅Linux上的安装分支协议fixture验证，无PowerShell解析器、无原生桌面声明、未连接Windows。公开zsetup install jq索引尚未激活。

完整MS6矩阵：契约13项通过；Ubuntu953.640秒、Debian856.357秒后，均在uv安装的600秒命令上限失败，受管jq及Python/Node/Go前置均成功。uv日志包含浏览器release URL的HEAD502及下载阶段；当前队列未运行依赖项目正文，历史功能通过结果保留但不替代当前结果。只读核对原生ks-cli Explain的三个替换模式，不覆盖api.github.com；固定版本上游Aqua源码在浏览器HEAD失败时可回退API制品URL。该回退是候选解释，当前进程尚未记录完整请求链，不能写为已确认根因。源代码：[Aqua](https://github.com/jdx/mise/blob/v2026.8.14/src/backend/aqua.rs)、[GitHub选择器](https://github.com/jdx/mise/blob/v2026.8.14/src/github.rs)。

初次iStoreOS0.188秒在宿主保护探针失败：宿主没有jq，新增探针错误地对空路径求摘要。公共Lab CLI通过外部SSH/shell fixture先复现再修正，明确记录jq存在/摘要或不存在；不向宿主安装jq。此次仅修正验收测量，没有修改任何产品helper或UV策略，原失败记录不覆盖。随后iStoreOS补测259.773秒，jq与Python通过，Node原生返回1：期望6b50f327...，实际d69c88c2...。网关admin_proxy记录38985752字节，先前成功制品55537378字节，推测传输不完整，但具体责任组件未定位；Mise已清理失败文件，未获得gzip验证样本。没有采用新摘要或关闭校验。该后台原有可选签名缺失警告原样保留，不冒充签名通过。

本专项停止：原MS6三轮优化历史及本次专项均已保留，MS7–MS10仍planned；后续下载链修复需要新授权。最终清理本run容器0、网络0，宿主jq前后均不存在、curl/相关库/opkg.conf/OpenSSL配置摘要不变，分区可用20.61GiB。缓存镜像与既有SDK-only归档保留，本轮未恢复该归档。没有公开发布、没有修改用户Agent目录。最终机器记录见multisystem-ms6-results.json。


### MS6 追加授权：下载链稳定性与完整性专项

任务树：复现UV HEAD失败/API回退和Node归档截断 → 公共协议失败回归 → 所有者最小修复 → 本地候选摘要锁 → 三系统MS6验收 → 自检清理。验收标准：失败路径可复现；冻结SHA和TLS不变；系统curl/库/jq/配置不变；当前三系统必需用例通过才能进入MS7。最多三轮优化，保留所有历史失败；没有公开发布或Windows连接。当前为诊断阶段，尚无产品修复或原生通过声明。

专项优化1：KSpeeder公共HTTP回归复现源站HEAD502时未尝试可用admin_proxy，修复后downloadcmd全套通过。按所有者AGENTS要求分开本地提交测试cce3c46与实现9532a64；无推送。候选完整commit9532a6477b1b8ec69455277341beb12ac46ba7d3，二进制SHA256 4c66e1dac6116f2d395de3e632d63c7db9d691b51183f2adbe34d4b0770bd6ac，仅隔离实验室。Lab外部候选入口在连接前校验SHA、启动后核对capabilities源码commit；新增回归先失败后通过，完整69项离线测试通过。

原生补充诊断：同一Node源实际取回55537378字节，冻结SHA6b50f327fd5053b5e4ba67de4bf93aa23653d8a9de39bd6f905f839069c7933d与gzip完整性通过；没有确认此前间歇截断的责任组件，也未替换摘要。UV精确版本调试日志显示HEAD先502、重试200，此次GET走浏览器地址而非API；诊断刻意使用25秒HTTP上限，GET在等待响应时失败，不能冒充原180秒策略的验收结果。日志原件保留在仓库外。优化1候选按原180秒策略验证中。

优化1原生结果：UV在原180秒策略完成21291955字节，原生Mise使用GitHub API digest校验、解压与安装通过；Node再次复现HTTP200/curl0但gzip1，43241472字节、SHA4623961897e7319379955c432d96c2783474cd5e30f2fd22257666ff163eac4c。失败归档已随隔离环境清理，保留日志/响应头摘要；本轮未通过。

优化2：先以公共Router原生HTTP和真实TinyGo/workerd测试分别复现截断EOF。PathHub io.Copy错误处理修复后Go全套通过，但真实workerd的raw JS未知长度流仍会对HTTP客户端表现为正常EOF，专项未通过。尝试的SDK CloseWithError接口未覆盖raw JS透传路径，已移除，workers依赖仓库保持干净；没有宣称线上Worker已修复/部署。

优化3：KSpeeder Node正式版本tar.gz全量GET增加有界落盘、gzip trailer/CRC完整性检查，再返回原字节和实际Content-Length；Mise原SHA/签名策略保留。两个并发槽，每个压缩128MiB、展开512MiB限制；请求结束清理临时文件；Range与其他路由不混用此校验。公共回归先复现截断/CRC损坏仍HTTP200，修复后完整downloadcmd通过；管理入口相关测试通过。候选e7d3bbf6bbf2180780d2594d9707ae49afaa8bea，SHAe5d3e24bfb8d3b83d2168aeb780c48cdf857a50a602636d90d5c7d27063a9a4d，仅实验室使用。开始MS6必测矩阵，先iStoreOS；达到三轮上限，不追加第四轮。

优化3 iStoreOS完整MS6通过601.898秒：受管完整jq及Python/Node/Go/UV-musl均完成；npm/pip/uv/Go冷缓存和重复共8个项目实际运行、npm显式新增、UV锁生成/冻结同步、五类负向、全局配置和系统Python保护全部通过。Node网关返回55537378字节；原生Mise校验/解压及功能检查通过，未采用损坏摘要。客户端依赖缓存每项目全新，不复用保留的SDK归档。宿主curl/库/opkg/OpenSSL/jq存在性及摘要保护通过，专用容器/网关/网络清理通过。Ubuntu/Debian正在同候选复测，阶段整体仍in_progress。

专项优化3最终：MS6通过。Ubuntu466.290秒、Debian581.395秒、iStoreOS601.898秒均完成当前全部必需用例；依赖契约13项、完整离线69项通过。每系统八个实际项目运行、五类负向、锁文件和全局/系统保护均通过。原始三轮MS6失败与jq专项失败、下载专项1/2失败均保留。下载专项3的通过限定为当前KSpeeder网关保护及MS6功能边界；真实workerd未知长度raw JS流错误的HTTP EOF诊断仍失败，没有将该上游平台路径写为已修复或已部署。最终本run容器0、网络0，宿主保护不变。自动进入MS7。


### MS7 下载加速

任务树：通用加速入口（文件/Git/Docker与SDK/依赖委托） → 只读Doctor/Explain → 同实例同窗口的metadata/index与artifact证明 → 三系统真实通道及连续开发流程 → 私有Docker daemon固定digest → 服务/能力/端口/DNS/TLS/摘要/直连/窗口负向 → 自检清理。验收标准遵循架构计划MS7的七项；客户端功能、校验与实际路径分别判定，必需用例不得以pending/skipped替代通过。Docker不接触宿主socket/config/data-root；桌面只做离线契约。最多三轮优化。使用skill-creator规范新增自包含通用skill，沿用已确认的公开CLI/原生程序协议/目标文件/Transport测试边界，先失败测试再实现。

MS7初始垂直实现：新增通用accelerate.sh文件校验/排他激活、只读Doctor/Explain、固定commit Git及固定digest Docker入口；evidence.sh/jq校验真实实例、窗口、监听端口、TLS、独立内容摘要及metadata/artifact。当前九项加速接口测试通过，上一轮全量77项通过（Docker新切片后待再跑全量）。KSpeeder新增TLS根响应观察download-observation.v1，记录实际响应SHA/字节/UTC/nonce，查询参数省略；公共HTTP先红后绿，downloadcmd及管理入口相关测试通过，候选1bb390970c09f4d94630932c2c37410f40868a58，SHA0d0f9bb36e81f4b2c135c9e085a92c755326bdf9d6836f56f991f4a433012efb。

独立Debian原生文件102字节SHA e8a0afb734fbdfff5b2ffd5074a5a12252d824d54192c3c2027cd3a0bf7856b4通过，native selected=admin_proxy及同实例TLS5443响应SHA匹配。Git实际固定7fd1a60b01f91b314f59955a4e4d4e80d8edf11d/tree b4eecafa9be2f2006ce1b709d6857b07069b4608通过，客户端TLS证书校验OK，服务有info/refs和git-upload-pack实际响应；尚未冒充完整MS7窗口清单验收。专用iStoreOS ROM daemon 27.3.1以私有Unix socket/data-root和vfs启动通过，SYS_ADMIN及AppArmor unconfined、privileged=false；首次未捕获stderr导致诊断不足，补日志定位/run软链接目标/tmp/run未初始化，仅在该容器入口初始化后通过。未挂宿主socket、未改宿主配置，三项微测试清理通过。尚未执行镜像pull或MS7完整矩阵，优化计数仍0。

MS7原生Docker切片通过：专用daemon实际pull固定d1a8d0a4...并inspect，manifest1023字节、config577字节、layer2415字节均由当前同一TLS实例观察，响应SHA等于各OCI标识；native daemon debug只显示从registry.linkease.net:5443拉取，无该内容的canonical endpoint fallback。以实际target clock开始/结束、原始客户端日志SHA和独立固定OCI标识构造清单，公开evidence.sh返回confirmed，包含metadata及两个artifact匹配，未拿客户端成功代替证明。真实Git固定commit/tree及info/refs/upload-pack通过，旧微测试尚未包含独立target clock窗口，完整矩阵将补齐。当前完整离线78项通过，skill quick_validate通过。Mise固定2026.8.14设置源已核对always_keep_download，可仅在新鲜实验室进程保留已校验归档用于客户端/网关摘要比对，不作为复用SDK或关闭校验的方式。来源：https://github.com/jdx/mise/blob/v2026.8.14/settings.toml 。仍未执行MS7完整三系统通道矩阵。


MS7首次完整原生自检：Debian511.266秒，十条通道九条通过（文件/Git/Docker、Node/Go SDK、npm/pip/uv/Go modules）；八类负向全部通过，原有依赖功能、锁和系统配置保护通过。唯一失败为Python预编译版本索引仍直接请求mise-versions.jdx.dev，归档实际经网关、原生校验和功能检查均成功。初始报告因缺metadata错误地把contentValidation标为failed；该报告原样保留，后续测量区分内容成功与缺加速证据，不放宽索引要求。外部原件已独立复制，避免下轮覆盖。

优化1：公共CLI Explain与真实HTTP gzip索引回归先复现缺少路由，测试单独提交dc9c0e1；所有者25d55cf08ab08ec8b8e3701e3cd1b62f8022eae5补充/tools/索引路由与route.mise-versions.v1协商，不改写/api/遥测或其他主机。ks-cli internal/app全套、downloadcmd/domainfold全套及服务能力测试通过；候选客户端/网关分别SHA66a1317e81e169240befa8eb11ed63c2844f2850631869643cdf4d1beb0ad6f1和44e944d0f71da8c73ec7906a58c0f0d9c9072d7b2b788fc3dc5fa3c4a293509f。候选均仅上传隔离工作目录，不替换系统客户端。Lab候选客户端入口先红后绿，连接前校验源commit和SHA，目标再次校验SHA与原生版本commit；完整离线79项通过。

优化1原生自检11.230秒失败：测试代码使用iStoreOS镜像不存在的printenv，尚未进入新路由验收。计入失败轮次，不伪装为产品通过。优化2只把PATH读取改为现有POSIX shell内置printf，Lab七项契约及MS7九项契约通过，开始同字节候选的iStoreOS完整复测。增加真实错误端口npm调用及原生direct下载分类，与已有错误日志端口/直连清单拒绝用例分别记录。原生桌面仍pending，未连接Windows、未发布。


优化2结果：iStoreOS完整876.365秒通过，十条通道与十项负向全部通过，原先两个Node截断均被502拒绝、原生重试最终取得完整原始SHA归档。Ubuntu535.969秒，十条加速通道全部通过；额外的“公网直连成功”探针在files.pythonhosted.org的5秒原生连接阶段超时40，尚未运行最后能力/TLS fixture，整轮failed，Debian尚未复测。系统保护与清理通过，失败原件和两目标证据已独立留存。

优化3（最后一轮）只修正负向测量：直连分类使用独立、私有namespace的loopback HTTP origin，实际ks-cli download --mode=direct必须成功并匹配固定SHA bc27e67ccaf63a1101094e22486b182f4ab2b359c615f9199fd0f502e2978f68；生产公共文件助手仍仅允许HTTPS。TLS拒绝仍用独立的不受信任HTTPS证书真实测试，没有通过关闭证书验证恢复业务下载。旧fixture先在公开原生调用边界因内容SHA不符而失败，新fixture三系统微测试均通过能力缺失、直连内容和TLS拒绝三项；原始capture保存于私有证据目录。新fixture SHA aa686404f3e01df5b73cba46be74247da0ac23423077d4541fbe7a384b391e5d，客户端和网关候选与优化2完全相同。完整79项离线回归通过，开始最后一轮完整三系统矩阵；若仍失败，按三轮上限停止，不进入MS8。


MS7优化3最终通过：完整契约及Ubuntu752.790秒、Debian852.739秒、iStoreOS834.160秒全部通过；各十条通道均有独立内容/功能检查与同实例、同窗口、实际TLS监听端口的metadata/index及artifact匹配，共30条原生通道。每目标十项负向均通过，包含真实错误端口和独立本地源的直连分类。iStoreOS Node上游502后由原生重试恢复，原SHA/TLS/签名策略保持，失败事件保留。所有三轮历史及初始失败保留，未宣称raw workerd平台EOF路径已修复或部署。完整79项离线回归通过，清理本run容器0、网络0，宿主保护不变。客户端/网关仅私有候选，未发布、未修改真实Agent目录、未连接Windows。自动进入MS8。


### MS8 软件实际使用

任务树：通用space/search/storage/开发CLI入口 → 已发布Linkspace及明确原生fallback → 已知样本/权限/链接/保护标记 → 实际挂载与持久性事实 → 确切mise uv实际子命令 → 三系统自检清理。验收：范围/数量/超时有界，样本结果可比对，默认不越界/不写源文件或持久索引；overlay/tmpfs/未知挂载不被容量误判；开发CLI来源、版本/help和cache dir通过。最多三轮优化，当前初始实现0。

已核验Linkspace公开v0.1.0元数据、x64制品SHA ce5f57bf9460c1e3a3e7dfed6a57d992877e854a544e4ecc635c5456fd47ed67/18280632字节，实际version/help及目录查询。非root真实权限微样本返回partial11、保留已观测大文件/中文搜索结果、跳过外部链接；storage plan把本机aufs报告persistent，故安装目录判定独立使用zsetup原生存储事实，不能借此误报安装安全。zsetup原生storage对aufs返回memory_backed=null，对tmpfs=true，对proc未知，均有实际对照。

公开接口先红后绿：当前usage/开发CLI共11项，软件目录共10项通过。含字面参数及--help式文件名、原退出码、范围限制、stdlib真实文件扫描/条目预算、容量与持久性分离、确切mise根/which来源、只读probe及显式install。iStore/OpenWrt只为Linux可移植Linkspace用户客户端开放zsetup来源，架构限已发布三类；mise/ks-cli继续原生包集成。Windows卷API代码与macOS存储路径已实现，当前原生桌面仍待验，不连接Windows。尚未运行MS8完整原生自检。


MS8初始实现自检：usage/CLI12项、software10项、完整92项离线回归通过，两个Skill quick_validate、Bash/Python语法通过。公开MS8原生入口在实现前明确返回未实现（before报告保留，不计优化）。已实现真实非root UID65534扫描，已知大文件/稀疏文件/Unicode/字面选项名/外链/权限、源文件与保护标记、无持久索引配置检查；原生zsetup对数据目录/overlay/tmpfs/proc未知四种存储结论实际测量。UV确切安装/which来源、help/cache dir、同名外部程序未执行、全局选择不变有断言。开始首轮Ubuntu完整原生验收，优化计数0。


MS8首轮Ubuntu157.442秒失败：已发布Linkspace版本/安装/SHA、真实非root空间/Unicode/字面选项词/权限/外链、四类实际存储、确切UV安装/help/cache dir、缺工具只读负例均通过；最后“HOME必须完全无文件”的保护断言失败，初始日志未带断言名称，原始报告保留。公开发布版本机真实查询复现0字节.config/fssearch-cli/storage-locks/<hex>-scratch.lock；这是扫描协调锁，没有业务配置或持久索引。

优化1只修正验收测量：允许这个确定目录/命名且0字节的协调锁，任何其他HOME文件仍失败；保护标记、源文件、global mise选择前后摘要及HOME剩余文件列表完整记录，并给断言加明确原因。不改Linkspace产品，不放宽配置/索引或源文件保护。Lab七项通过、Python语法通过，开始完整三系统自检，优化计数1。


优化1结果：Ubuntu239.680秒、Debian256.544秒完整通过。iStoreOS60.654秒准备阶段失败，受管jq已成功；实验室错误假设其core位于~/.local/bin，实际owner shell bootstrap保存在ZSETUP_ROOT/rescue/0.5.1/zsetup，没有注册用户命令。没有进入该目标Linkspace与扫描正文，failed保留。

优化2：新增公开tool.sh回归先复现unavailable，后从固定owner rescue路径只读发现冻结版本，先匹配官方锁SHA再执行--version；篡改缓存返回conflict17，未执行、未覆盖、未创建软链接。Lab消费probe返回的实际路径；不再猜固定bin目录，不新增OpenWrt安装器。完整93项回归、Bash/Python语法通过。首轮从iStoreOS复测，优化计数2。

### MS8 optimization 2 result and final optimization 3

Optimization 2 passed all 93 offline contracts, including frozen-hash verification of the real owner rescue core. Native iStoreOS stopped before product usage because the isolated KSpeeder gateway did not become healthy in the original startup budget (109.554s case). A minimized real-process reproduction found the process running and TCP accepting connections while the admin HTTP server was not yet serving. The captured goroutine stack places startup in certificate retrieval (`cert_fetcher.go`, `tunnel.linkease.com`), and an independent verified curl request to that endpoint timed out. No system curl or TLS policy was changed. The scenario receipt records zero completed positive/negative cases; the reused evidence folder had a prior-run gateway log and is archived, not attributed to this attempt.

Optimization 3 retains startup failure state/logs under invocation-specific names before cleanup and uses a bounded 180-second startup deadline. Seven public lab-controller contracts passed. Native iStoreOS is run first, then Ubuntu/Debian if it passes. This is the last allowed optimization round; any remaining required failure stops MS8 and leaves MS9/MS10 planned.

MS8 optimization 3 passed on all required fresh targets: iStoreOS 127.107s, Ubuntu 290.533s, Debian 214.659s, plus each public contract gate. Each target passed eight positive and five negative real-product cases; iStoreOS reused the SHA-verified owner rescue core. Final audit: no owned containers or networks remain, host curl/SSL/package-policy guard unchanged. Certificate origin recovered during this run; the waiting-budget change is not claimed to repair that upstream outage. Automatically advance to MS9.

### MS9 task tree and acceptance

Mac: x64/arm64, native Homebrew/internal sources, HOME/PATH, launchd and real Bash 3.2. Windows: structured WinGet adapter, Git Bash bootstrap, native executable and explicit batch bridge, Python Scripts/venv, drive/backslash/Unicode/space paths, scoped MSYS conversion and Docker POSIX arguments. Execution boundary: literal argv, script transport, original failures via external executor/module fixtures. Acquire source/digest-verified portable PowerShell and actual Bash 3.2 in the task SSD directory when possible; parse executable PowerShell, run shell syntax and behavior contracts, retain unavailable parsers explicitly. Acceptance: complete positive/negative desktop contracts and existing regressions; missing published artifacts are unavailable rather than placeholders; Mac/Windows native remains pending and no Windows target connection. Initial implementation plus at most three optimization rounds before MS10.

MS9 implementation: structured WinGet source/exact-version lifecycle through the public PowerShell module; explicit batch bridge with shell-expansion input rejection; child-only Docker MSYS policy; source-bound Windows Node/npm JS and venv Python/pip with validated existing KSCLI Explain environments; native path conversion; WSL launcher rejection before execution; structured first Git Bash installer failures; Mac native owner/launchd fixtures. Real PowerShell parser/external-module tests and Bash 3.2 syntax/behavior executed. Initial self-check: all 18 desktop contracts passed in 12.165s; 111 full offline tests had one fixture failure caused by task-built Bash shadowing the system Bash in a merged-/usr ownership case. Optimization 1 scopes that fixture to its intended system program and updates the skill instructions. No native desktop claim, Windows connection or global tool installation.

MS9 optimization 1 passed: full 111 offline tests (29.236s), all 18 desktop contracts (12.166s), actual PowerShell 7.4.21 parser/executor and Bash 3.2.57 checks. Adapter implementation and offline contracts are complete; macOS and Windows native kernels, PowerShell 5.1 and real WinGet/Windows API runtime remain pending. Automatically advance to MS10.

### MS10 task tree and acceptance

Declare ten platform/mode presets and the frozen six common IDs, with Ubuntu/Debian canonical sources. Compose from canonical packs; retain native-only legacy script interfaces as non-SKILL resources and map four retired primary IDs to one common implementation each. Bundle and hash-check the iStore runtime adapter so flattened presets work away from the source checkout. Synchronize Kai canonical snapshots/source locks/routing without third-party Transports. Verify dry-run/install/upgrade/remove/conflict/unrelated-file preservation only in task temporary directories. Native acceptance is 3 systems x 2 modes x 3 journeys = 18, plus fresh environment repeats and associated MS7 channel evidence. Build two deterministic reviewable candidate releases; no publish/deploy/real Agent config writes. Required and existing regressions must pass, pending native desktop scope remains explicit. Initial self-check plus at most 3 optimization rounds.

MS10 initial distribution/offline integration: 116 public offline contracts passed. The complete legacy baseline found stale direct remote composition, old layout counts and eager Markdown references; optimization 1 redirects the legacy remote entry to the declared preset, migrates reviewed counts from 20 to 22 system skills, retains all previous size budgets, and moves conditional evidence to data/. Automatic discovery remains available for all six common skills; 13 previous user-task entries minus four retired plus six common gives 15 entries (2556 bytes), within the original 3072-byte catalog budget. An accidentally normalized literal CR test fixture was restored byte-for-byte from HEAD. No production curl/library changes. Native MS10 Ubuntu started; full Kai source-hash and consumer verification follows the completed canonical sync.

Optimization 1: all 15 legacy baseline groups, all 117 offline tests, six distribution contracts (including actual committed legacy install → protected upgrade → clean uninstall), real consumer routing and all target-session direction/transport checks passed. Two candidate builds produced the same 20 byte-identical archives, with explicit sourceState=worktree; originals retained. Independent skill-creator forward-testing reproduced a missing iStoreOS/OpenWrt zsetup provider when full jq already exists and no rescue core exists. Optimization 2 adds a public failing regression first, then reuses the existing HTTPS/SHA/size/version checked Linux core bootstrap for those two Linux targets; native mise/ks-cli owners remain unchanged. The iStoreOS native journey now checks independent core creation before full-jq bootstrap. Final native acceptance and candidate builds must use the new bundle, rather than crediting the old bytes. No new installer family or system curl upgrade.

Optimization 2 native: final candidate iStoreOS 527.468s and Ubuntu 701.331s passed all six required plus three fresh-repeat journeys each. Independent core install returned installed on all three fresh iStoreOS environments; factory curl/SSL and host curl/libcurl/zstd/jq/opkg policy unchanged. Debian on-device passed all three journeys, then remote capture failed before bootstrap: jq 1.6 treats the measurement variable $end as a reserved keyword. Historical failed result and receipts retained. Optimization 3 (last) renames only the target JSON collector variable, not product skills or preset bytes; validate actual pinned SSH capture on all three native parsers, then rerun Debian fully. Existing final candidate digests remain unchanged and the valid iStoreOS/Ubuntu proofs are retained; no fourth optimization if a required gate still fails.

MS10 optimization 3 passed. The minimized actual Debian jq-1.6 Transport probe reproduced the reserved-variable failure before the fix; Debian jq-1.6, Ubuntu jq-1.7 and iStoreOS jq-1.8.1 all passed the corrected real pinned-SSH capture, including Unicode/space/empty/shell-looking argv, original exit37 and stderr SHA. Full 118 offline tests (39.083s), all 11 contract groups and the unchanged 15-group legacy baseline passed. Debian complete rerun 639.592s passed six required plus three fresh-repeat journeys; valid identical-archive iStoreOS527.468s and Ubuntu701.331s results from optimization2 are retained, not falsely attributed to a new run. All 18 required +9 repeat journeys match the final archive source/tree digests. Nine gateway instance IDs are distinct; current-window pip metadata/artifact/TLS proof and actual project execution pass. MS7 proof is linked against currentCandidates, separate from older historical gateway candidates.

Final audit: 0 owned containers, 0 owned networks,22128656384 available bytes, unchanged migrated Docker root and unchanged host curl/libcurl/zstd/jq/opkg/SSL snapshot. Each iStoreOS cycle installed the independent core and passed factory curl/SSL guards. Two final builds produced20 identical archives across10 presets; worktree provenance and candidate-only status explicit. Candidates and public evidence retained under ignored release/ms10-candidate and release/ms10-evidence, with no SSH credentials/config copied. All milestones0–10 now passed within the declared fixture/container scope; macOS/Windows native and untested architectures/services remain pending. No Windows connection, public release, production deployment or real Agent-directory change.

Additional owner checks: Skill|Capability Agent tests passed after a process-only Go proxy download retry (go.sum unchanged). Six top-level Boot tests (eight failure events including children) fail identically in the current tree and an isolated git archive of the original Reasonix HEAD; passed-event counts also match. These pre-existing session-persistence/lease failures are preserved separately, not claimed green and not changed by this task. See additionalOwnerRegression in multisystem-ms10-results.json.
