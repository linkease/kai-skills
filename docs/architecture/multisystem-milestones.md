# Kai Skills 多系统实施里程碑与验收目标

状态：实施中。逐阶段结果见[执行记录](../verification/multisystem-execution.md)与[机器可读状态](../verification/multisystem-status.json)。阶段验收只依据实际测试结果，不能用计划目标替代通过证据。

目标是让软件搜索、安装、下载加速、开发环境、项目依赖和软件实际使用共享任务流程，由平台适配处理系统差异。首轮运行验收覆盖 Ubuntu、Debian、iStoreOS；macOS、Windows 同步实现完整适配，其中 Windows 暂不连接真实设备。macOS 的原生验收需要独立的 macOS 执行环境，Linux Docker 不能替代。

本计划中的“完整适配”指首轮冻结的能力范围；底层产品没有对应平台产物、摘要或服务能力时，必须提供可测试的不可用结果和正确下一步，不能生成无效安装命令。这样的负向测试通过，不表示正向功能已经可用。

## 产品与源码职责

| 归属 | 职责 |
| --- | --- |
| common System Pack | 软件、开发环境、项目依赖、加速、空间与文件等通用任务流程 |
| 各平台 System Pack | 软件源、包管理器、服务管理、Shell、路径、存储和运行时环境的适配 |
| Transport | 目标身份、连接、上传、执行、超时、取消；不决定系统维护策略 |
| zsetup 与 zsetup-scripts | 内部软件安装及已有下载、校验、存储事务；不在 skills 内复制下载器 |
| mise | SDK、运行时、开发 CLI 的安装和版本选择 |
| npm、pip、uv、Go 等原生工具 | 项目依赖、锁文件、解析与执行语义 |
| ks-cli 与 KSpeeder | 已支持协议的加速、能力探测与错误契约 |
| linkspace 等产品 | 空间查询、文件搜索等实际功能 |

源码继续在 `components/` 唯一维护；`platforms/` 为生成产物。新增通用能力后同步调整生成器、安装预设和 Kai 的来源锁。保留 iStoreOS 专属的 UCI、procd、LuCI、iStore 集成；不向普通 Linux 注入 mise-exec、iStore HOME 或 UCI 规则。

计划使用的通用 Skill ID 是 `kai-software`、`kai-dev-environment`、`kai-project-dependencies`、`kai-download-acceleration`、`kai-storage-files`，以及按需调用的 `kai-tool-bootstrap`。MS0 冻结实际名称及旧 ID 的迁移映射。每一步最多激活一个主 Skill 和一个当前必要的 helper，跨步骤可以更换 helper。

## 测试环境与证据规则

测试服务器通过仓库外变量 `KAI_LAB_SSH_TARGET` 指定。地址、凭据、SSH 指纹和实际工作目录不写入仓库。SSH 保持严格主机密钥检查，未知或变化的密钥使连接测试失败。

2026 年 10 月 26 日只读预检确认测试宿主为 x86_64 iStoreOS 24.10.1，Docker 27.3.1，4 个 CPU，约 4 GiB 内存；Docker 数据所在文件系统当时剩余约 3.76 GiB。每次执行重新检测，旧数据不作为后续运行的容量保证。

同日经用户确认完成存储准备：清理约 9.84 GiB 的旧性能测试生成数据，Docker 迁至 `/mnt/lighthost-s5-vm/docker`，迁移后所在文件系统可用约 22.88 GiB。报告、复现材料、配置备份和旧 Docker 目录均保留，挂载身份保护及服务状态复核通过。详见[空间检查与授权执行记录](../verification/docker-storage-audit-2026-10-26.md)。这是 MS1 的存储前置条件，不代表容器实验室或其他里程碑已验收。

首轮运行矩阵在 MS0 冻结，建议如下。版本是选定的测试基线，不表示最新版本。

| 环境 | 首轮范围 | 必须保留的事实与限制 |
| --- | --- | --- |
| Ubuntu 24.04 x86_64 | apt、Bash、mise、依赖、软件使用、加速 | 真实发行版镜像，锁定 digest |
| Debian 12 x86_64 | apt、Bash、mise、依赖、软件使用、加速 | 与 Ubuntu 独立运行，不用改系统标识代替 |
| iStoreOS 24.10.1 x86_64 | opkg/is-opkg、实际 iStore/mise 集成、依赖、加速 | 使用可追溯 rootfs 和匹配软件源，检查真实 integration 文件 |
| OpenWrt APK 场景 | 数据库检测与命令选择的 fixture | 没有真实 APK 目标时不声明其安装运行通过 |
| macOS x86_64 与 arm64 | 平台实现、命令计划、路径、工具可用性、离线契约 | 无原生 runner 时，原生功能验收为 pending |
| Windows x64 | Git Bash、PowerShell、原生程序、路径和离线契约 | 不连接 Windows；WSL 单独识别为 Linux 执行环境 |

容器只证明用户态行为。内核模块、真实路由与防火墙、硬件、真实 overlay 持久性、开机启动、宿主 Docker daemon 的安装和重启不计入本轮容器通过项。容器内没有 init/service manager 时，不能以跳过服务测试来宣称 procd、systemd 或 launchd 已验收。

所有验收记录至少包含：源码 commit 与工作树摘要、测试 ID、平台事实、镜像/rootfs digest、工具版本、运行参数、时间、预期结果、实际结果、退出码和脱敏证据路径。临时输出放仓库外；提交到 `docs/verification/` 的记录只包含必要结论和可追溯摘要。

结果分别记录 `implementation`、`fixture_validation`、`container_validation`、`native_validation` 和 `acceleration_validation`。测试用例使用 `passed`、`failed`、`blocked`、`skipped`；阶段有 `passed`、`failed`、`blocked`，不把 required 用例的 skipped/blocked 转成通过。native_validation 可以按平台保持 pending，但必须在支持矩阵中可见。

## 里程碑总表

| 里程碑 | 交付物 | 通过条件 | 依赖 |
| --- | --- | --- | --- |
| MS0 范围与基线 | 能力矩阵、旧 ID 映射、回归基线 | 所有 required 用例有 ID、预期与证据类型；既有失败已定位 | 无 |
| MS1 隔离测试实验室 | 远程 Docker 执行器、环境锁、资源预算、清理机制 | 三系统环境真实可识别，重复运行不污染宿主 | MS0 |
| MS2 执行与平台接口 | 目标事实、命令、环境、结果的统一接口及四平台适配 | argv、cwd、环境、错误、超时、取消契约通过 | MS0 |
| MS3 工具发现与引导 | Bash、zsetup、mise、ks-cli 的按需发现和安装策略 | 干净/已安装/冲突/不支持场景正确，无额外服务副作用 | MS1、MS2 |
| MS4 软件搜索与生命周期 | 统一发现结果、系统与内部软件安装、使用入口 | 三系统完成搜索、安装、实际使用、卸载及失败恢复 | MS3 |
| MS5 开发工具与运行时 | 通用 mise 流程、平台环境适配、安装验证 | Python、Node、Go 的版本、来源和功能验证通过 | MS3 |
| MS6 项目依赖 | npm、pip、uv、Go 依赖安装与运行流程 | 实际导入/执行成功，锁文件和环境作用域符合预期 | MS5 |
| MS7 下载加速 | 文件、Git、SDK、依赖与 Docker 的加速验收 | 冷缓存客户端和网关证据匹配，失败分类正确 | MS1、MS5、MS6 |
| MS8 软件实际使用 | 空间分析、文件搜索、开发程序执行 | 能回答实际任务，结果可与已知样本比对 | MS4、MS5 |
| MS9 macOS 与 Windows 收口 | 两平台完整适配及离线回归报告 | 非空壳实现、分支可执行测试、缺产物结果明确 | MS2 至 MS8 |
| MS10 分发与综合验收 | 预设、消费者兼容、Kai 同步、候选制品与报告 | 必测矩阵全绿、可重现、未验项目显式列出 | MS0 至 MS9 |

Windows/macOS 的实现从 MS2 起随功能提交。MS9 用于集中检查完整性，不用于把平台实现延迟到最后。

## MS0 范围与基线

交付能力矩阵和测试清单，冻结首轮系统、架构、包管理器、运行时、工具来源与平台差异。软件目录、预设目录和项目依赖目录分别建模，避免把 zsetup 的列表当成整个系统的软件目录。

可测试目标：

1. 每个能力列出正向测试、至少一个失败测试，以及适用平台、实现归属和证据等级；不存在只有“支持”二字的条目。
2. 确认 ks-cli 已有普通 Linux 安装入口，OpenWrt 使用对应包管理路径；macOS/Windows 按当前实际产物与摘要登记，不猜测安装地址。
3. 收录现有 catalog、canonical、generated、Transport、安装生命周期、Reasonix 和 iStoreOS runtime 相关测试；基线全绿，或对每个既有失败记录复现命令、原因与修复归属。基线失败不能混入后续成功结论。
4. 旧 Skill ID 逐一标记保留、提取或过渡映射；迁移后不得出现两份人工维护的实现。
5. 至少 30 条路由用例覆盖软件、运行时、项目依赖、下载、存储、系统专属任务；“安装 Python”和“pip install”必须走不同主流程，Ubuntu 不选择 iStore 环境。

MS0 通过意味着范围和判断标准已冻结，不意味着功能已经实现。

## MS1 隔离测试实验室

在指定远程 Docker 宿主建立可重建实验室。执行器读取仓库外目标配置；所有镜像、容器、卷和网络带本次项目及 run ID 的所有权标记。工作目录和缓存使用探测后的持久磁盘，不放在宿主 overlay 或 `/tmp` 内承载大型下载。

可测试目标：

1. Ubuntu、Debian 使用锁定 digest 的真实镜像。iStoreOS 使用来源、版本、架构、摘要明确的 rootfs，实际检测 `/etc/os-release`、包数据库、包管理程序、libc、iStore/mise integration 文件。改名字或复制几个配置文件不能通过。
2. iStoreOS 镜像所需的 iStore/mise 包及其依赖有真实来源和摘要，缺任一必需产物时阶段 blocked，不能退回 fixture 后宣称完成。
3. 每个目标可运行 on-device 测试，也可通过实验室专属 SSH 入口运行 remote-control 测试。端口动态分配，目标脚本中的标记文件只出现在容器内。
4. 默认单目标运行。开始前估算镜像展开、构建层、SDK、缓存和证据空间；试验采用至少 1 GiB 磁盘余量的初始预算，并配置容器内存/进程限额。预算不足返回明确失败，不清理其他工作负载。
5. 取消、超时和注入失败后，只清理本 run 的资源；重复创建、执行、清理两轮成功。宿主保护路径的测试标记及非本次资源清单保持一致。
6. 不挂载宿主根目录或 Docker socket 到普通测试容器。Docker pull 场景使用专用 daemon/data-root；若独立 daemon 需要额外权限，执行器明确记录并限定到该专属容器，不改宿主 daemon 配置。
7. 加速服务使用实验室专属实例、配置、端口和日志。测试容器的 localhost 不是宿主；必须验证实际网关路径。若工具目前只能访问同网络命名空间服务，采用明确配置的 sidecar/同 namespace 方案，不能因访问不到而关闭校验。
8. iStoreOS 复用固件自带 curl、libcurl、证书和下载策略；实验室准备不主动安装或升级 curl，不修改 opkg 下载后端。构建前后核对 curl、libcurl、libzstd、相关包元数据和 opkg 配置的摘要及 curl 版本；宿主机对应文件也必须保持不变。补齐其他必要工具导致上述文件变化时，构建失败，不能通过配套升级系统 curl 来绕过。

真实内核、路由和生产服务变更不属于此实验室创建任务。

## MS2 执行与平台接口

定义小而明确的执行接口，输入包括目标身份、argv、cwd、环境增量、stdin、超时及取消；输出包括原始退出码、受限 stdout/stderr、平台事实与错误类别。只实现现有任务需要的接口，不引入通用脚本语言或第二套包管理器。

可测试目标：

1. Linux、macOS、iStoreOS、Windows fixture 返回正确的系统、架构、Shell、包管理器、用户目录和执行环境；未知值保持 unknown。PATH 上有 opkg 不足以识别 OpenWrt。
2. 参数中含空格、中文、引号、空字符串、`$()`、分号和反引号时，测试程序接收完全相同的 argv，不发生额外命令执行。
3. cwd、stdin、环境增量正确传递；连续两次独立调用不会依赖上一次 shell 的 source。当前项目和当前目标不会被其他会话环境覆盖。
4. 超时与取消停止测试启动的进程树，记录可区分结果；传输失败不能被解释成业务安装失败，原生工具非零退出码得到保留。
5. Windows 适配区分 Git Bash/MSYS、PowerShell、Windows 原生程序和 WSL；Git Bash 不被识别为 Linux，WSL 不使用 Windows 的 SDK 路径。
6. 接口和执行器测试跨真实调用边界验证实际参数与副作用；不得只用 grep 检查源码里是否出现某个字符串。

## MS3 工具发现与引导

实现按任务发现和补齐 Bash、zsetup、mise、ks-cli 的流程。优先复用已安装且版本兼容的工具及其原安装管理者。安装客户端与安装/启动加速服务分别处理。

可测试目标：

1. “干净环境、兼容版本、版本过旧、外部来源冲突、平台未发布”五类场景给出准确命令计划和结果；兼容工具再次检查不重新下载安装。
2. 普通 Linux 实际复用 `zsetup install ks-cli --foreground`，验证命令路径与版本；其安装不启动或安装 KSpeeder 服务。已存在外部命令时保留它并报告冲突。
3. iStoreOS 使用真实 feed 中的包，验证 mise-exec、mise、integration 文件、runtime_dir 和 ks-cli 可用性；不能套用普通 Linux 安装器。
4. macOS/Windows 缺产物或摘要时，返回工具/平台/原因/下一步；已有受信任工具的路径仍能继续执行任务。不拿 Linux 二进制代替。
5. Windows 首次 Bash 引导可以从 PowerShell 或原生入口进入，不要求先有 Bash。路径发现测试排除 WSL 启动器并验证含空格的绝对路径。
6. 下载损坏、版本不匹配、空间不足和取消测试均保留原有可用工具；复用 zsetup 的校验与事务，不复制下载实现。

## MS4 软件搜索与生命周期

统一结果至少包含软件 ID、名称、类型、来源、管理者、平台兼容性、可用版本、安装状态、使用入口与证据时间。各查询仍以系统仓库、iStore、zsetup 自身的目录为权威来源。

可测试目标：

1. Ubuntu、Debian 查询真实 apt 索引和已安装数据库；iStoreOS 查询真实包数据库，并覆盖 iStore 目录、普通系统包和内部 zsetup 软件的区别。
2. 同名软件来自多个来源时，结果不混成一个安装 ID；功能搜索返回有限候选及匹配理由，具体包名不触发无意义的重复选择。
3. 每个真实目标选一个冻结版本或快照仓库中的轻量软件，完成搜索、信息查询、安装、命令功能检查、文件归属查询和卸载；操作只发生在容器内。
4. 每个平台各验证一个系统包和一个适用的内部软件/iStore 应用路径。内部产品不存在时，该正向能力保持 blocked，不用负向测试替代。
5. 不隐式刷新索引；显式 refresh 的写入可见，源不可用、无候选、权限不足、冲突和安装失败均保留原始错误。
6. 重复安装幂等，卸载不误删项目文件；用户修改的配置和外部来源文件不被强制覆盖。需要服务或 Docker 的软件仍由其管理者处理生命周期。

## MS5 开发工具与运行时

从现有 iStoreOS mise 技能提取通用的版本解析、安装、选择和功能验证。普通 Linux/macOS 使用各自的用户环境；iStoreOS 每次独立调用重新进入实际 mise 集成环境。

可测试目标：

1. Ubuntu、Debian、iStoreOS 各完成 Python、Node、Go 的一个确切版本安装，共九个 SDK 正向用例。版本在环境锁中记录，不把历史 workaround 写成永久 latest。
2. 可执行文件来自所选 mise SDK，版本完全一致；仅观察系统 PATH 上的 Python/Node/Go 不能通过。
3. Python 实际验证 ssl、sqlite3、bz2、lzma、ctypes、venv 和 pip；Node 执行脚本；Go 编译并运行小程序。编译产物与缓存写到试验所有的持久路径。
4. 覆盖仅安装、项目选择、临时 exec 三种作用域；全局选择作为显式独立用例。默认任务不修改全局版本。
5. 只读 probe 不隐式安装缺失 SDK；iStoreOS 正确处理 mise-exec 不转发参数的接口，不修改普通系统的 HOME。
6. musl/架构没有匹配的预编译产物时明确失败，不静默安装编译器或转源码编译。候选版本不满足正向用例时重新冻结有可用产物的版本，仍无法满足则 blocked。
7. 验证失败、下载失败、完整性失败、环境未激活与版本解析错误分别报告，TLS、校验与签名不关闭。

## MS6 项目依赖

实现与项目自身包管理方式一致的依赖流程。首轮覆盖 npm、pip、uv、Go；不擅自将已有 npm 项目改为其他包管理器。

可测试目标：

1. Ubuntu、Debian、iStoreOS 各运行 Node/npm、Python/venv/pip、Python/uv、Go modules 四个样例，共十二个正向用例。每个样例有冻结版本与实际依赖导入/执行断言。
2. npm 对既有 lock 使用 ci 并验证依赖；Python 用指定解释器创建 venv 并确认实际 pip/uv 作用域；Go 样例包含真实 require/import，不能仅运行空项目命令。
3. 已有锁文件场景前后摘要不变；明确新增依赖的场景只产生预期的 manifest/lock 变化。系统 Python、全局 npmrc/pip 配置和 go env 不被改写。
4. 先验证冷缓存下载，再在另一目录验证重复运行。缺运行时、锁不匹配、依赖不存在、原生扩展缺系统库、网络失败和项目路径含空格都有断言。
5. 原生依赖工具失败保留原退出码。Git/私有仓库/非 registry 依赖识别为单独下载来源，不假设被普通 registry 加速覆盖。
6. 样例安装后实际运行并校验输出；仅安装日志包含 success 不算完成。

## MS7 下载加速

覆盖当前 ks-cli/服务明确支持的通道。冻结的通道清单是验收输入，不把“brew 元数据可路由”解释为 Homebrew 所有 bottle 已加速，也不把 mise 外层包装解释为其所有 backend 都被覆盖。

可测试目标：

1. 每个真实目标验证 Python/Node/Go SDK 与 npm/PyPI/Go modules 的实际下载；uv 按已支持的 PyPI 通道验证。每条通道记录确切客户端、实际源和服务能力。
2. 文件下载核对内容摘要；公开 Git clone 核对冻结 commit；Docker 在专用 daemon 中拉取固定 digest 镜像并检查结果。不能改宿主 Docker 镜像配置来完成测试。
3. Doctor、Explain 是只读检查，不能隐式安装/启动服务；执行期如需启动实验室专属服务，由试验范围覆盖并在结果中记录。
4. 冷缓存请求同时保留客户端与同一服务实例、同一时间窗的网关证据，证明相应 metadata/index 与 artifact 请求经过网关。
5. 仅客户端成功记为 client passed、acceleration pending；缓存命中、客户端直连、网关内部回源分别分类，不能一概写为加速成功。
6. 服务缺失、能力缺失、端口错误、DNS/TLS 失败、摘要不匹配、客户端直连和错误日志窗口都有负向用例。任何失败都不能通过 insecure、关闭证书/校验或污染全局配置恢复。
7. 准备一个连续的用户流程：安装 SDK、安装项目依赖、运行项目。结果同时给出运行时、依赖功能、加速路径三类结论。

## MS8 软件实际使用

把“安装完成”推进到“任务完成”。首轮实际使用聚焦空间分析、文件搜索、SDK/开发 CLI 的执行；不扩展为任意软件使用知识库。

可测试目标：

1. 在试验目录构造文件树，包含大小已知的普通文件、中文和空格路径、符号链接、无权限目录与外部保护标记。空间分析结果能定位预设大文件，文件搜索返回预设目标。
2. 支持 linkspace 的平台实际调用其已发布程序；不支持的平台使用明确登记的原生方案，结果标注实际工具。不能把原生 fallback 的通过写为 linkspace 本体通过。
3. 默认查询有路径范围、输出数量与超时限制；不会为了查空间扫描整个宿主或自动删除文件。
4. 选择安装目录时返回实际挂载、容量与持久性证据；overlay、tmpfs、未知挂载都有预期结论，不能仅凭可用字节推断持久性。
5. 通过 mise 管理至少一个首轮支持的开发 CLI，验证确切版本、help/版本入口和一个真实子命令；项目运行时不混入系统中的同名程序。
6. 报告包含安装位置、实际使用命令、结果和下一步；无需用户自行理解内部 helper 的组合。

## MS9 macOS 与 Windows 收口

集中核对两平台在 MS2 至 MS8 的实现与通用能力一致。代码不能只有分支、TODO 或固定返回成功。发布物不可用与能力未实现分别报告。

可测试目标：

1. macOS x86_64/arm64 fixture 验证架构选择、HOME/PATH、Bash 兼容性、Homebrew 与内部安装来源选择；服务使用 launchd 策略，不生成 systemctl/UCI 命令。
2. Windows x64 验证 Git Bash 选择、首次引导、原生程序启动、`.cmd` 桥接、Python Scripts/venv、盘符、反斜杠、空格和中文路径。额外覆盖 MSYS 参数转换和 Docker 参数中的 POSIX 路径，不能全局禁用转换来掩盖问题。
3. Windows 的命令计划、脚本传输与错误处理在 mock executor 上执行契约测试；可用的 PowerShell 解析器执行语法/解析测试。解析器不可用时明确记录，不能用文本匹配替代执行测试。
4. Bash 脚本在相应最低支持版本语法检查；共用逻辑执行行为测试；需要 Windows 内核的进程/路径行为保留待原生验证。引入编译程序时才增加对应平台交叉编译，交叉编译不等于运行验收。
5. 无真实 macOS runner 时，macOS offline gate 可以通过，native gate 保持 pending；Windows native gate 本轮按范围保持 pending，不连接 Windows。
6. 缺客户端发布物时正向安装显示 unavailable，已安装客户端的合法执行路径仍完成离线验证；没有产品摘要时不生成可执行下载计划。

MS9 的完成表述必须为“适配已实现且离线契约通过”；只有另行完成原生测试，才能声明对应平台真机验收通过。

## MS10 分发与综合验收

新增 Ubuntu、Debian 的 on-device 与 remote-control 预设；其余现有预设同步消费通用技能。Kai 直接消费 canonical System Pack，第三方 Agent 使用生成预设。

可测试目标：

1. catalog 中每组 platform/mode 恰好匹配一个预设；通用技能只装一次；iStoreOS 专属技能不出现在 Ubuntu/Windows 预设中，Bash 未安装不阻止 bootstrap 技能被发现。
2. 生成器从声明驱动组合，不增加每平台一套人工维护 Skill；`tools/verify-generated.sh` 通过，打包后离开源码仓库仍能运行，不依赖 sibling checkout。
3. Codex、OpenCode、Reasonix 的发现与路由测试覆盖新 ID、触发词、脚本路径和旧 ID 过渡映射；旧映射只转向唯一实现，不额外激活旧新两个主 Skill。
4. 在临时目录执行 dry-run、安装、升级和卸载；不修改开发者当前 Agent 目录。用户修改的文件能触发保留/冲突机制，无关 Skill 不变。
5. Kai 在其源码所有者处完成 canonical 快照、来源锁、路由、路径和测试同步；测试不把 Ubuntu 控制端误判为 iStoreOS 目标，不叠加第三方 remote-control Transport。
6. Ubuntu、Debian、iStoreOS 各从干净实验室执行 on-device 与 remote-control 的三条完整用户旅程：找软件并实际使用、安装 SDK 并运行依赖项目、分析空间并搜索文件，共十八条 required 旅程；MS7 各通道的加速证据同时关联到本轮结果。
7. 对每个 required 镜像至少再用全新容器、HOME、项目目录和客户端缓存复跑关键旅程一次，避免依赖上次安装状态。网关冷缓存测试使用独立实例或明确可证实的未缓存输入，不能只清客户端缓存。
8. 本计划要求的 fixture/container 用例无 failed、blocked 或 skipped，既有回归无新增失败；macOS/Windows native、未覆盖架构及真实内核/服务范围保持显式 pending，不计入通过项。
9. 同一源码两次构建候选包的摘要一致，manifest/source digest/解包内容一致。构建可审查的候选制品即可完成本阶段；本计划不包含公网发布或生产部署。

最终交付分别列出功能实现范围、容器通过矩阵、离线通过矩阵、实际工具可用范围和后续原生验收清单。不能用一个总 PASS 隐藏平台差异。

## 测试入口与阶段推进

现有测试继续保留，MS0 已新增按里程碑选择测试的入口和清单，形式如下。尚未实现的阶段测试会返回失败，不会因缺失脚本而跳过。

```sh
sh tools/test-multisystem.sh --list
sh tools/test-multisystem.sh --milestone MS2 --suite contract
sh tools/test-multisystem.sh --milestone MS5 --suite lab --target ubuntu
sh tools/test-multisystem.sh --suite required
```

本机执行 npm、Cargo、Go、Zig 的依赖安装、构建与测试时，遵循工作区 SSD 缓存入口，并核验实际输出位置；独立 shell 不依赖前一次 source。远程实验室使用自身持久目录和资源预算，不假定宿主具有本机缓存入口。

实施顺序为 MS0 → MS1/MS2 → MS3 → MS4/MS5 → MS6/MS8 → MS7 → MS9 → MS10；其中可并行的依赖只表示工作可以拆分，不要求启动多个 Agent。功能变更先添加会失败的接口/行为回归，再实现；不为纯文档变更增加镜像实现细节的测试。

每阶段执行前声明 required 用例，执行后提交机器可读结果与可读结论。required 用例失败或外部产物缺失时保留 failed/blocked，并继续不依赖该项的工作。阶段修复后运行相关测试；只有代码继续变化或证据仍不完整时才扩大复测。阶段完成后更新验证记录，不能把本计划中的预期目标直接改成既成测试事实。

关联约束：[运行时与下载合约](runtime-download-contract.md)、[既有任务执行入口](runtime-task-entrypoints.md)、[发布与安装生命周期](../RELEASING.md)。这些文件中的历史任务范围保留，跨系统的新行为以本计划及其后续实现合约为准；TLS、校验、环境隔离和来源所有权规则继续沿用。
