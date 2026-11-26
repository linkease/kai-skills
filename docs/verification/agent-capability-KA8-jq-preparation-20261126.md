# KA8：显式 jq 准备与原生采证修正（2026-11-26）

用户要求的 jq 一键准备和查询对接已实现，三个实施步骤通过工程自检。KA8 的端到端模型验收仍未通过，本轮没有增加付费模型会话，KA9/KA10 未开始。

## 先更正问题归因

原生测试机已有目标用户的 `~/.local/bin/jq`，只是没有进入 PATH。此前查询器只检查 PATH，因此“机器没有 jq”的结论不准确。旧原始回执和旧模型评测全部保留；它们证明的是当时查询器无法使用 jq，不能证明设备没有安装。

现在查询按显式 `KAI_JQ_BIN`、PATH、目标用户的 `~/.local/bin/jq` 选择并校验完整 jq（包括 regex、Unicode、walk）。显式路径不兼容时明确失败，不暗中换程序。已有副本可用时不重新安装、不修改全局 PATH。

## 任务树与验收

1. jq 准备与消费。
   - 增加 `sh scripts/prepare.sh probe|plan|ensure --tool jq`，复用现有 jq 安装 owner，避免继续准备其他业务运行时。
   - probe/plan 不安装；ensure 校验 owner 资源，按既有下载/校验策略准备 jq，安装后再次检验功能并返回路径。Bash 和原生下载核心仍是必要的引导依赖。
   - 回归覆盖：真正缺失的隔离环境调用 owner、功能复检、再次 ensure 复用、安装失败、空操作假成功、owner 校验和失败和明确不兼容路径。owner 校验失败原本没有 JSON 回执的问题先复现后修正。
   - 通过。隔离 owner 是测试替身，实际 jq 二进制用于功能复检；不冒充原生联网全新安装验收。
2. 原生日志范围查询。
   - 新增可单独或组合使用的 `--log-count N`、`--log-pattern REGEX`，N 是 1–1000 条原生消息，不是物理行。
   - 按 argv 传给 logread；无 shell 解释，不添加业务专用过滤器。未选参数时保持原来的未过滤查询。
   - 回执记录 `logSelection.tailMessages`、`pattern`、`completeHistory:false`；参数错误/被忽略的场景在执行前拒绝。4KiB 探测、8KiB 回执和原有超时限制不变。
   - 通过。消息范围不是稳定日志快照或完整历史；重复查询可能看到新日志。
3. 生成物与原生复测。
   - 从 canonical 重新生成独立技能、平台副本、集合锁与索引；一致性检查通过。
   - 最终 93 项能力测试、8 项准备入口测试、7 项 jq owner 测试、20 项引导回归通过，共 128 项不同测试。
   - 用实际生成的独立 service-manager 包及内嵌 bootstrap 在原生机临时目录验证；源码清单和包 SHA256 留档。
   - plan、ensure、再次 ensure 均校验并复用现有 jq；配置/生成配置/2250 字节完整登记/运行命令/选定日志的组合查询 succeeded。
   - 合成的转义 token 键与 URL 凭据均被脱敏，phase、target 保留；指定不存在的 jq 则 unknown，未暗中安装或换用其他程序。
   - init、系统配置、登记文件和既有 jq 指纹未变，拥有的临时目录已清理。通过。

## 可调用接口

在独立 `istoreos-service-manager` 包目录中，一键准备 jq：

```sh
sh resources/runtime/kai-tool-bootstrap/scripts/prepare.sh ensure --tool jq
```

把 ensure 换成 probe/plan 可查询/预览。成功回执返回校验后的 `path`；调用者也可通过 `KAI_JQ_BIN=该绝对路径` 传给查询。模型决定是否需要准备，宿主执行现有权限和变更保护；读取查询本身不会安装软件，安装 jq 也不代表业务任务完成。

本轮实际成功的显式范围组合是：

```sh
sh scripts/inspect.sh --target-id ID --service dockerd \
  --sections config,runtime,logs --length 4096 --log-count 5
```

这不是固定 Docker 处置流程。调用者自行选择服务、范围、消息条数及模式；默认窗口仍可能返回 partial，超限也不会报成完整结果。

## 验收边界

本轮完成了用户请求的工程能力；没有证明原先错误的模型判断已被修复，也没有把旧失败样本改成通过。原定 216 个会话与 12 个原生平台/模式矩阵未运行，KA8 仍未签收。已有 KaiPlus 应用、内置 bundle 锁定和旧会话快照没有替换，发布和交付验收继续归 KA10。

逐项结果、版本哈希和私有证据引用见 [JSON 报告](agent-capability-KA8-jq-preparation-20261126.json)。设备信息和原始输出保留在项目私有 build/verification 中。
