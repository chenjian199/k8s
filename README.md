# Kubernetes 配置与部署

本目录包含 Dynamo 推理服务在 Kubernetes 集群上的完整基础设施配置，涵盖集群环境初始化、RDMA 高性能网络、Dynamo 平台安装、推理服务部署示例、API 网关以及辅助工具。

---

## 目录结构总览

```
k8s/
├── basic-env/           # 集群基础环境初始化（kubeadm、Containerd、GPU Operator）
├── nfs/                 # NFS 模型存储配置（服务端导出 + 客户端挂载）
├── rdma-register/       # RDMA/RoCE 网络注册（Network Operator + MacVLAN + IPPool）
├── multus-webhook/      # Mutating Webhook（自动为 Dynamo Worker Pod 注入 RDMA 网络注解）
├── dynamo-deploy/       # Dynamo 平台安装与推理服务部署
│   ├── deploy/          # dynamo-platform Helm Chart 安装（Grove + KAI + Dynamo Operator）
│   ├── examples/        # DynamoGraphDeployment CRD 部署示例（单节点/多节点）
│   └── benchmark/       # 推理性能基准测试工具（aiperf.py）
└── apache-apisix/       # Apache APISIX API 网关（限流、认证、路由）
```

---

## 推荐部署顺序

```
1. basic-env      →  集群初始化，安装 GPU Operator / Multus CNI
2. nfs            →  配置 NFS 共享存储，挂载模型文件
3. rdma-register  →  注册 RDMA 网卡资源，创建 MacVLAN 二级网络
4. multus-webhook →  部署 Webhook，自动注入 Pod RDMA 网络注解
5. dynamo-deploy/deploy    →  安装 dynamo-platform（Helm）
6. dynamo-deploy/examples  →  部署推理服务（DynamoGraphDeployment）
7. dynamo-deploy/benchmark →  运行性能基准测试
8. apache-apisix  →  （可选）部署 API 网关，对外暴露推理接口
```

---

## 各目录说明

### [basic-env](./basic-env/) — 集群基础环境

Kubernetes 集群从零初始化所需的全部脚本。

| 文件/目录 | 说明 |
|-----------|------|
| `init-k8s.sh` | kubeadm init/join，Containerd 配置，网络插件安装 |
| `install-plugin/nvidia-gpu-operate.sh` | NVIDIA GPU Operator 安装 |
| `install-plugin/nvidia-gpu-plugin.sh` | NVIDIA Device Plugin 安装 |
| `install-plugin/multus.sh` | Multus CNI 安装与跨命名空间权限配置 |
| `get-status.sh` / `get-resource.sh` | 集群状态与资源查看工具 |
| `attach-pods.sh` | 批量进入 Pod 调试工具 |
| `config/containerd-config.toml` | Containerd 运行时配置（含 NVIDIA 运行时） |

详见 [basic-env/README.md](./basic-env/README.md)

---

### [nfs](./nfs/) — NFS 模型存储

在集群节点间共享模型文件（`/mnt/share` → NFS `/nfs`），供 Dynamo Pod 通过 PV/PVC 挂载。

| 文件 | 说明 |
|------|------|
| `setup.sh` | 服务端安装 `nfs-kernel-server`、配置导出；客户端挂载 `192.168.4.6:/nfs` |

详见 [nfs/README.md](./nfs/README.md)

---

### [rdma-register](./rdma-register/) — RDMA 网络注册

基于 NVIDIA Network Operator 注册 RoCE 网卡资源，为 Dynamo P/D 分离部署提供高性能 KV Cache 跨节点传输通道。

| 文件/目录 | 说明 |
|-----------|------|
| `setup.sh` | 完整操作手册（安装、验证、连通性测试、卸载） |
| `recipes/nicclusterpolicy.yaml` | NIC 集群策略（RDMA 设备插件 + NV-IPAM + Multus） |
| `recipes/macvlan-ippools.yaml` | 10 张网卡各自的 IP 地址池（`172.16.100.0/24` ~ `172.16.109.0/24`） |
| `recipes/macvlan-networks.yaml` | MacVLAN 二级网络定义（`macvlan-roce0` ~ `macvlan-roce9`） |
| `recipes/sriov-node-policy.yaml` | SR-IOV 节点策略（备用方案） |
| `examples/test-single.yaml` | 单卡路由测试 Pod（挂载 roce0 + roce1） |
| `examples/test-agg.yaml` | 聚合路由测试 Pod（挂载全部 10 张网卡） |

详见 [rdma-register/README.md](./rdma-register/README.md) · [recipes/README.md](./rdma-register/recipes/README.md)

---

### [multus-webhook](./multus-webhook/) — RDMA 网络注解自动注入

Kubernetes Mutating Admission Webhook，自动为带有 `nvidia.com/dynamo-component-type: worker` 标签且申请了 RDMA 资源的 Pod 注入 `k8s.v1.cni.cncf.io/networks` 注解，免去在每个部署 YAML 中手动配置网卡绑定。

| 文件 | 说明 |
|------|------|
| `webhook.py` | Flask HTTPS 服务，核心注入逻辑 |
| `Dockerfile` | 镜像构建（`webhook:v6`） |
| `multus_webhook_deploy.yaml` | Deployment + Service（443→8443） |
| `multus_webhook_mwc.yaml` | MutatingWebhookConfiguration |
| `setup.sh` | 完整操作手册（构建镜像、生成证书、部署、测试、卸载） |
| `csr.conf` / `cert.conf` | TLS 证书 CSR 与 SAN 配置 |
| `ca.crt` / `tls.crt` 等 | 已生成的证书文件 |
| `test.yaml` | 功能验证 Pod（覆盖聚合模式和单口模式） |

详见 [multus-webhook/README.md](./multus-webhook/README.md)

---

### [dynamo-deploy/deploy](./dynamo-deploy/deploy/) — Dynamo 平台安装

通过 Helm 安装 `dynamo-platform`，包含 Grove（拓扑调度）、KAI Scheduler（GPU 队列调度）、Dynamo Operator（CRD + 控制器）、etcd、NATS 全栈组件。

| 文件 | 说明 |
|------|------|
| `setup.sh` | 完整安装手册（Chart 下载、Grove/KAI/dynamo-platform 安装、CRD 冲突处理、NFS 配置、镜像预拉取、完整卸载流程） |

详见 [dynamo-deploy/deploy/README.md](./dynamo-deploy/deploy/README.md)

---

### [dynamo-deploy/examples](./dynamo-deploy/examples/) — 推理服务部署示例

基于 `DynamoGraphDeployment` CRD 的完整推理拓扑示例，覆盖单节点到多节点、vLLM 到 TRT-LLM、TCP 到 RDMA 各种场景。

| 文件 | 模型 | 拓扑 | GPU | RDMA |
|------|------|------|-----|------|
| `single/agg.yaml` | DeepSeek-R1-Distill-8B | 聚合 | 1 | ✗ |
| `single/disagg_kvbm_2p2d.yaml` | DeepSeek-R1-Distill-8B | 2P2D + KVBM | 4 | ✗ |
| `multi/disagg_kvbm_1p1d.yaml` | DeepSeek-R1-Distill-8B | 1P1D + KVBM 跨节点 | 2 | ✗ |
| `multi/disagg_kvbm_1p1d_rdma.yaml` | DeepSeek-R1-Distill-8B | 1P1D + KVBM + RDMA | 2 | ✓ |
| `multi/kimi-k25-agg-kvbm.yaml` | Kimi-K2.5（TRT-LLM） | 聚合多节点 | 16 | ✓ |
| `multi/dynamo-vllm-raw.yaml` | DeepSeek-R1（671B） | P/D 多节点 | 32 | ✓ |

详见 [dynamo-deploy/examples/README.md](./dynamo-deploy/examples/README.md)

---

### [dynamo-deploy/benchmark](./dynamo-deploy/benchmark/) — 性能基准测试

基于 `aiperf` 的推理性能扫描工具，支持并发度扫描、自动 tokenizer 探测、结果按目录归档。

| 文件 | 说明 |
|------|------|
| `aiperf.py` | 核心测试脚本（并发扫描 + 健康检查 + 自动回退） |
| `start-container.sh` | 启动本地开发容器（`chenjian110/dynamo:vllm-v1.0.1`） |
| `buildx.sh` | 构建本地 Docker 镜像 |
| `setup-source-code.sh` | 容器内编译源码与 Python 包 |
| `set-proxy.sh` | 配置 HTTP/SOCKS5 代理 |

详见 [dynamo-deploy/benchmark/README.md](./dynamo-deploy/benchmark/README.md)

---

### [apache-apisix](./apache-apisix/) — API 网关

Apache APISIX 部署与配置，用于对外暴露 Dynamo 推理接口，提供认证、多层限流和路由管理。

| 文件/目录 | 说明 |
|-----------|------|
| `setup.sh` | APISIX 服务启动脚本 |
| `config/apisix.yaml` | APISIX 主配置（etcd 地址、端口、插件列表） |
| `launch/admin-account.sh` | 创建 30 个预配置用户及 Key Auth 密钥 |
| `launch/add-route.sh` | 路由配置（推理接口路由 + 限流插件绑定） |
| `launch/add-group.sh` | Consumer Group 配置（多层限流策略） |
| `launch/test.sh` | 接口功能验证脚本 |
| `launch/benchmark.sh` | 限流性能测试脚本 |

详见 [apache-apisix/README.md](./apache-apisix/README.md)

---

## 相关资源

- [NVIDIA Network Operator 文档](https://docs.mellanox.com/display/COKAN10/Network+Operator)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Apache APISIX](https://apisix.apache.org/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Dynamo 官方文档](https://docs.nvidia.com/dynamo/)
