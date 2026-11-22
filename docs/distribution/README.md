# Agent 安装指南维护与发布

唯一源码为 `agent-install.md`。固定入口是 https://fw.koolcenter.com/binary/kai/kai-skills/agent-install.md 。官网仅维护提示词模板和这个 URL；不要在官网复制安装规则。

修改平台支持、安装器参数、Agent 目录或验收规则时更新指南修订号，核对公开安装器与相关 CLI 帮助，并在受影响环境验证安装。保持指南与公网版本相符，不依据尚未发布的代码声明可用。纯文档更新不改变技能发行版本、stable 或 Product Configuration。

源设备目录由外部程序每 30 秒自动同步到 fw.koolcenter.com（维护者确认）。无需手动 rsync 或直接登录公网服务器；发布脚本只写源目录并等待公网内容一致。调度间隔不等于保证 30 秒内可见，仍需以 HTTPS 校验为准。详见 [自动同步说明与调查修正](origin-sync-investigation.md)。

在仓库根目录执行（主机与路径从仓库外运维配置提供）：

```sh
python3 tools/publish-agent-guide.py plan
python3 tools/publish-agent-guide.py publish --host "$KAI_GUIDE_HOST" --root "$KAI_GUIDE_ROOT"
python3 tools/publish-agent-guide.py verify
```

发布只写指定 kai-skills 目录的指南、guides/ 历史副本与临时锁。要求已有可信 SSH 身份和已登记主机密钥；远端仅使用 Shell、mktemp、sha256sum、cmp、cp、mv。单次发布锁避免并行覆盖；异常断连若留下锁，维护者应先确认没有发布进程再处理。

脚本校验源文件，上传至同目录临时文件并校验 SHA-256；保存旧指南和新指南到 `guides/<sha256>.md`，再原子替换固定入口。不改动技能发行清单及其校验清单，也不删除历史文件。整包发布流程以后应显式保留这些独立指南文件。

发布后最多等待 180 秒并逐字节检查固定公网 URL（可用 --timeout 延长）。同步尚未完成时返回失败，源服务器可能已更新；先用 verify 复查，不要把超时当成没有发布，也不要在公网验证通过前上线官网入口。确认 nginx/CDN 不长期缓存该可变地址；脚本使用 no-cache 请求，但缓存服务仍需正确配置。

回滚：从已保存的 `guides/<sha256>.md` 或已知 Git 提交取回原文至仓库外临时文件，检查后通过 `publish --source /path/to/previous.md --host ... --root ...` 发布，再用相同 --source 执行 verify。同步延迟期间不得声称公网已回滚。源文件也应通过后续提交恢复，避免下次发布再次覆盖。

官网验收：单项、多项、全选均生成明确 ID；空选择禁用；跨系统切换过滤不适用项；复制文本与预览一致；手机与桌面操作正常。官网的系统筛选只是辅助选择，提示词仍要求 Agent 核对实际环境。
