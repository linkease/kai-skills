# Legacy native interface reference


# iStoreOS Storage Path

当用户要“装到硬盘/U盘/指定数据目录”，或遇到“磁盘满/空间不足/迁移目录”时，按下面流程输出一个可用的 `base path`。

## 输出合同（很重要）

- 你输出的 `base path` 会用于：`is-opkg AUTOCONF=<app> path=<base> ...`
- `is-opkg` 会派生：
  - `ISTORE_CONF_DIR=<base>/Configs`
  - `ISTORE_CACHE_DIR=<base>/Caches`
  - `ISTORE_PUBLIC_DIR=<base>/Public`
  - `ISTORE_DL_DIR=<base>/Public/Downloads`
- 应用级目录（如 `OneAPI/iStoreEnhance`）由应用自身 autoconf/脚本拼接，避免在本技能里硬编码每个应用的目录名。

## 流程

1) 枚举挂载点与空间：`mount` + `df -h`（必要时 `df -i`）
2) 选择策略：
   - 用户指定挂载点优先（需可写、空间足够）
   - 否则优先外置/数据盘（常见 `/mnt/<name>`）且空间充足
   - 最后才回退系统盘（并提示风险）
3) 默认只根据已存在目录和权限位筛选，不做写入。只有权限位证据不足且用户确认后，才用 `probe.sh` 做真实写入验证。
4) 输出 `base path` + 解释派生目录

## 脚本

- 自动选择 `base path`（stdout 输出路径，stderr 输出解释）：`SKILLS_DIR="${KAIPLUS_SKILLS_DIR:-${KAIPLUS_HOME:?KAIPLUS_HOME is required}/config/skills}"; sh "$SKILLS_DIR/istoreos-storage-path/scripts/detect.sh"`
- 确认后做真实可写探测：`KAIPLUS_CONFIRMED=1 sh "$SKILLS_DIR/istoreos-storage-path/scripts/probe.sh" <absolute-base-path>`
