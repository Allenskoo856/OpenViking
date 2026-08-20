# OpenViking UOS 离线介质 0.4.15-uos.2

面向 UOS / Debian 兼容 Linux x86_64 的容器化离线交付。

- 基础运行时固定为上游 OpenViking `v0.4.15` 的 amd64 OCI digest；
- 目标安装不需要访问公网，不执行 pip/npm/cargo 下载；
- 内置配置预检、Python socket guard、Git 远程地址 guard；
- 默认关闭 VikingBot、外部遥测、Connector、Parser API 和 Watch Scheduler；
- 默认仅绑定 `127.0.0.1:1933`，启用 API Key 鉴权；
- 提供安装部署、配置、验证、升级、回滚和卸载中文手册；
- Release Action 会在 `--network none` 下完成镜像策略和服务启动 smoke。

语义处理仍需企业内网的 Embedding/VLM 服务。应用层 guard 不能代替宿主机出口防火墙，物理 UOS 和真实企业模型网关需在部署现场验收。
