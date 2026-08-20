# OpenViking UOS 内网离线安装部署手册

本文对应 `openviking-uos-offline-0.4.15-uos.2-linux-amd64` 离线介质。目标是让 UOS / Debian 兼容的 x86_64 服务器在安装阶段不访问公网，并让 OpenViking 只访问经过批准的企业内网模型服务。

## 1. 交付范围

离线介质包含：

- 固定版本的 OpenViking 运行镜像，含 Python、Rust CLI、原生向量引擎和 Web Studio；
- UOS 内网加固层：配置预检、Python socket 出网拦截、Git 远程地址拦截和代理变量清理；
- Docker Compose 模板；
- 安装、完整性校验、启停、健康检查和卸载脚本；
- `ov.conf`、`ovcli.conf`、`.env` 示例；
- 本手册和《配置手册》；
- 介质内外两层 SHA-256 校验值与 `manifest.json` 来源清单。

介质不包含 UOS 安装镜像、Docker/Compose 安装包、模型权重、推理框架、企业 CA/DNS/KMS，也不提供公开网站、GitHub、飞书、火山方舟、OpenAI 或 Codex OAuth 的离线替代品。

OpenViking 的语义处理需要 Embedding 和 VLM。离线介质解决“程序和依赖如何进入内网”，模型能力需要由企业内网 OpenAI 兼容网关或本地模型服务提供。

## 2. 支持边界

| 项目 | 本介质基线 |
|---|---|
| CPU | x86_64 / amd64 |
| 操作系统 | UOS Server、UOS Desktop 或 Debian 10 兼容主机 |
| 容器运行时 | Docker Engine，支持 `docker load` |
| Compose | `docker compose` v2，或兼容的 `docker-compose` |
| 磁盘 | 镜像与工作数据建议至少预留 20 GiB；生产容量按文档规模另算 |
| 内存 | 最低 4 GiB；建议 8 GiB 以上 |
| 端口 | 默认仅监听 `127.0.0.1:1933` |
| 数据目录 | 默认 `/var/lib/openviking` |

物理 UOS 型号、国产 CPU、企业 Docker 发行版和真实模型网关需要在目标环境另行验收。本介质不支持 ARM64。

## 3. 构建、传输和运行边界

1. GitHub Actions 构建区可以联网拉取固定镜像和 Actions 依赖；
2. 介质通过审批过的 U 盘、摆渡机或制品库传入内网；
3. UOS 目标机从本地归档执行 `docker load`，不执行在线 `pip`、`npm`、`cargo` 或镜像拉取；
4. 业务运行只访问配置过的内网模型地址。网页、远程 Git、飞书等地址默认不能访问公网。

## 4. 下载、传输与校验

从 fork 的 GitHub Release 下载：

```text
openviking-uos-offline-0.4.15-uos.2-linux-amd64.tar.gz
openviking-uos-offline-0.4.15-uos.2-linux-amd64.manifest.json
SHA256SUMS
```

在下载机校验后，把归档和校验文件一起传入目标区：

```bash
sha256sum -c --strict SHA256SUMS
```

## 5. UOS 目标机前置检查

```bash
uname -s
uname -m
docker version
docker info
docker compose version || docker-compose version
df -h /var/lib /opt
```

预期系统为 `Linux`、架构为 `x86_64`，Docker 客户端和服务端均可用，Compose 可用且数据盘空间充足。Docker/Compose 必须由企业软件仓或管理员提前安装；本介质不会更改系统软件源。

## 6. 介质完整性与无网络预验收

```bash
sha256sum -c --strict SHA256SUMS
tar -xzf openviking-uos-offline-0.4.15-uos.2-linux-amd64.tar.gz
cd openviking-uos-offline-0.4.15-uos.2-linux-amd64
./verify-offline-media.sh
```

若允许加载镜像，执行完整 smoke：

```bash
./verify-offline-media.sh --docker-smoke
```

它会校验介质内文件、manifest 和 gzip，执行 `docker load`，使用 `--network none` 校验策略、验证公网 DNS 被应用层拒绝，并在完全无网络的容器中启动服务和检查 `/health`。

无网络 health 只证明程序、原生模块、配置加载和 HTTP 服务能启动，不证明内网模型业务可用。

## 7. 安装

默认安装管理文件到 `/opt/openviking-uos`，数据保存到 `/var/lib/openviking`：

```bash
sudo ./install-offline.sh
```

自定义目录：

```bash
sudo ./install-offline.sh \
  --install-dir /data/app/openviking-uos \
  --data-dir /data/openviking
```

脚本加载本地镜像，但不会用占位配置自动启动。它不覆盖已有 `.env`、`ov.conf` 或 `ovcli.conf`；升级时只替换管理文件，并备份上一版管理文件。

## 8. 首次配置

```bash
sudo chmod 600 /opt/openviking-uos/.env /var/lib/openviking/*.conf
sudo vi /opt/openviking-uos/.env
sudo vi /var/lib/openviking/ov.conf
```

至少替换：

- `OPENVIKING_ALLOWED_HOSTS`：内网模型网关域名；使用 IP 时可留空；
- `OPENVIKING_ALLOWED_CIDRS`：企业额外内网网段；
- Embedding 地址、Key、模型名和实际维度；
- VLM 地址、Key 和模型名；
- `OPENVIKING_ROOT_API_KEY`：独立、随机、至少 32 字符的管理密钥。

不要把 `.env`、`ov.conf` 或 `ovcli.conf` 上传到 GitHub、工单或聊天群。具体语法见《配置手册》。

## 9. 启动与验收

```bash
cd /opt/openviking-uos
sudo ./manage.sh policy-check
sudo ./manage.sh up
sudo ./manage.sh status
sudo ./manage.sh smoke
sudo ./manage.sh doctor
```

验收层次：

1. `policy-check`：静态配置和网络目的地址符合内网基线；
2. `status`：容器运行且健康；
3. `smoke`：`/health` 返回成功；
4. `doctor`：Embedding、VLM、磁盘、原生向量引擎通过；
5. 业务验收：上传一份本地文档，等待处理完成，再执行语义检索。

本地文档验收示例：

```bash
docker cp ./acceptance.txt openviking-uos:/tmp/acceptance.txt
sudo docker exec openviking-uos ov add-resource /tmp/acceptance.txt --wait
sudo docker exec openviking-uos ov ls viking://resources/
sudo docker exec openviking-uos ov find "验收文本中的关键问题"
```

不要用公网 URL 作为内网验收材料。

## 10. 访问与安全

默认访问地址：

```text
http://127.0.0.1:1933
http://127.0.0.1:1933/studio
```

供其他内网机器访问时，把 `.env` 的 `OPENVIKING_BIND_ADDRESS` 改成服务器内网 IP，并同时完成：

- UOS 防火墙只允许受信网段访问 TCP 1933；
- 保持 `server.auth_mode=api_key`；
- `cors_origins` 明确列出来源，不使用 `*`；
- 生产环境用企业反向代理终止 TLS；
- 不在 URL、日志或截图中暴露 API Key。

## 11. 日常运维与备份

```bash
cd /opt/openviking-uos
sudo ./manage.sh status
sudo ./manage.sh logs 300
sudo ./manage.sh doctor
sudo ./manage.sh restart
sudo ./manage.sh stop
sudo ./manage.sh up
```

备份前建议停服：

```bash
sudo ./manage.sh stop
sudo tar -C /var/lib -czf /data/backup/openviking-$(date +%Y%m%d%H%M%S).tar.gz openviking
sudo ./manage.sh up
```

不要在服务运行中覆盖向量库文件。恢复应在隔离环境先演练。

## 12. 升级与回滚

升级前备份数据，校验新 Release，停止当前容器，运行新版安装脚本，再做策略、doctor 和业务回归：

```bash
cd /opt/openviking-uos
sudo ./manage.sh stop
cd /path/to/new-media
sudo ./install-offline.sh
cd /opt/openviking-uos
sudo ./manage.sh policy-check
sudo ./manage.sh up
sudo ./manage.sh doctor
```

安装脚本保留配置和数据，并备份上一版管理文件。回滚必须确认旧镜像仍在、数据格式兼容；若新版本执行不可逆数据迁移，应从升级前备份恢复，不能只切换镜像标签。

## 13. 卸载

仅停止并移除容器，保留镜像、配置、管理文件和数据：

```bash
cd /opt/openviking-uos
sudo ./uninstall-offline.sh
```

删除数据不可恢复，脚本要求双重显式确认：

```bash
sudo ./uninstall-offline.sh \
  --remove-data \
  --confirm-remove-data DELETE_OPENVIKING_DATA
```

管理目录和镜像需在确认无其他部署使用后单独处理。

## 14. 网络隔离说明

介质提供三层应用防护：

- 启动前检查 URL、provider、遥测、Connector、Parser API、Watch Scheduler 和认证；
- Python 启动时安装 socket guard，未知域名在 DNS 解析前被拒绝；
- `git` wrapper 拒绝未批准的 HTTP(S)、SSH 和 scp-like 远程地址。

`intranet` 模式允许回环、RFC1918、CGNAT、链路本地和 IPv6 ULA；域名必须显式写入 `OPENVIKING_ALLOWED_HOSTS`。`offline` 只允许回环和管理员显式增加的地址。`online` 关闭限制，不应在生产内网使用。

应用 guard 不能替代宿主机出口控制。原生库、额外二进制或 Docker 配置错误仍可能绕过，生产环境必须同时使用出口防火墙、代理 ACL、DNS 或容器网络策略阻断公网。

## 15. 常见故障

### 配置仍含占位符

`manage.sh up` 报 `change-me`、`replace-with` 或 `intra.example` 时，完整替换 `.env` 示例值，再运行 `policy-check`。

### 域名或 IP 被策略拒绝

日志包含 `network policy blocked`。先确认目的地址属于企业内网；域名加入 `OPENVIKING_ALLOWED_HOSTS`，特殊内网 IP 段以最小 CIDR 加入 `OPENVIKING_ALLOWED_CIDRS`。禁止 `0.0.0.0/0`、`::/0`，不要改成 `online` 绕过。

### `/health` 成功但搜索失败

`/health` 只证明服务进程正常。执行 `manage.sh doctor`，检查模型地址、Key、模型能力、Embedding 维度和网关响应格式。

### `docker load` 空间不足

先清点 Docker 数据目录、镜像、容器和卷。不要直接运行全局 `docker system prune -a --volumes`；确认其他业务后再做有范围的清理。

### Git/网页导入失败

公网 URL 默认被拒绝。优先把资料下载到受控区后作为本地文件上传；确需内网 Git/站点时，加入准确域名并配置宿主机 ACL。

## 16. 验收记录

生产交付至少留存：

- Release URL、tag、源 commit、Action run ID；
- 外层与内层 SHA-256 输出；
- UOS、CPU、Docker/Compose 版本；
- `--network none` smoke 输出；
- `policy-check`、`doctor`、`/health` 输出；
- 本地文档写入与语义检索结果；
- 防火墙/代理拒绝公网的独立证据；
- 备份、恢复、升级和回滚演练记录。
