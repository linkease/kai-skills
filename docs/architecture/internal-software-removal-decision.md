# 内部软件卸载范围：已确认

用户已确认推荐方案：删除受管程序版本，保留配置、项目/用户数据、缓存和未知/修改内容；实现归 zsetup-scripts，Kai 仅调用所有者接口。以下选项表保留为决策背景。

MS4 要求系统软件与内部软件均完成搜索、安装、实际使用和卸载。实际验证发现：Linux 正式 zsetup 0.5.1 与 Linkspace 安装器 0.1.0 提供安装、current/previous 切换和失败回滚，没有卸载命令；`installer_dispatch` 只接受 scope/prefix/work-dir 参数，其他参数交给业务程序。不能把回滚或命令入口删除直接记为完整卸载。

公开来源：[zsetup 权威索引](https://fw.koolcenter.com/binary/zsetup/config.json)、[Linkspace 0.1.0 安装器](https://fw.koolcenter.com/binary/linkspace/0.1.0/linkspace-install.sh)。安装器 SHA256 为 `caa0c486544d498164d55473a7a0e8fabf18818597108c628870ec495d62a022`；原生 Ubuntu/Debian 实际安装与功能调用结果记录在 MS4 证据中。

需要确定“卸载”的产品范围：

| 方案 | 实际删除 | 保留 | 验收含义 |
| --- | --- | --- | --- |
| 推荐：删除受管版本 | 经所有权和完整性核验的程序、版本标记、current/previous 和对应命令链接 | 配置、项目/用户数据、下载缓存、未知或修改过的文件 | 完整程序卸载；数据和缓存清理是独立请求 |
| 仅移除入口 | 经核验且指向本安装的命令链接 | 所有安装版本与数据 | 应明确称为停用，不能继续沿用当前“完整卸载”的验收表述 |
| 暂不提供卸载 | 无 | 全部文件 | 缩小 MS4 及 MS10 的 required 范围，卸载能力保持 unavailable |

建议由安装所有者 zsetup-scripts 提供受管二进制卸载入口，Kai 的 `software.sh remove` 只调用该入口。沿用既有事务锁、`.managed` 所有权和 `*.verified` 完整性信息；遇正在安装、外部命令、修改过的程序、异常链接或未知目录内容时保留并返回冲突。服务的停止/注销继续由应用自身处理，不把服务移除混入普通客户端卸载。

实现采用 zsetup-scripts 的 `scripts/remove-managed.sh` 所有者入口，由其生成器嵌入共享存储、事务锁及卸载源码。Kai 通过显式开发同步工具带入同字节资源和来源/摘要锁；分发物不依赖 sibling checkout。仅支持 user scope 的 Linkspace、ks-cli、kspeeder 二进制安装，不处理服务。调用现有 zsetup run 执行本地资源，不增加下载器或虚构卸载命令。公网安装器与不可变发布文件保持原字节；本轮仅准备和测试本地候选。
