# Dynamo Benchmark 工具集

本目录包含用于对 Dynamo 分离式推理服务（disaggregated serving）进行性能基准测试的完整工具链，支持本地容器开发环境与 Kubernetes 集群两种使用场景。

---

## 目录结构

```
benchmark/
├── aiperf.py              # 核心基准测试脚本（并发扫描 + 指标采集）
├── start-container.sh     # 启动本地开发容器
├── buildx.sh              # 构建本地 Docker 镜像
├── setup-source-code.sh   # 容器内编译源码 & 安装 Python 包
├── set-proxy.sh           # 配置 HTTP/SOCKS5 代理环境变量
└── temp/                  # 基准测试结果输出目录（自动创建）
```

---

## 快速开始

### 1. 启动开发容器

```bash
# 从项目根目录执行
bash k8s/dynamo-deploy/benchmark/start-container.sh
```

容器配置说明：
- 镜像：`chenjian110/dynamo:vllm-v1.0.1`
- 挂载工作区：`/workspace`
- 挂载模型目录：`/nfs/nfs/models` → 容器内 `/models`
- 挂载缓存：`~/.cache` → `/home/dynamo/.cache`
- 容器名：`CJ-DYNAMO-VLLM-LOCAL-DEV`

### 2. 编译源码（容器内执行）

```bash
bash k8s/dynamo-deploy/benchmark/setup-source-code.sh
```

该脚本依次完成：
1. Cargo 编译（含 `block-manager` feature）
2. Python bindings（`maturin develop`）
3. KVBM bindings
4. 安装 Python 包（`uv pip install`）
5. 运行 sanity check

### 3. 配置代理（可选）

若需访问外网（如 HuggingFace），在容器内执行：

```bash
bash k8s/dynamo-deploy/benchmark/set-proxy.sh
```

代理配置（写入 `~/.bashrc`）：
- HTTP/HTTPS Proxy：`http://127.0.0.1:7890`
- SOCKS5 Proxy：`socks5h://127.0.0.1:7891`

---

## 基准测试脚本 `aiperf.py`

### 工作原理

1. **Tokenizer 预检**：启动时自动探测 `--model-path` 下的本地 tokenizer 是否可加载。若不可用，自动切换为 `--use-server-token-count` 模式（使用服务端 token 计数）。
2. **服务健康检查**：对 `<service-url>/health` 发请求，最多重试 30 次。
3. **并发扫描**：按 `--concurrencies` 列表逐个运行 aiperf，每轮间隔 5 秒。
4. **结果保存**：每个并发度的结果保存至独立子目录 `<output-dir>/c<N>/`。

> **模型路径说明**
>
> | 参数 | 含义 | 示例 |
> |------|------|------|
> | `--model-path` | 容器内本地文件路径，用于加载 tokenizer | `/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B` |
> | `--served-model-name` | 服务端 API 识别的模型名，用于 `-m` 请求参数 | `/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B` |

### 命令行参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--model-path` | `/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B` | 本地 tokenizer 路径 |
| `--served-model-name` | `/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B` | API 请求中使用的模型名 |
| `--service-url` | `http://127.0.0.1:8000` | 推理服务地址 |
| `--isl` | `500` | 输入序列长度均值（tokens） |
| `--osl` | `20` | 输出序列长度均值（tokens） |
| `--stddev` | `0` | 输入序列长度标准差 |
| `--concurrencies` | `101,201,301,401` | 并发度扫描列表（逗号分隔） |
| `--deployment-name` | `disagg` | 部署名称（影响输出子目录命名） |
| `--output-dir` | `<脚本目录>/temp` | 结果保存根目录 |
| `--use-server-token-count` | `false` | 强制使用服务端 token 计数（跳过本地 tokenizer） |

### 使用示例

**使用默认参数运行（自动探测 tokenizer）：**

```bash
python k8s/dynamo-deploy/benchmark/aiperf.py
```

**对指定服务地址运行，自定义并发度和序列长度：**

```bash
python k8s/dynamo-deploy/benchmark/aiperf.py \
  --service-url http://localhost:8001 \
  --isl 5000 \
  --osl 100 \
  --concurrencies 1,50,100,200 \
  --deployment-name disagg-rdma
```

**强制跳过本地 tokenizer（无合成输入）：**

```bash
python k8s/dynamo-deploy/benchmark/aiperf.py \
  --use-server-token-count \
  --service-url http://localhost:8000
```

**自定义输出目录：**

```bash
python k8s/dynamo-deploy/benchmark/aiperf.py \
  --output-dir /workspace/results \
  --service-url http://localhost:8001
```

### 输出目录结构

```
<output-dir>/
└── <deployment-name>_isl<ISL>_osl<OSL>/
    ├── c101/                          # 并发度 101 的结果
    │   ├── profile_export.jsonl
    │   ├── profile_export_aiperf.csv
    │   ├── profile_export_aiperf.json
    │   ├── server_metrics_export.csv
    │   ├── server_metrics_export.json
    │   ├── gpu_telemetry_export.jsonl
    │   └── logs/
    │       └── aiperf.log
    ├── c201/
    ├── c301/
    └── c401/
```

---

## 与 Kubernetes 部署联动

`../setup.sh` 中描述了完整的 K8s 联调流程：

```bash
# 1. 部署服务（在宿主机执行）
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d.yaml
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d_rdma.yaml

# 2. 端口转发
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-frontend 8000:8000 &
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-rdma-frontend 8001:8000 &

# 3. 进入容器执行基准测试
bash k8s/dynamo-deploy/benchmark/start-container.sh

# 容器内：
python ./k8s/dynamo-deploy/benchmark/aiperf.py \
  --output-dir /workspace/results \
  --service-url http://localhost:8001   # RDMA 部署

python ./k8s/dynamo-deploy/benchmark/aiperf.py \
  --output-dir /workspace/results \
  --service-url http://localhost:8000   # 普通部署
```

---

## 构建自定义镜像

若需修改基础镜像，在项目根目录执行：

```bash
bash k8s/dynamo-deploy/benchmark/buildx.sh
```

构建参数：
- 代理：通过 `host.docker.internal:7890/7891` 透传主机代理
- UID/GID：与宿主机用户一致（避免文件权限问题）
- 镜像标签：`dynamo-vllm-local-dev:v1.0.1`

---

## 常见问题

**Q: 提示 `PermissionError` 无法创建 temp 目录**

手动创建输出目录后重试：
```bash
mkdir -p k8s/dynamo-deploy/benchmark/temp
```

**Q: Tokenizer 加载失败（`Tokenizer Configuration Error`）**

脚本会自动切换到 `--use-server-token-count` 模式。若希望使用合成输入（synthetic input），请确认 `--model-path` 指向容器内可访问的本地路径（如 `/models/...`），而非 NFS 路径（`/nfs/nfs/...`）。

**Q: 服务 health check 超时**

确认端口转发正常运行，或检查服务 Pod 状态：
```bash
kubectl -n dynamo-system get pods -o wide
```
