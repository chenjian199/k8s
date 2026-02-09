# RDMA 网络注册配置

本目录包含用于在 Kubernetes 集群中配置和管理 RDMA（Remote Direct Memory Access）网络的 YAML 配置文件。这些配置文件主要用于设置 Multus CNI、SR-IOV、NVIDIA Network Operator 以及相关的网络资源。

## 文件说明

### 1. multus-token.yaml
**用途**: 为 Multus CNI 配置 Token 请求权限

**内容**:
- 创建 `ClusterRole`，允许创建 ServiceAccount token
- 创建 `ClusterRoleBinding`，将权限绑定到 `kube-system` 命名空间中的 `multus` ServiceAccount

**使用场景**: 当 Multus 需要使用 Token 进行身份验证时，需要应用此配置文件。

**部署命令**:
```bash
kubectl apply -f multus-token.yaml
```

---

### 2. service-account.yaml
**用途**: 为 Multus CNI 创建 ServiceAccount 和 RBAC 权限

**内容**:
- 创建 `multus` ServiceAccount（位于 `kube-system` 命名空间）
- 创建 `ClusterRole`，授予以下权限：
  - 读取 Pod、Namespace 资源
  - 更新/补丁 Pod 资源（用于写入网络状态）
  - 读取 NetworkAttachmentDefinition 资源
- 创建 `ClusterRoleBinding`，将权限绑定到 ServiceAccount

**使用场景**: 这是 Multus CNI 运行所需的基础权限配置，必须在部署 Multus 之前应用。

**部署命令**:
```bash
kubectl apply -f service-account.yaml
```

---

### 3. multus-daemonset-thick.yml
**用途**: 部署 Multus CNI 的 DaemonSet

**内容**:
- 创建 `NetworkAttachmentDefinition` CRD
- 创建 Multus 相关的 RBAC 资源
- 创建 `ConfigMap` 用于 Multus daemon 配置
- 部署 `DaemonSet`，在每个节点上运行 Multus CNI

**关键特性**:
- 使用 "thick" 模式部署（包含所有依赖）
- 自动安装 Multus 二进制文件到 `/opt/cni/bin`
- 配置了必要的卷挂载和权限

**使用场景**: 这是 Multus CNI 的核心部署文件，用于在集群中启用多网络支持。

**部署命令**:
```bash
kubectl apply -f multus-daemonset-thick.yml
```

**注意事项**: 
- 此文件包含完整的 Multus 部署，如果使用其他方式安装 Multus（如通过 Operator），可能不需要此文件。

---

### 4. nic-cluster-policy.yaml
**用途**: 配置 NVIDIA Network Operator 的集群策略

**内容**:
- 配置 OFED（OpenFabrics Enterprise Distribution）驱动镜像
- 配置 NV-IPAM（NVIDIA IPAM）组件
- 配置 Secondary Network 相关的 CNI 插件和 Multus 镜像

**关键配置**:
- OFED 驱动版本: `doca3.1.0-25.07-0.9.7.0-0`
- Network Operator 版本: `v25.7.0`
- 所有镜像均来自 `nvcr.io/nvidia/mellanox`

**使用场景**: 当使用 NVIDIA Network Operator 管理网络设备时，需要配置此策略来指定使用的驱动和插件版本。

**部署命令**:
```bash
kubectl apply -f nic-cluster-policy.yaml
```

**前置条件**: 需要先安装 NVIDIA Network Operator。

---

### 5. rdma-nic-cluster-policy.yaml
**用途**: 配置 RDMA 共享设备插件（RDMA Shared Device Plugin）

**内容**:
- 配置 `rdmaSharedDevicePlugin`，用于将 RDMA 设备作为 Kubernetes 资源暴露
- 定义了多个 RDMA 资源（roce5 到 roce15），每个对应一个物理网卡接口
- 每个资源配置了最大 RDMA HCA 数量（1024）和对应的网卡接口名称

**资源映射**:
- `roce5`: `enp157s0np0`
- `roce7`: `enp27s0np0`
- `roce8`: `enp188s0f0np0`
- `roce9`: `enp188s0f1np1`
- `roce10`: `enp220s0f0np0`
- `roce11`: `enp220s0f1np1`
- `roce12`: `enp77s0f0np0`
- `roce13`: `enp77s0f1np1`
- `roce14`: `enp60s0f0np0`
- `roce15`: `enp60s0f1np1`

**使用场景**: 当需要在 Pod 中请求 RDMA 设备资源时，需要配置此策略。Pod 可以通过 `rdma/<resourceName>` 的形式请求 RDMA 设备。

**部署命令**:
```bash
kubectl apply -f rdma-nic-cluster-policy.yaml
```

---

### 6. sriov-node-policy.yaml
**用途**: 配置 SR-IOV 网络节点策略

**内容**:
- 为指定的物理网卡（PF）创建虚拟功能（VF）
- 配置 RDMA 支持（`isRdma: true`）
- 设置 MTU 为 9000（巨型帧）
- 每个 PF 创建 16 个 VF
- 资源名称为 `rdma_net`

**配置的网卡**:
- `enp60s0f0np0`, `enp60s0f1np1`
- `enp77s0f0np0`, `enp77s0f1np1`
- `enp188s0f0np0`, `enp188s0f1np1`
- `enp220s0f0np0`, `enp220s0f1np1`

**使用场景**: 当需要使用 SR-IOV 技术将物理网卡虚拟化，并在容器中使用 VF 时，需要配置此策略。

**部署命令**:
```bash
kubectl apply -f sriov-node-policy.yaml
```

**注意事项**: 
- 需要节点具有 `sriov: enabled` 标签
- 此配置会创建 VF，可能需要重启节点或重新加载驱动

---

### 7. rdma-macvlan-networks.yaml
**用途**: 创建 Macvlan 网络定义，用于 RDMA 网络

**内容**:
- 创建 `rdma-networks` 命名空间
- 创建 11 个 MacvlanNetwork 资源（roce5 到 roce15）
- 每个网络配置：
  - 主接口（master interface）
  - 桥接模式（bridge mode）
  - MTU 9000
  - IPAM 使用 whereabouts，分配指定 IP 范围

**网络配置**:
| 网络名称 | 主接口 | IP 范围 | IP 分配范围 |
|---------|--------|---------|------------|
| roce5 | enp157s0np0 | 192.168.5.0/24 | 192.168.5.200-250 |
| roce7 | enp27s0np0 | 192.168.7.0/24 | 192.168.7.200-250 |
| roce8 | enp188s0f0np0 | 192.168.8.0/24 | 192.168.8.200-250 |
| roce9 | enp188s0f1np1 | 192.168.9.0/24 | 192.168.9.200-250 |
| roce10 | enp220s0f0np0 | 192.168.10.0/24 | 192.168.10.200-250 |
| roce11 | enp220s0f1np1 | 192.168.11.0/24 | 192.168.11.200-250 |
| roce12 | enp77s0f0np0 | 192.168.12.0/24 | 192.168.12.200-250 |
| roce13 | enp77s0f1np1 | 192.168.13.0/24 | 192.168.13.200-250 |
| roce14 | enp60s0f0np0 | 192.168.14.0/24 | 192.168.14.200-250 |
| roce15 | enp60s0f1np1 | 192.168.15.0/24 | 192.168.15.200-250 |

**使用场景**: 当 Pod 需要通过 Multus 附加多个 RDMA 网络接口时，需要先创建这些网络定义。Pod 可以通过注解引用这些网络。

**部署命令**:
```bash
kubectl apply -f rdma-macvlan-networks.yaml
```

---

### 8. rdma-test.yaml
**用途**: 测试 Pod，用于验证 RDMA 网络配置

**内容**:
- 创建两个测试 Pod（`rdma-test-multus-06` 和 `rdma-test-multus-14`）
- 每个 Pod 配置：
  - 通过 Multus 注解附加 10 个 RDMA 网络（roce5 到 roce15）
  - 请求对应的 RDMA 资源（`rdma/roce5` 到 `rdma/roce15`）
  - 请求 1 个 GPU 资源
  - 使用 CUDA 基础镜像

**Pod 配置**:
- `rdma-test-multus-06`: 调度到节点 `bdsz-node0001.192.168.4.6`
- `rdma-test-multus-14`: 调度到节点 `bdsz-node0002.192.168.4.14`

**使用场景**: 用于测试 RDMA 网络配置是否正确，验证 Pod 能否成功获取 RDMA 设备和网络接口。

**部署命令**:
```bash
kubectl apply -f rdma-test.yaml
```

**验证命令**:
```bash
# 检查 Pod 状态
kubectl get pods -n dynamo-system

# 检查 Pod 的网络接口
kubectl exec -n dynamo-system rdma-test-multus-06 -- ip addr

# 检查 RDMA 设备
kubectl exec -n dynamo-system rdma-test-multus-06 -- ibdev2netdev
```

---

### 9. gpu-map.yaml
**用途**: 配置 NVIDIA GPU 设备插件

**内容**:
- 创建 `ConfigMap`，配置 NVIDIA 设备插件的参数
- 配置 GPU 资源名称为 `nvidia.com/gpu`
- 设置设备 ID 策略为 UUID
- 禁用 MIG（Multi-Instance GPU）策略

**使用场景**: 当需要在集群中暴露 GPU 资源时，需要配置此 ConfigMap。通常与 NVIDIA Device Plugin 一起使用。

**部署命令**:
```bash
kubectl apply -f gpu-map.yaml
```

**注意事项**: 
- 此配置需要配合 NVIDIA Device Plugin DaemonSet 使用
- 确保节点上已安装 NVIDIA 驱动

---

## 部署顺序建议

建议按照以下顺序部署这些配置文件：

1. **基础权限和账户**:
   ```bash
   kubectl apply -f service-account.yaml
   kubectl apply -f multus-token.yaml
   ```

2. **Multus CNI**:
   ```bash
   kubectl apply -f multus-daemonset-thick.yml
   ```

3. **NVIDIA Network Operator 配置**:
   ```bash
   kubectl apply -f nic-cluster-policy.yaml
   kubectl apply -f rdma-nic-cluster-policy.yaml
   ```

4. **SR-IOV 配置**（如需要）:
   ```bash
   kubectl apply -f sriov-node-policy.yaml
   ```

5. **网络定义**:
   ```bash
   kubectl apply -f rdma-macvlan-networks.yaml
   ```

6. **GPU 配置**（如需要）:
   ```bash
   kubectl apply -f gpu-map.yaml
   ```

7. **测试验证**:
   ```bash
   kubectl apply -f rdma-test.yaml
   ```

## 验证步骤

部署完成后，可以通过以下命令验证配置：

```bash
# 检查 Multus DaemonSet
kubectl get daemonset -n kube-system kube-multus-ds

# 检查 NetworkAttachmentDefinition
kubectl get net-attach-def -n rdma-networks

# 检查 RDMA 资源
kubectl get nodes -o json | jq '.items[].status.allocatable | keys | .[] | select(. | startswith("rdma/"))'

# 检查测试 Pod
kubectl get pods -n dynamo-system
kubectl describe pod -n dynamo-system rdma-test-multus-06
```

## 注意事项

1. **节点标签**: 确保需要配置 SR-IOV 的节点具有 `sriov: enabled` 标签
2. **网卡名称**: 根据实际环境修改网卡接口名称（如 `enp60s0f0np0`）
3. **IP 地址范围**: 根据实际网络规划修改 IP 地址范围
4. **命名空间**: 某些资源需要特定的命名空间，确保命名空间已创建
5. **驱动版本**: 根据实际硬件和驱动版本调整镜像版本号
6. **资源限制**: 根据实际需求调整 VF 数量和资源限制

## 故障排查

如果遇到问题，可以检查以下内容：

1. **Multus 日志**:
   ```bash
   kubectl logs -n kube-system -l app=multus
   ```

2. **网络状态**:
   ```bash
   kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}'
   ```

3. **RDMA 设备**:
   ```bash
   kubectl exec <pod-name> -- ibdev2netdev
   kubectl exec <pod-name> -- ibstat
   ```

4. **节点资源**:
   ```bash
   kubectl describe node <node-name>
   ```

## 相关文档

- [Multus CNI 文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NVIDIA Network Operator 文档](https://docs.nvidia.com/networking/)
- [SR-IOV 网络设备插件](https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin)
- [RDMA 共享设备插件](https://github.com/Mellanox/k8s-rdma-shared-dev-plugin)
