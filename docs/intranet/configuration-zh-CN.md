# OpenViking UOS 内网配置手册

本文说明离线介质中的 `.env`、`ov.conf`、`ovcli.conf` 和网络策略。配置以 OpenViking `0.4.15`、离线介质 `0.4.15-uos.1` 为准。

## 1. 文件与优先级

| 文件 | 默认位置 | 用途 | 权限建议 |
|---|---|---|---|
| `.env` | `/opt/openviking-uos/.env` | Compose、模型密钥、网络策略和端口 | `0600` |
| `ov.conf` | `/var/lib/openviking/ov.conf` | OpenViking 服务端配置 | `0600` |
| `ovcli.conf` | `/var/lib/openviking/ovcli.conf` | 容器内 CLI 连接配置 | `0600` |
| `manifest.json` | `/opt/openviking-uos/manifest.json` | 版本、来源和镜像清单 | `0644` |

上游配置顺序为：显式 `--config`、`OPENVIKING_CONFIG_FILE`、`~/.openviking/ov.conf`、`/etc/openviking/ov.conf`。离线 Compose 明确设置 `/app/.openviking/ov.conf`，所以宿主机数据目录内的 `ov.conf` 实际生效。

`ov.conf` 支持 `$VAR` 和 `${VAR}` 展开。模板把秘密放在 `.env`，未设置的变量会原样保留并被策略预检拒绝。

## 2. `.env` 配置

### 容器和监听

```dotenv
OPENVIKING_IMAGE=openviking-uos:0.4.15-uos.1
OPENVIKING_BIND_ADDRESS=127.0.0.1
OPENVIKING_SERVER_PORT=1933
OPENVIKING_DATA_DIR=/var/lib/openviking
```

- 镜像名必须与 `manifest.json` 一致；
- 默认只监听回环。允许局域网访问时填服务器内网 IP，不建议 `0.0.0.0`；
- 宿主机端口可改，容器内仍为 1933；
- 数据目录保存配置、资源、索引和日志，必须纳入备份。

### 网络模式

```dotenv
OPENVIKING_NETWORK_MODE=intranet
OPENVIKING_ALLOWED_HOSTS=model-gateway.corp.local,minio.corp.local
OPENVIKING_ALLOWED_CIDRS=100.96.0.0/16
```

| 模式 | 默认允许 | 适用场景 |
|---|---|---|
| `offline` | 回环，以及管理员明确增加的地址 | 无网络安装和启动验收 |
| `intranet` | 回环、RFC1918、CGNAT、链路本地、IPv6 ULA；域名必须列入清单 | 企业内网，推荐 |
| `online` | 不限制 | 仅联网构建/维护区，生产内网禁止 |

允许清单用逗号分隔，不支持通配符。填写准确主机名，不要写 `*.corp.local`。CIDR 保持最小范围，禁止 `0.0.0.0/0` 和 `::/0`。

Docker 内访问宿主机模型服务可用 `host.docker.internal`；Compose 已映射到 `host-gateway`，还需把该域名加入允许清单。

### 模型网关

```dotenv
OPENVIKING_EMBEDDING_API_BASE=http://model-gateway.corp.local:8000/v1
OPENVIKING_EMBEDDING_API_KEY=...
OPENVIKING_EMBEDDING_MODEL=bge-m3
OPENVIKING_VLM_API_BASE=http://model-gateway.corp.local:8000/v1
OPENVIKING_VLM_API_KEY=...
OPENVIKING_VLM_MODEL=qwen3-vl
```

离线基线使用 `provider: openai`，网关需兼容 OpenAI Embeddings 和 Chat Completions。模型名取决于企业实际部署，不能直接照抄示例。

Embedding `dimension` 必须与实际输出一致。更换模型或维度后通常要重建已有索引。VLM 用于 L0/L1 摘要、语义理解和记忆抽取；图片、音频、视频需要相应多模态能力。

### Root API Key

```dotenv
OPENVIKING_ROOT_API_KEY=<至少32字符的独立随机值>
```

可在受控终端生成：

```bash
openssl rand -hex 32
```

Root Key 只用于管理操作。普通 Agent/用户应创建 user/admin key，不要共享 Root Key。

## 3. `ov.conf` 核心项

### 本地存储

```json
{
  "storage": {
    "workspace": "/app/.openviking/data",
    "vectordb": {"name": "context", "backend": "local"},
    "agfs": {"backend": "local"}
  }
}
```

单机 UOS 使用本地文件和本地向量库。不要改成未挂载的容器目录，否则重建容器会丢数据。MinIO/S3/Redis 等企业后端需另做高可用、TLS、凭据和备份设计，并把准确端点加入允许清单。

### Embedding

```json
{
  "embedding": {
    "max_concurrent": 4,
    "max_retries": 2,
    "dense": {
      "provider": "openai",
      "api_base": "${OPENVIKING_EMBEDDING_API_BASE}",
      "api_key": "${OPENVIKING_EMBEDDING_API_KEY}",
      "model": "${OPENVIKING_EMBEDDING_MODEL}",
      "dimension": 1024,
      "input": "text",
      "encoding_format": "float",
      "batch_size": 16
    }
  }
}
```

推荐起点而非上游固定默认：并发 4、重试 2、batch 16、`encoding_format=float`。根据网关限流逐步调整；多模态 embedding 才将 `input` 改为 `multimodal`。

### VLM

```json
{
  "vlm": {
    "provider": "openai",
    "api_base": "${OPENVIKING_VLM_API_BASE}",
    "api_key": "${OPENVIKING_VLM_API_KEY}",
    "model": "${OPENVIKING_VLM_MODEL}",
    "max_concurrent": 4,
    "max_retries": 2,
    "timeout": 600,
    "thinking": false
  }
}
```

内网模式要求显式 `api_base`。`openai-codex` 依赖 Codex OAuth/公网端点，策略会拒绝。备用 credential 也必须分别指向受控内网地址。

### 搜索模式

```json
{"default_search_mode": "fast"}
```

`fast` 主要使用向量检索，模型调用少；`thinking` 加入 LLM 规划/重排，可能提高效果但增加延迟和负载。建议先用 `fast` 完成上线，再通过质量评测决定。

### 服务与认证

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 1933,
    "workers": 1,
    "auth_mode": "api_key",
    "root_api_key": "${OPENVIKING_ROOT_API_KEY}",
    "cors_origins": ["http://127.0.0.1:1933", "http://localhost:1933"],
    "profile_enabled": false,
    "with_bot": false
  }
}
```

容器内监听 `0.0.0.0` 是为了 Docker 映射；宿主机暴露范围由 `.env` 决定。CORS 必须列出实际来源，不能用 `*`。多 worker、共享存储和多副本需要单独验证锁、任务队列和向量库一致性。

### 遥测和连接器

```json
{
  "telemetry": {"tracer": {"enabled": false, "endpoint": ""}},
  "connector": {"enable": false},
  "parser_api": {"enable": false},
  "enable_watch_scheduler": false
}
```

这是内网基线。关闭 Watch Scheduler 可避免定时刷新远程资源，不影响手工上传本地文件。接入企业内网 OTLP、Parser 或 Connector 前，应评审数据内容、端点和网络策略。

## 4. `ovcli.conf`

```json
{
  "url": "http://127.0.0.1:1933",
  "api_key": "replace-with-user-or-admin-key"
}
```

生产客户端应使用服务器内网 HTTPS 地址和 user/admin key。普通数据访问不要使用 Root Key。

## 5. 配置验证

静态策略检查：

```bash
cd /opt/openviking-uos
sudo ./manage.sh policy-check
```

它检查环境变量、URL/hostname、模型 endpoint、Codex OAuth、遥测、Connector、Parser API、Watch Scheduler、API Key 认证、Root Key 和 CORS。

真实模型与原生模块检查：

```bash
sudo ./manage.sh doctor
```

实际 Compose 展开：

```bash
sudo docker compose config
```

`docker compose config` 可能输出展开后的秘密，不要把完整输出发到公开工单。

## 6. 企业 CA 和 HTTPS

模型网关使用企业 CA 时，应将 CA 只读挂载进容器并设置 `SSL_CERT_FILE`，或由企业 CI 构建带 CA 的派生镜像。不要关闭 TLS 校验，也不要进入运行容器做不可追踪的手工修改。派生镜像应生成新 manifest 和 SHA-256。

## 7. 资源导入策略

推荐顺序：本地文件上传、审批过的只读资料目录、企业内网 Git/文档站，最后才是经安全网关批准的外部资源。公网 GitHub、网页、RSS、飞书默认被拒绝。每个允许目的地址都应有数据分类、责任人和复核日期。

## 8. 性能与变更

先记录基线，再调整模型并发、batch、QPS、超时、文档分块、磁盘 IOPS 和搜索模式。资源不足时优先降低并发/批次，不要盲目增加重试。

配置变更步骤：

1. 备份配置和业务数据；
2. 在隔离验证机修改；
3. 执行 `policy-check` 和 `doctor`；
4. 上传小型本地样本文档并检索；
5. 审批后应用生产并记录回滚点。

Embedding 模型/维度变更必须制定索引重建计划。存储后端、加密或多租户鉴权变更必须先做恢复演练。

## 9. 安全检查清单

- `.env` 和 `*.conf` 为 `0600`，仓库/日志中没有真实密钥；
- 只绑定回环或指定内网 IP；
- API Key 鉴权开启，CORS 无通配符；
- VikingBot、遥测、Connector、Parser API、Watch Scheduler 按基线关闭；
- 网络模式不是 `online`，域名/CIDR 清单已审批；
- 宿主机防火墙独立阻断公网；
- 数据目录有加密、备份、恢复和留存策略；
- 升级介质已核验 Release 来源和 SHA-256。
