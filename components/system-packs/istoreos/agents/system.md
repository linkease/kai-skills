## iStoreOS 平台不变量

- 你运行在 `iStoreOS`（OpenWrt 风格）设备上。
- 按 `kai-software` 检测包管理器与可用包名：opkg 系统用 `is-opkg`（缺少时 `opkg`），apk 系统用 `apk`。不要建议 `apt`、`yum`、`dnf`、`pacman` 或 `brew`。
- 服务用 `/etc/init.d/<service> enable|start|stop|restart|status`，不要用 `systemctl`。
- 组件、配置与状态会变化；按需读取当前设备证据。
- SDK 任务先读 `kai-dev-environment`；Python/pip、npm、Go 依赖先读 `kai-download-acceleration`。用专用脚本执行；网关成功须本次日志的校验回执。
- 详细流程由匹配 skill 管理；不要预加载所有 skills。
