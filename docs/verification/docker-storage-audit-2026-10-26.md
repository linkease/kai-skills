# Docker 测试宿主空间检查

2026 年 10 月 26 日，通过已有可信 SSH 连接检查测试宿主。目标地址、凭据与指纹保留在仓库外。用户随后确认执行清理和迁移；已清理指定的历史性能测试生成数据，并完成 Docker data_root 迁移。应用数据、其他历史测试目录和旧 Docker 目录保留。

## 工具和检查范围

目标未预装 linkspace。临时复制工作区已有的静态 x86_64 linkspace，核对本地与目标 SHA256 一致后执行；版本为 `dev-2403d66-aufs1`，摘要为 `b1096e3d2f9b9bbba29099e635fc2b5620de17e51ebd5faec0ce3be1b5b59788`。使用 live scan、allocated 指标和挂载范围检查，不创建持久索引。临时工具与扫描工作区在检查后清理。

Docker 根目录、当前数据盘、Configs、fssearch-cli-test 以及候选盘的性能测试目录均完成相应范围扫描，无不可读范围。候选盘首次全盘扫描达到 64 MiB 临时空间上限后返回 partial；随后缩小到性能测试目录并采用 128 MiB 上限，完成该目录及其直接子目录统计。候选盘其余内容不作为全盘扫描完成结果报告。

Docker 自身的 `system df` 与 `system df -v` 均显示镜像、容器、卷、构建缓存为零；有 bridge、docker-lan、host、none 四个网络。

## 执行前容量结果

空间数值为检查时的观测，GiB 使用 1024 的三次方字节。文件树分摊占用与最终可回收空间不同，尤其存在硬链接时；删除后的真实回收量必须用 df 复核。

| 路径 | 观测结果 |
| --- | --- |
| `/mnt/vio3-1` | ext4，容量约 31.37 GiB，可用约 3.78 GiB，使用率 87% |
| `/mnt/vio3-1/docker` | 实际分配 569344 字节，约 556 KiB；无 Docker 可回收对象 |
| `/mnt/lighthost-s5-vm` | ext4，容量约 23.46 GiB，可用约 13.06 GiB，使用率 44%；已配置 UUID 自动挂载 |
| `/mnt/vio4-0` | 可用约 0.79 GiB，使用率约 95%，不适合作为迁移目标 |

当前 Docker 数据盘的主要目录：

| 目录 | 分配占用 | 判断 |
| --- | --- | --- |
| `/mnt/vio3-1/Configs` | 10.09 GiB | 其中 Runtime 5.70 GiB、KAI 2.80 GiB，不归类为可直接删除 |
| `/mnt/vio3-1/lighthost` | 6.69 GiB | 虚拟化数据，保留 |
| `/mnt/vio3-1/fssearch-cli-test` | 3.93 GiB | 历史测试候选；含 current 链接和 user-capacity，不能整体盲删 |
| `/mnt/vio3-1/.linkease_data` | 1.44 GiB | 应用数据，保留 |
| `/mnt/vio3-1/s10-m5-vm-images-20260922` | 0.70 GiB | 旧 VM 镜像候选，需要确认不再用于恢复或复用 |

## 优先清理候选

优先候选为 `/mnt/lighthost-s5-vm/.linkspace-perf/20261012-m0`，分配占用约 9.85 GiB，包含 `.owned-by-linkspace-perf` 标记、测试样本与索引。扫描结束后的进程 exe/cwd/打开文件检查，以及 `/etc/config`、`/etc/init.d`、`/etc/crontabs`、`/etc/rc.local` 路径引用检查，未发现这些候选路径的引用。该检查不能替代对历史测试保留需求的确认。

| 子目录或类别 | 分配占用 | 处理建议 |
| --- | --- | --- |
| `bin` | 3.96 GiB | 历史性能测试程序，确认无需重跑后删除 |
| 六个 `store-*` 目录 | 合计约 3.58 GiB | 历史测试存储，保留报告后可列入清理 |
| 三个 `source-*` 目录 | 合计约 1.42 GiB | 生成测试样本，含硬链接，按整组处理后用 df 验证 |
| `small-dir-20261013` | 0.87 GiB | 生成测试样本，确认保留需求后清理 |
| `reports` | 约 16.5 MiB | 保留，连同复现脚本和 fixture 描述归档 |

执行前预测：仅保留报告和少量复现材料，可回收约 9.8 GiB，候选盘可用空间从约 13.1 GiB 提高到约 22.9 GiB。实际清理结果见下文。

次级候选是 Configs 下的三个历史 ks-cli 测试目录，合计约 1.10 GiB：`ks-cli-probe-e2d4e9d-20261007`、`ks-cli-test-20261007-f767846`、`ks-cli-git-smoke-b89dc0f-20261012`。目录含报告、rollback 和 backup 材料；需要先保留这些材料，再决定测试工作目录的清理范围。

fssearch-cli-test 内的 `current` 指向 `20261010051215`；`user-capacity` 约 0.78 GiB。两者先保留。其余历史轮次、large-scan 样本可以进一步制定逐项清理清单。本轮不需要清理个人文件、应用配置、VM 数据或系统备份来满足实验室的首期容量需求。

## Docker 迁移方案

迁移目标为 `/mnt/lighthost-s5-vm/docker`，执行前该目录不存在。该挂载点为可写 ext4，并已配置 UUID 自动挂载。迁移的收益是给后续镜像、SDK 和实验室缓存提供更充裕的可用空间；旧 Docker 元数据很小，迁移不会明显释放旧盘空间。

执行方案：

1. 执行前重新验证挂载身份、空间、Docker 工作负载、网络和未提交 UCI 修改；保存 `/etc/config/dockerd` 与当前 Docker 网络信息。
2. 停止 dockerd 并确认停止，完整复制旧数据目录到新目录并校验，保留 docker-lan 等网络元数据。不能只因没有容器就丢弃所有旧元数据。
3. 只修改 `dockerd.globals.data_root`，保留现有镜像源、iptables 和其他配置；启动服务后核对 Docker Root Dir、四个网络、对象清单和目标挂载身份。
4. 保留旧目录和配置备份作为回滚点；失败则停止服务、恢复原配置并使用原目录启动。不在迁移当次删除旧目录。
5. 验证开机挂载顺序，确保目标盘未挂载时不会在同名路径创建 Docker 数据。重启整机验证另列验收，不用一次手动启动替代。

## 授权执行与独立复核结果

清理于 14:42:34 UTC 完成，迁移于 14:48:10 UTC 完成；14:49:35 UTC 从新的 SSH 会话完成独立复核。

| 项目 | 实际结果 |
| --- | --- |
| 清理范围 | 仅性能测试根目录内显式列出的 15 个生成目录；包括历史 bin、三个 source、六个 store、small-dir、两个 smoke fixture、Python 缓存和临时目录 |
| 实际回收 | 10562183168 字节，约 9.84 GiB，以同一挂载点清理前后 statvfs 的可用空间差计算 |
| 证据保留 | reports、smoke-tools、两个复现脚本、三个 fixture 描述、所有权标记及锁文件保留在原位置；另复制到受保护备份目录，1985 个条目校验通过 |
| 目标盘最终状态 | 可用 24569565184 字节，约 22.88 GiB；df 使用率 2% |
| 当前 Docker Root Dir | `/mnt/lighthost-s5-vm/docker`，Docker 实际状态与 UCI 一致 |
| 元数据复制 | 停服后比对 82 个持久元数据条目的内容摘要、类型、权限、所有者和扩展属性；旧目录未改动并保留 |
| 网络 | bridge、docker-lan、host、none 均存在；docker-lan 的 ID、IPAM、选项保持一致，daemon 身份保持一致 |
| 其他配置 | 仅改变 UCI data_root，镜像源、iptables 和其他 daemon 配置保持一致，无未提交 UCI 修改 |
| 工作负载 | 完成后镜像、容器、卷均为零 |
| 挂载保护 | 新增 `/etc/dockerd-data-root-guard.sh` 并在 dockerd 启动前调用；校验目标挂载点、UUID、ext4 与 rw。正确目标返回成功，使用 `/tmp` 的错误目标测试返回失败 |
| 开机顺序 | 已核对 fstab 在 S11、dockerd 在 S99，且 UUID 自动挂载启用；整机重启与真实缺盘启动未执行 |

第一次迁移因严格复制检查遇到 `volumes/backingFsBlockDev` 块设备节点而中止，自动恢复了旧目录上的 Docker 服务，未切换配置。核对 [Moby v27.3.1 的 quota 实现](https://github.com/moby/moby/blob/v27.3.1/quota/projectquota.go#L406) 后，第二次仅排除这个与底层文件系统绑定、由 Docker 启动时重建的节点；其他持久元数据照常复制并验证。已确认新节点对应新文件系统的设备号 8:48，而非旧盘的 8:17。首次失败及回滚证据也保留在备份目录。

独立复核还重新检查了原位置与备份中的保留文件摘要、所有被授权删除目录确已消失、当前 UCI 与 daemon 的数据目录、Docker 网络和挂载保护。未清理 fssearch-cli-test、三个 Configs 下的 ks-cli 测试目录、VM、系统备份或其他应用数据。

备份与执行记录位于：

```text
/mnt/lighthost-s5-vm/kai-maintenance/20261026T143828Z/
```

该目录由 root 保护，保存报告副本及清单、配置和 init 脚本备份、迁移前后网络信息、清理与迁移结果、独立复核结果、操作脚本及 SHA256SUMS。原 Docker 数据仍位于 `/mnt/vio3-1/docker`。

尚未在新目录创建镜像、容器或卷时，可使用目录中的受保护回滚入口：

```sh
sh /mnt/lighthost-s5-vm/kai-maintenance/20261026T143828Z/rollback-docker.sh
```

回滚入口会检查工作负载、当前配置摘要和网络名称；若后续已创建测试环境或修改配置，应重新制定回滚范围。它恢复旧配置及原 init 脚本，保留新数据目录，不自动删除任何一侧的数据。

挂载保护包含对包提供的 `/etc/init.d/dockerd` 的小范围修改；升级 dockerd 包后需要复核保护调用仍然存在。该工作仅完成实验室的存储前置条件，未创建 Ubuntu、Debian 或 iStoreOS 测试容器，不标记 MS1 完成。
