# RDMA 网络资源配置清单

本目录包含在 Kubernetes 集群中注册和管理 RDMA（RoCE）网络资源所需的全部 CRD 配置文件，按照**安装顺序**依次应用即可完成从设备插件到二级网络的完整配置。

---

## 文件列表与应用顺序

```
recipes/
├── nicclusterpolicy.yaml     # Step 1：配置 NIC 集群策略（设备插件 + IPAM + Multus）
├── macvlan-ippools.yaml      # Step 2：配置各网卡的 IP 地址池
├── macvlan-networks.yaml     # Step 3：创建 MacVLAN 二级网络（NAD）
└── sriov-node-policy.yaml    # （可选）SR-IOV 节点策略（备用方案）
```

---

## `nicclusterpolicy.yaml` — NIC 集群策略

**作用**：通过 NVIDIA Network Operator 的 `NicClusterPolicy` CRD，一次性配置三个子系统：RDMA 设备插件、NV-IPAM 地址管理、Multus 多网卡 CNI。

### 字段说明

```yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy   # 固定名称，Network Operator 会识别该名称
```

#### `spec.rdmaSharedDevicePlugin` — RDMA 共享设备插件

将宿主机的 RDMA 网卡暴露为 Kubernetes 扩展资源（`rdma/rdma_roceN`），供 Pod 通过 `resources.limits` 申请。

```yaml
spec:
  rdmaSharedDevicePlugin:
    image: k8s-rdma-shared-dev-plugin        # 镜像名（不含仓库地址）
    repository: nvcr.io/nvidia/mellanox      # 镜像仓库地址
    version: network-operator-v26.1.0        # 与 Network Operator 版本对应
    imagePullSecrets: []                      # 私有仓库密钥，公开镜像留空

    config: |                                 # JSON 格式的设备发现规则
      {
        "configList": [
          {
            "resourceName": "rdma_roce",      # 资源名，Pod 中通过 rdma/rdma_roce 申请
                                              # 聚合资源：包含下方所有接口，申请1个即可使用全部网卡
            "rdmaHcaMax": 1024,               # 单节点该资源最大可分配数量（虚拟化上限）
            "selectors": {
              "ifNames": [                    # 通过网卡接口名筛选设备
                "enp157s0np0", "enp27s0np0",  # Mellanox/ConnectX 系列网卡
                "h3cnic0", "h3cnic1", ...     # H3C 定制网卡（h3cnic0~7）
              ]
            }
          },
          {
            "resourceName": "rdma_roce0",     # 单口资源：仅绑定 h3cnic0 这一张网卡
            "rdmaHcaMax": 1024,
            "selectors": {
              "ifNames": ["h3cnic0"]          # 精确匹配单张网卡接口名
            }
          },
          # ... rdma_roce1 ~ rdma_roce9 按同样模式逐卡配置
        ]
      }
```

> **`rdma_roce`（聚合）vs `rdma_roceN`（单口）的区别**：
> - `rdma_roce`：选择器包含全部 10 张网卡接口，申请 1 个单位即获得对所有网卡的 RDMA 访问权
> - `rdma_roce0`~`rdma_roce9`：每个资源只绑定一张网卡，用于精确控制每张网卡的分配

---

#### `spec.nvIpam` — NV-IPAM 地址管理

为 Pod 的二级网络接口自动分配 IP，替代传统 DHCP。

```yaml
spec:
  nvIpam:
    image: nvidia-k8s-ipam                   # IPAM 插件镜像名
    repository: nvcr.io/nvidia/mellanox      # 镜像仓库
    version: network-operator-v26.1.0        # 与 Network Operator 版本保持一致
    imagePullSecrets: []
    enableWebhook: false                     # 是否启用 IPAM Webhook 做请求校验
                                             # 关闭可简化安装，生产环境建议开启
```

---

#### `spec.secondaryNetwork` — 二级网络 CNI 组件

```yaml
spec:
  secondaryNetwork:
    cniPlugins:
      image: plugins                         # CNI 基础插件包（bridge/macvlan/ipvlan 等）
      repository: nvcr.io/nvidia/mellanox
      version: network-operator-v26.1.0

    multus:
      image: multus-cni                      # Multus CNI 主程序
      repository: nvcr.io/nvidia/mellanox   # 允许 Pod 同时挂载多个网络接口
      version: network-operator-v26.1.0
```

---

## `macvlan-ippools.yaml` — IP 地址池

**作用**：为每张 RDMA 网卡定义独立的 IP 子网段，NV-IPAM 从中为 Pod 分配 IP。每个 `IPPool` 对应一张物理网卡。

### 字段说明（以 `rdma-roce0-pool` 为例）

```yaml
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: rdma-roce0-pool                     # 地址池名称，由 MacvlanNetwork 的 poolName 字段引用
  namespace: nvidia-network-operator        # 必须部署在 Network Operator 命名空间
spec:
  subnet: 172.16.100.0/24                   # 该网卡使用的 IP 子网
                                            # 10 张网卡对应 10 个 /24 子网，互不重叠
  perNodeBlockSize: 50                      # 每个节点从该子网中预分配的 IP 数量
                                            # 例：节点1 分配 .1~.50，节点2 分配 .51~.100
  gateway: 172.16.100.1                     # 该子网的默认网关（二层直连时可不用，但需配置）
```

### 各网卡地址池一览

| 地址池名称 | 子网 | 网关 | 对应网卡 |
|------------|------|------|----------|
| `rdma-roce0-pool` | `172.16.100.0/24` | `172.16.100.1` | `h3cnic0` |
| `rdma-roce1-pool` | `172.16.101.0/24` | `172.16.101.1` | `h3cnic1` |
| `rdma-roce2-pool` | `172.16.102.0/24` | `172.16.102.1` | `h3cnic2` |
| `rdma-roce3-pool` | `172.16.103.0/24` | `172.16.103.1` | `h3cnic3` |
| `rdma-roce4-pool` | `172.16.104.0/24` | `172.16.104.1` | `h3cnic4` |
| `rdma-roce5-pool` | `172.16.105.0/24` | `172.16.105.1` | `h3cnic5` |
| `rdma-roce6-pool` | `172.16.106.0/24` | `172.16.106.1` | `h3cnic6` |
| `rdma-roce7-pool` | `172.16.107.0/24` | `172.16.107.1` | `h3cnic7` |
| `rdma-roce8-pool` | `172.16.108.0/24` | `172.16.108.1` | `enp157s0np0` |
| `rdma-roce9-pool` | `172.16.109.0/24` | `172.16.109.1` | `enp27s0np0` |

> **`perNodeBlockSize: 50` 的含义**：整个 /24 子网有 254 个可用 IP，每节点预留 50 个，支持最多 5 个节点共享同一地址池而不冲突。

---

## `macvlan-networks.yaml` — MacVLAN 二级网络

**作用**：为每张 RDMA 网卡创建一个 `MacvlanNetwork`，Network Operator 会自动在指定命名空间生成对应的 `NetworkAttachmentDefinition`（NAD），供 Pod 通过 Multus 注解挂载。

### 字段说明（以 `macvlan-roce0` 为例）

```yaml
apiVersion: mellanox.com/v1alpha1
kind: MacvlanNetwork
metadata:
  name: macvlan-roce0                       # MacVLAN 网络名称
                                            # 同时也是生成的 NAD 名称，Pod 注解中引用此名
spec:
  networkNamespace: "dynamo-system"         # NAD 将被创建在哪个命名空间
                                            # Pod 必须在该命名空间才能使用此网络
  master: "h3cnic0"                         # 绑定的宿主机物理网卡接口名
                                            # MacVLAN 会在此接口上创建虚拟子接口
  mode: "bridge"                            # MacVLAN 工作模式：
                                            #   bridge：同一宿主机的 MacVLAN 接口可互通（推荐）
                                            #   private：接口间完全隔离
                                            #   vepa：流量经物理交换机转发
                                            #   passthru：直接透传物理网卡（独占模式）
  mtu: 9000                                 # 最大传输单元（Jumbo Frame）
                                            # RDMA 传输推荐 9000，避免大包分片
  ipam: |                                   # IP 地址管理配置（JSON 格式）
    {
      "type": "nv-ipam",                    # 使用 NV-IPAM 插件分配 IP
      "poolName": "rdma-roce0-pool"         # 引用 macvlan-ippools.yaml 中定义的地址池
    }
```

### MacVLAN 模式说明

| 模式 | 同主机通信 | 说明 |
|------|-----------|------|
| `bridge` | ✓ | 同一宿主机的不同 Pod 间可直接通信，**推荐用于 RDMA** |
| `private` | ✗ | 完全隔离，只能与外部通信 |
| `vepa` | 经交换机 | 所有流量经物理交换机反射，需要交换机支持 |
| `passthru` | ✓ | 独占物理网卡，性能最高但每张网卡只能挂载一个 Pod |

### 所有网络与网卡对应关系

| MacVLAN 网络名 | 宿主机接口 | IP 地址池 | NAD 所在命名空间 |
|----------------|------------|-----------|-----------------|
| `macvlan-roce0` | `h3cnic0` | `rdma-roce0-pool` | `dynamo-system` |
| `macvlan-roce1` | `h3cnic1` | `rdma-roce1-pool` | `dynamo-system` |
| `macvlan-roce2` | `h3cnic2` | `rdma-roce2-pool` | `dynamo-system` |
| `macvlan-roce3` | `h3cnic3` | `rdma-roce3-pool` | `dynamo-system` |
| `macvlan-roce4` | `h3cnic4` | `rdma-roce4-pool` | `dynamo-system` |
| `macvlan-roce5` | `h3cnic5` | `rdma-roce5-pool` | `dynamo-system` |
| `macvlan-roce6` | `h3cnic6` | `rdma-roce6-pool` | `dynamo-system` |
| `macvlan-roce7` | `h3cnic7` | `rdma-roce7-pool` | `dynamo-system` |
| `macvlan-roce8` | `enp157s0np0` | `rdma-roce8-pool` | `dynamo-system` |
| `macvlan-roce9` | `enp27s0np0` | `rdma-roce9-pool` | `dynamo-system` |

---

## `sriov-node-policy.yaml` — SR-IOV 节点策略（可选）

**作用**：通过 SR-IOV Network Operator 将物理网卡虚拟化为多个 VF（Virtual Function），与上方的 MacVLAN 方案是两种不同的 RDMA 网络虚拟化路线。本集群当前使用 MacVLAN 方案，SR-IOV 作为备用配置保留。

### 字段说明

```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: rdma-mlx5-pfs                       # 策略名称
  namespace: nvidia-network-operator        # 必须部署在 Network Operator 命名空间
spec:
  nodeSelector:
    sriov: enabled                          # 仅在打了此标签的节点上启用 SR-IOV
                                            # 需手动给节点加标签：
                                            # kubectl label node <node> sriov=enabled

  resourceName: rdma_net                    # 暴露给 K8s 的扩展资源名
                                            # Pod 通过 intel.com/rdma_net 申请

  numVfs: 16                                # 每张物理网卡（PF）创建的虚拟功能（VF）数量
                                            # 每个 VF 可被独立分配给一个 Pod

  deviceType: netdevice                     # VF 设备类型：
                                            #   netdevice：作为普通网络设备（推荐）
                                            #   vfio-pci：作为 VFIO 设备（用于 DPDK）

  isRdma: true                              # 启用 RDMA 功能（必须为 true 才能使用 RDMA）

  mtu: 9000                                 # VF 的 MTU，与 MacVLAN 方案保持一致

  nicSelector:
    pfNames:                                # 选择要虚拟化的物理网卡（PF）接口名列表
    - enp60s0f0np0                          # 格式通常为 <设备路径>f<功能号>np<端口号>
    - enp60s0f1np1
    - enp77s0f0np0
    - enp77s0f1np1
    - enp188s0f0np0
    - enp188s0f1np1
    - enp220s0f0np0
    - enp220s0f1np1
```

### MacVLAN vs SR-IOV 对比

| 特性 | MacVLAN（当前方案） | SR-IOV（备用方案） |
|------|--------------------|--------------------|
| 实现层次 | 软件层（内核 MacVLAN 驱动） | 硬件层（网卡固件 VF） |
| 性能 | 接近线速 | 接近裸金属（更低延迟） |
| 配置复杂度 | 低 | 高（需硬件支持，BIOS 开启 SR-IOV） |
| 网卡独占 | 否（多 Pod 共享同一 PF） | 否（每个 VF 独立分配） |
| 依赖组件 | Network Operator + Multus | SR-IOV Network Operator |

---

## 应用顺序

```bash
# Step 1：配置设备插件、IPAM 和 Multus
kubectl apply -f recipes/nicclusterpolicy.yaml
# 等待 State: Ready
kubectl describe nicclusterpolicy nic-cluster-policy

# Step 2：创建 IP 地址池
kubectl apply -f recipes/macvlan-ippools.yaml
kubectl get ippools.nv-ipam.nvidia.com -n nvidia-network-operator

# Step 3：创建 MacVLAN 二级网络（自动生成 NAD）
kubectl apply -f recipes/macvlan-networks.yaml
kubectl get network-attachment-definitions -n dynamo-system
```

---

## 相关文档

- [RDMA 注册总体流程](../README.md)
- [Multus Webhook](../../multus-webhook/README.md) — 自动注入 Pod 网络注解
