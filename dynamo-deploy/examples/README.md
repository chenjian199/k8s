# Dynamo K8s 部署示例

本目录包含基于 `DynamoGraphDeployment` CRD 的 Kubernetes 部署配置，按**单节点**（`single/`）和**多节点**（`multi/`）场景分类，涵盖聚合、P/D 分离（含 KVBM）、RDMA 加速、大模型多节点等完整拓扑。`test-pod.sh` 提供端到端操作手册。

---

## 目录结构

```
examples/
├── test-pod.sh                        # 端到端操作手册（PV/部署/测试/清理）
├── single/                            # 单节点场景（模型和服务在同一节点）
│   ├── model-local-pv.yaml            # PV：hostPath 本地挂载（无 NFS）
│   ├── model-cache.yaml               # PVC：绑定 model-cache-local-pv
│   ├── agg.yaml                       # 聚合部署：Frontend + 1 decode worker
│   └── disagg_kvbm_2p2d.yaml          # P/D 分离 + KVBM：2 Prefill + 2 Decode
└── multi/                             # 多节点场景（跨节点，需 NFS）
    ├── model-pv.yaml                  # PV：NFS 挂载（192.168.4.6:/nfs，700Gi）
    ├── model-cache-nfs.yaml           # PVC：绑定 model-cache-pv（NFS）
    ├── disagg_kvbm_1p1d.yaml          # P/D + KVBM：1P1D，跨节点，TCP 传输
    ├── disagg_kvbm_1p1d_rdma.yaml     # P/D + KVBM：1P1D，跨节点，RDMA 加速
    ├── kimi-k25-agg-kvbm.yaml         # Kimi-K2.5：VLLM 聚合 + NIXL，2x8 GPU
    └── dynamo-vllm-raw.yaml           # DeepSeek-R1：vLLM 多节点 P/D，2×8 GPU
```

---

## 存储配置

所有部署均依赖 PVC 挂载模型文件，部署前须先创建对应的 PV 和 PVC。

### 方案一：NFS 共享存储（多节点推荐）

适用于模型文件已挂载到 NFS 服务器（如 `192.168.4.6:/nfs`）的场景：

```bash
# 创建 PV（NFS）
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/model-pv.yaml

# 创建 PVC
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/model-cache-nfs.yaml
```


| 配置项        | 值                 |
| ---------- | ----------------- |
| PV 名称      | `model-cache-pv`  |
| PVC 名称     | `model-cache-nfs` |
| 容量         | 700Gi             |
| NFS Server | `192.168.4.6`     |
| NFS 路径     | `/nfs`            |
| 容器内挂载点     | `/nfs`            |


### 方案二：本地 hostPath（单节点，无 NFS）

适用于模型文件已存在于节点本地 `/mnt/share` 的场景：

```bash
# 创建 PV（hostPath）
kubectl apply -f ./dynamo-deploy/examples/single/model-local-pv.yaml -n dynamo-system

# 创建 PVC
kubectl apply -f ./dynamo-deploy/examples/single/model-cache.yaml -n dynamo-system
```


| 配置项    | 值                      |
| ------ | ---------------------- |
| PV 名称  | `model-cache-local-pv` |
| PVC 名称 | `model-cache`          |
| 容量     | 700Gi                  |
| 宿主机路径  | `/mnt/share`           |
| 容器内挂载点 | `/mnt/share`           |


验证：

```bash
kubectl get pv -n dynamo-system | grep model
kubectl get pvc -n dynamo-system | grep model
```

---

## 部署示例详解

### 1. 聚合部署（`single/agg.yaml`）

**最简单的推理拓扑**：Frontend + 1 个 vLLM Decode Worker，适合功能验证和低并发场景。

```
Frontend (bdsz-node0002) ──▶ VllmDecodeWorker (bdsz-node0002, 1 GPU)
```


| 参数  | 值                                             |
| --- | --------------------------------------------- |
| 模型  | DeepSeek-R1-Distill-Llama-8B                  |
| 镜像  | `nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1` |
| GPU | 1                                             |
| PVC | `model-cache`（hostPath）                       |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/single/agg.yaml
kubectl -n dynamo-system port-forward svc/vllm-agg-frontend 8000:8000 &
```

---

### 2. P/D 分离 + KVBM 2P2D（`single/disagg_kvbm_2p2d.yaml`）

**单节点高吞吐拓扑**：2 个 Prefill Worker + 2 个 Decode Worker，通过 KVBM（KV Block Manager）在 Prefill 节点缓存 100GB CPU KV 缓存，使用 NixlConnector + PdConnector 进行 KV 传输。

```
Frontend ──▶ VllmPrefillWorker ×2 (KVBM, 100GB CPU cache)
                    │ NixlConnector / PdConnector
             VllmDecodeWorker ×2
```


| 组件                | 副本数 | GPU | 关键配置                                                                                      |
| ----------------- | --- | --- | ----------------------------------------------------------------------------------------- |
| Frontend          | 1   | 0   | 离线模式（HF_HUB_OFFLINE=1）                                                                    |
| VllmDecodeWorker  | 2   | 1   | `--disaggregation-mode decode`，NixlConnector                                              |
| VllmPrefillWorker | 2   | 1   | `--disaggregation-mode prefill`，KVBM+Nixl+Dynamo 三层 Connector，`DYN_KVBM_CPU_CACHE_GB=100` |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/single/disagg_kvbm_2p2d.yaml
```

---

### 3. P/D 分离 + KVBM 1P1D（跨节点，TCP）（`multi/disagg_kvbm_1p1d.yaml`）

**跨节点 P/D 分离**：Prefill 和 Decode 部署在不同节点，通过 NFS 共享模型文件，KV Cache 通过 NixlConnector（TCP）传输。

```
Frontend (node0002) ──▶ VllmDecodeWorker (node0002, 1 GPU)
                               │ NixlConnector (TCP)
                        VllmPrefillWorker (node0003, 1 GPU, KVBM 100GB)
```


| 组件                | 节点              | GPU | 内存限制  |
| ----------------- | --------------- | --- | ----- |
| Frontend          | `bdsz-node0002` | 0   | —     |
| VllmDecodeWorker  | `bdsz-node0002` | 1   | —     |
| VllmPrefillWorker | `bdsz-node0003` | 1   | 100Gi |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d.yaml
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-frontend 8000:8000 &
```

---

### 4. P/D 分离 + KVBM 1P1D（跨节点，RDMA）（`multi/disagg_kvbm_1p1d_rdma.yaml`）

与上一示例相同拓扑，但在 Prefill 和 Decode Worker 上额外申请 **RDMA 资源**（`rdma/rdma_roce0`），通过 RoCE 网卡加速 KV Cache 跨节点传输，大幅降低传输延迟。

> **前置条件**：需完成 [rdma-register](../../rdma-register/README.md) 和 [multus-webhook](../../multus-webhook/README.md) 的配置。


| 组件                | 节点              | GPU | RDMA 资源              |
| ----------------- | --------------- | --- | -------------------- |
| VllmDecodeWorker  | `bdsz-node0002` | 1   | `rdma/rdma_roce0: 1` |
| VllmPrefillWorker | `bdsz-node0003` | 1   | `rdma/rdma_roce0: 1` |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d_rdma.yaml
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-rdma-frontend 8001:8000 &
```

---

### 5. Kimi-K2.5 聚合部署（`multi/kimi-k25-agg-kvbm.yaml`）

**大模型多节点聚合**：使用 VLLM后端部署 Kimi-K2.5（GPTQ 4-bit），双节点各 8 GPU（共 16 GPU），通过 NixlConnector + RDMA 互联。

```
Frontend (node0002) ──▶ vllmDecodeWorker (node0002+node0003, 8 GPU/节点)
                              │ multinode: nodeCount=2, TP=16
                              │ RDMA: rdma/rdma_roce=8
```


| 参数      | 值                                                  |
| ------- | -------------------------------------------------- |
| 后端      | VLLM                                               |
| 模型      | `/nfs/kimi-K2.5-NVFP4`                             |
| GPU     | 8/节点 × 2 节点 = 16 GPU                               |
| RDMA    | `rdma/rdma_roce: 8`                                |
| TP Size | 16                                                 |
| 推理解析器   | `kimi_k25` + `kimi_k2`                             |
| 共享内存    | 80Gi                                               |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/kimi-k25-agg-kvbm.yaml
```

---

### 6. DeepSeek-R1 多节点 P/D 分离（`multi/dynamo-vllm-raw.yaml`）

**超大模型多节点 P/D 分离**：DeepSeek-R1（671B MoE），Prefill 和 Decode 各占 2 节点（2×8=16 GPU），使用 EPLB（Expert Parallel Load Balancing）、DBO（Decode-only Batch Optimization）、DeepEP all2all 后端等高级特性。

```
Frontend ──▶ prefill  (2节点 × 8 GPU, DP=16, all2all=high_throughput)
                 │ NixlConnector (RDMA/IB)
             decode   (2节点 × 8 GPU, DP=16, all2all=low_latency)
```


| 参数    | 值                                        |
| ----- | ---------------------------------------- |
| 模型    | DeepSeek-R1（`deepseek-ai/DeepSeek-R1`）   |
| GPU   | 各 8/节点 × 2 节点（Prefill + Decode 共 32 GPU） |
| 网络    | `rdma/ib: 8`（InfiniBand）                 |
| 数据并行  | DP=16，`enable-expert-parallel`           |
| KV 传输 | NixlConnector                            |
| 特性    | EPLB、DBO、DeepGEMM、CUDA Graph             |


```bash
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/dynamo-vllm-raw.yaml
```

---

## 端到端操作流程（`test-pod.sh`）

`test-pod.sh` 是完整的操作手册，包含以下步骤：

```bash
# 1. 创建存储（NFS 或 hostPath 二选一）
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/model-pv.yaml
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/model-cache-nfs.yaml

# 2. 部署推理服务（普通 TCP 版 + RDMA 版）
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d.yaml
kubectl -n dynamo-system apply -f ./dynamo-deploy/examples/multi/disagg_kvbm_1p1d_rdma.yaml
kubectl -n dynamo-system get pods -o wide

# 3. 端口转发
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-frontend 8000:8000 &
kubectl -n dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-rdma-frontend 8001:8000 &

# 4. 验证服务
curl http://localhost:8000/v1/models
curl http://localhost:8001/v1/models

# 5. 发送推理请求
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

# 6. 性能基准测试（需进入容器）
bash ./dynamo-deploy/benchmark/start-container.sh
# 容器内执行：
python ./k8s/dynamo-deploy/benchmark/aiperf.py \
  --output-dir /workspace/results \
  --service-url http://localhost:8001

# 7. 清理
kubectl -n dynamo-system delete dynamographdeployment vllm-disagg-kvbm-1p1d --ignore-not-found=true
kubectl -n dynamo-system delete dynamographdeployment vllm-disagg-kvbm-1p1d-rdma --ignore-not-found=true
kubectl delete pv model-cache-local-pv
kubectl delete pv model-cache-pv
```

---

## 示例速查表


| 文件                                 | 后端      | 拓扑          | GPU 数 | RDMA | 跨节点 | 适用模型        |
| ---------------------------------- | ------- | ----------- | ----- | ---- | --- | ----------- |
| `single/agg.yaml`                  | vLLM    | 聚合          | 1     | ✗    | ✗   | 中小模型        |
| `single/disagg_kvbm_2p2d.yaml`     | vLLM    | 2P2D + KVBM | 4     | ✗    | ✗   | 中小模型        |
| `multi/disagg_kvbm_1p1d.yaml`      | vLLM    | 1P1D + KVBM | 2     | ✗    | ✓   | 中型模型        |
| `multi/disagg_kvbm_1p1d_rdma.yaml` | vLLM    | 1P1D + KVBM | 2     | ✓    | ✓   | 中型模型        |
| `multi/kimi-k25-agg-kvbm.yaml`     | TRT-LLM | 聚合多节点       | 16    | ✓    | ✓   | Kimi-K2.5   |
| `multi/dynamo-vllm-raw.yaml`       | vLLM    | P/D 多节点     | 32    | ✓    | ✓   | DeepSeek-R1 |


---

## 相关文档

- [基准测试工具](../benchmark/README.md) — `aiperf.py` 使用说明
- [RDMA 网络配置](../../rdma-register/README.md) — RoCE 网卡注册，RDMA 示例的前置条件
- [Multus Webhook](../../multus-webhook/README.md) — 自动注入 RDMA 网络注解

