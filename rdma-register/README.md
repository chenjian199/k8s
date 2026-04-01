# RDMA 网络注册配置

本目录包含在 Kubernetes 集群中为部署配置 RoCE（RDMA over Converged Ethernet）网络的完整方案，基于 NVIDIA Network Operator + Multus CNI + NV-IPAM 实现多 RDMA 网卡的二级网络注册与 Pod 绑定。

---

## 目录结构

```
rdma-register/
├── setup.sh                          # 完整操作手册（安装/验证/卸载）
├── recipes/
│   ├── nicclusterpolicy.yaml         # NIC 集群策略（RDMA 设备插件 + IPAM + Multus）
│   ├── macvlan-networks.yaml         # MacVLAN 二级网络定义（roce0~roce9，共 10 张网卡）
│   ├── macvlan-ippools.yaml          # NV-IPAM IP 地址池（每卡独立 /24 子网）
│   └── sriov-node-policy.yaml        # （备用）SR-IOV 节点策略
└── examples/
    ├── test-single.yaml              # 单卡测试 Pod（每 Pod 挂载 2 张 RDMA 网卡）
    └── test-agg.yaml                 # 聚合测试 Pod（每 Pod 挂载全部 10 张 RDMA 网卡）
```

---

## 架构说明

### 网卡与资源映射


| 资源名             | 网卡接口          | IP 子网             | 网关             |
| --------------- | ------------- | ----------------- | -------------- |
| `rdma_roce0`    | `h3cnic0`     | `172.16.100.0/24` | `172.16.100.1` |
| `rdma_roce1`    | `h3cnic1`     | `172.16.101.0/24` | `172.16.101.1` |
| `rdma_roce2`    | `h3cnic2`     | `172.16.102.0/24` | `172.16.102.1` |
| `rdma_roce3`    | `h3cnic3`     | `172.16.103.0/24` | `172.16.103.1` |
| `rdma_roce4`    | `h3cnic4`     | `172.16.104.0/24` | `172.16.104.1` |
| `rdma_roce5`    | `h3cnic5`     | `172.16.105.0/24` | `172.16.105.1` |
| `rdma_roce6`    | `h3cnic6`     | `172.16.106.0/24` | `172.16.106.1` |
| `rdma_roce7`    | `h3cnic7`     | `172.16.107.0/24` | `172.16.107.1` |
| `rdma_roce8`    | `enp157s0np0` | `172.16.108.0/24` | `172.16.108.1` |
| `rdma_roce9`    | `enp27s0np0`  | `172.16.109.0/24` | `172.16.109.1` |
| `rdma_roce`（聚合） | 全部上述接口        | —                 | —              |


每个节点从每个 IP Pool 中分配 50 个地址（`perNodeBlockSize: 50`），MTU 统一设为 9000（Jumbo Frame）。

### 组件依赖

```
NVIDIA Network Operator (v26.1.0)
  ├── rdmaSharedDevicePlugin   → 将 RDMA 网卡暴露为 K8s 扩展资源 rdma/rdma_roceN
  ├── nvIpam                   → 为二级网络分配 IP 地址
  └── secondaryNetwork
        ├── cniPlugins          → CNI 插件基础库
        └── multus              → 多网卡 CNI，允许 Pod 同时挂载多个网络接口
```

---

## 安装步骤

> 所有命令在宿主机（集群管理节点）执行，需要 `kubectl` 和 `helm` 访问权限。

### 第一步：安装 NVIDIA Network Operator

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade -i network-operator nvidia/network-operator \
  -n nvidia-network-operator \
  --create-namespace \
  --version v26.1.0

# 等待所有组件就绪
kubectl -n nvidia-network-operator get pods
```

### 第二步：部署 NIC 集群策略

```bash
kubectl apply -f k8s/rdma-register/recipes/nicclusterpolicy.yaml

# 验证策略状态（等待 State: Ready）
kubectl describe nicclusterpolicy nic-cluster-policy

# 验证节点 RDMA 资源已注册
kubectl get node bdsz-node0002.192.168.4.6 -o json | jq '.status.allocatable'
kubectl get node bdsz-node0003.192.168.4.14 -o json | jq '.status.allocatable'
```

预期输出中应包含 `rdma/rdma_roce0` ~ `rdma/rdma_roce9` 等资源字段。

### 第三步：创建 IP 地址池和 MacVLAN 网络

```bash
kubectl apply -f k8s/rdma-register/recipes/macvlan-ippools.yaml
kubectl apply -f k8s/rdma-register/recipes/macvlan-networks.yaml

# 验证 IP 池
kubectl get ippools.nv-ipam.nvidia.com -n nvidia-network-operator

# 验证 MacVLAN 网络（State 应为 Ready）
kubectl get macvlannetwork -A
```

### 第四步：验证 NAD（Network Attachment Definitions）

```bash
kubectl get network-attachment-definitions -A
```

预期在 `dynamo-system` 命名空间下出现 `macvlan-roce0` ~ `macvlan-roce9` 共 10 条记录。

---

## 连通性测试

### 单卡路由测试（每 Pod 挂载 roce0 + roce1）

```bash
kubectl apply -f k8s/rdma-register/examples/test-single.yaml
kubectl get pods -n dynamo-system -o wide | grep rdma

# 进入 node0002 上的测试 Pod
kubectl -n dynamo-system exec -it rdma-test-multus-06 -- bash

# 进入 node0003 上的测试 Pod
kubectl -n dynamo-system exec -it rdma-test-multus-14 -- bash
```

### 聚合路由测试（每 Pod 挂载全部 10 张网卡）

```bash
kubectl apply -f k8s/rdma-register/examples/test-agg.yaml
kubectl get pods -n dynamo-system -o wide | grep rdma

kubectl -n dynamo-system exec -it rdma-test-agg-06 -- bash
kubectl -n dynamo-system exec -it rdma-test-agg-14 -- bash
```

### Pod 内测试步骤

进入测试 Pod 后，依次执行：

```bash
# 1. 安装测试工具
apt-get update
apt-get install -y rdma-core ibverbs-utils perftest infiniband-diags iproute2

# 2. 查看网卡和 RDMA 设备
ip addr           # 确认二级网卡 IP 已分配
rdma link         # 查看 RDMA 链路状态
ibv_devices       # 列出 InfiniBand/RoCE 设备
ibv_devinfo -v | egrep "id|GID"   # 查看 GID 信息

# 3. 带宽测试（mlx5_10 为 RDMA 设备名，根据实际调整）
# 服务端（先执行，在 node0002 上）
ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -R

# 客户端（后执行，在 node0003 上，填入服务端 IP）
ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -R 172.16.100.101
```

### 清理测试 Pod

```bash
kubectl delete -f k8s/rdma-register/examples/test-single.yaml --ignore-not-found=true
kubectl delete -f k8s/rdma-register/examples/test-agg.yaml --ignore-not-found=true
```

---

## 在 Dynamo 推理部署中使用 RDMA

配置完成后，Dynamo 的分离式部署（disaggregated serving）可在 YAML 中通过以下方式申请 RDMA 资源：

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [
        { "name": "macvlan-roce0", "namespace": "dynamo-system" },
        { "name": "macvlan-roce1", "namespace": "dynamo-system" }
      ]
spec:
  containers:
  - resources:
      requests:
        rdma/rdma_roce0: 1
        rdma/rdma_roce1: 1
      limits:
        rdma/rdma_roce0: 1
        rdma/rdma_roce1: 1
    securityContext:
      capabilities:
        add: ["IPC_LOCK"]
```

参考完整示例：`k8s/dynamo-deploy/examples/multi/`

---

## 卸载

```bash
# 删除二级网络和 IP 池
kubectl delete -f k8s/rdma-register/recipes/macvlan-networks.yaml --ignore-not-found=true
kubectl delete -f k8s/rdma-register/recipes/macvlan-ippools.yaml --ignore-not-found=true

# 删除 NIC 集群策略
kubectl delete -f k8s/rdma-register/recipes/nicclusterpolicy.yaml --ignore-not-found=true

# 卸载 Network Operator
helm uninstall network-operator -n nvidia-network-operator
kubectl delete namespace nvidia-network-operator --ignore-not-found=true

# （可选）清理残留 CRD
kubectl delete crd nicclusterpolicies.mellanox.com
kubectl delete crd macvlannetworks.mellanox.com
kubectl delete crd ippools.nv-ipam.nvidia.com
```

---

## 常见问题

**Q: `kubectl get network-attachment-definitions` 没有输出**

NicClusterPolicy 尚未 Ready，或 Multus CNI 未正确安装。检查：

```bash
kubectl -n nvidia-network-operator get pods
kubectl describe nicclusterpolicy nic-cluster-policy
```

**Q: 节点 allocatable 中没有 `rdma/rdma_roceN` 资源**

等待 `rdmaSharedDevicePlugin` Pod 完全启动并完成设备扫描，通常需要 1~2 分钟。确认网卡接口名称与 `nicclusterpolicy.yaml` 中 `ifNames` 一致：

```bash
ip link show | grep -E 'h3cnic|enp'
```

**Q: `ib_write_bw` 连接超时**

确认两端 Pod 的二级网卡 IP 在同一子网，且 GID 路由可达。检查 `ip addr` 输出中是否有 `172.16.10x.xxx` 地址。

**Q: Multus 跨命名空间 NAD 无权访问**

需要为 Multus 授予跨命名空间权限（注意安全影响）：

```bash
kubectl create clusterrolebinding multus-kube-system-cluster-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:multus
```

不再需要时删除：

```bash
kubectl delete clusterrolebinding multus-kube-system-cluster-admin --ignore-not-found=true
```

