# 源目录到公网文件站的同步调查

调查日期：2026-11-18。此记录区分设备实测与待验证推断；服务器地址、账号、密钥和设备具体挂载点留在仓库外运维配置。

## 结论与证据

- 源数据目录下已有 `a.sh` 和 `b.sh`，均为旧的手动 rsync 命令，没有内置调度。前者使用 `rsync://用户@服务器/share/`，源为相对路径 `public_html/binary`；后者使用 SSH，源为相对路径 `../public_html/*`，目标为 `/data/koolcenter/fw/`。证据：通过源设备 SSH 只读查看两个脚本，文件时间分别为 2025-01-19、2025-01-22。
- `a.sh` 必须以包含 public_html 的数据目录作为工作目录；其源没有尾斜杠，目标 module 下会包含 binary 这一层。`b.sh` 必须从数据目录的一个子目录执行，才符合 `../public_html/*` 的意图；不应直接从数据目录运行，也不应为发布指南而同步全部站点。脚本的存在不能证明它们仍被使用。
- 源设备宿主机 PATH 中没有 rsync。运行中的 `pve` 容器具有 `/usr/bin/rsync`（3.2.7）、SSH，并将宿主机 `/mnt` 挂载到容器 `/mnt`。这是实测可用的 rsync 执行环境，但没有证据证明它就是历史发布任务的执行者。
- 已检查宿主机 crontab、启动入口，以及 pve 容器 cron 配置，没有找到这两条同步脚本的调度引用。iStorePanel 的只读数据库查询显示 cronjobs 表没有任务。未发现运行中的 rsync 同步进程。这些检查不排除公网服务器主动拉取、其他机器调度或其他未检查服务的同步任务。
- 从执行环境和 pve 容器连接旧脚本所指服务器的 rsync daemon 端口（默认 873）均超时；从 pve 使用 BatchMode、StrictHostKeyChecking 和连接超时检查 SSH 默认端口 22，也超时。未到达认证阶段，因此不能据此断定密码、公钥或 module 权限有问题。
- 公网指南 URL 仍返回 404；源目录文件存在。尚未证明旧脚本的目标目录与当前 fw.koolcenter.com 的 nginx 根目录仍然对应。脚本目标域名与公网域名解析地址不同本身不代表配置错误，可能存在前置或同步链路。

## 如何恢复和触发

1. 先由文件站维护者确认旧同步地址是否仍有效、当前 SSH/rsync 端口及来源网络限制，以及 nginx 对应目录或 rsync module 的映射。不要猜测端口，也不要关闭主机密钥检查。
2. 使用已有 SSH 身份；若主机密钥未知或变化，先通过可信运维信息核验。rsync daemon 用户与 SSH 用户是不同认证体系，不互换账号或认证材料。
3. 网络恢复后，在源设备上通过 pve 容器做单文件 dry-run。以下变量在源设备当前 shell 设置，从仓库外配置读取；`SYNC_SOURCE_ROOT` 是包含 public_html 的绝对目录，`SYNC_SSH_TARGET` 是实际 SSH 用户与主机，`SYNC_PUBLIC_ROOT` 是已经确认的公网 kai-skills 目录，`SYNC_SSH_PORT` 是实际端口。

```sh
docker exec pve rsync -rtvin --timeout=20 \
  -e "ssh -p ${SYNC_SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10" \
  "${SYNC_SOURCE_ROOT}/public_html/binary/kai/kai-skills/agent-install.md" \
  "${SYNC_SSH_TARGET}:${SYNC_PUBLIC_ROOT}/"
```

这只是待验证模板，不是已经成功执行的发布命令。目标目录须预先存在。核对预览只涉及 agent-install.md 后，正式执行使用 `-rtvi`（去掉 `n`）；不加 `--delete`。历史指南可以随后按明确文件名单独同步。

如继续使用 daemon 路径，先核对 share module 的目录映射及认证，再使用精确文件列表；不能把操作系统绝对路径当作 module 名称。避免直接执行 a.sh 或 b.sh 做全站同步。

4. 在维护机的 linkease-skills 仓库执行：

```sh
python3 tools/publish-agent-guide.py verify --timeout 180
```

只有固定公网 URL 与本地源码逐字节一致，才可宣布指南发布完成。服务器端 dry-run 或 rsync 成功不代替 HTTPS 验证。

## 后续自动化边界

当前 `publish-agent-guide.py publish` 只负责源目录写入和公网读回，未调用以上旧脚本，也未配置同步任务。待真实链路确认后，再添加一个范围受限的同步步骤，或由运维维护固定任务；应保留独立 dry-run、超时退出和公网校验。不要把源文件写入成功当作公网同步成功，也不要未经核实就给设备新增全目录定时同步。

## 依据

设备第一手证据为上述源目录脚本、Docker mounts/command discovery、cron 文件、iStorePanel cronjobs 只读查询及连接探测结果；未保存原始配置、数据库或身份材料。

rsync 参数语义依据 [官方 rsync 手册](https://download.samba.org/pub/rsync/rsync.1)：单冒号路径使用远程 shell，双冒号或 rsync:// 使用 daemon module；`--dry-run` 预览，`--itemize-changes` 列明变更；源目录尾斜杠控制是否保留目录本身；`--files-from` 支持限定相对文件名单。
