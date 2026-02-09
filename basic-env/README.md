# Kubernetes 基础环境配置

本目录包含用于初始化和配置 Kubernetes 集群基础环境的脚本和配置文件。这些工具主要用于设置容器运行时、安装必要的插件、管理集群资源以及调试 Pod。

## 目录结构

```
basic-env/
├── init-k8s.sh                    # Kubernetes 集群初始化脚本
├── get-status.sh                  # 查看集群资源状态
├── attach-pods.sh                 # 调试 Pod 工具
├── get-resource.sh                # 获取 GPU 资源信息
├── config/
│   ├── containerd-config.toml    # Containerd 配置文件（NVIDIA 运行时）
│   └── register.yaml              # Containerd 配置文件（备用）
└── install-plugin/
    ├── nvidia-gpu-plugin.sh      # NVIDIA GPU 设备插件安装
    ├── nvidia-gpu-operate.sh      # NVIDIA GPU Operator 安装
    ├── nfs.sh                     # NFS 存储类安装
    └── multus.sh                  # Multus CNI 安装
```

## 文件说明

### 1. init-k8s.sh
**用途**: Kubernetes 集群初始化和管理脚本

**功能**:
- **初始化主节点**: 使用 `kubeadm init` 创建新的 Kubernetes 集群
- **删除集群**: 完全清理集群配置和数据
- **加入节点**: 提供工作节点和控制平面节点加入命令

**关键配置**:
- Kubernetes 版本: `v1.34.1`
- API Server 地址: `192.168.4.6`
- Pod 网络 CIDR: `10.244.0.0/16`
- Service CIDR: `10.233.0.0/16`
- 镜像仓库: `registry.aliyuncs.com/google_containers`（阿里云镜像）

**使用方法**:
```bash
# 初始化主节点（需要根据实际情况修改参数）
sudo ./init-k8s.sh

# 删除集群（谨慎使用）
# 脚本中包含删除集群的命令，需要手动执行相应部分
```

**注意事项**:
- 执行前需要根据实际环境修改 IP 地址和版本号
- 删除集群操作会清除所有数据，请谨慎使用
- 需要 root 权限执行

---

### 2. get-status.sh
**用途**: 快速查看 Kubernetes 集群资源状态

**功能**:
- 查看集群级别的资源（节点、命名空间、持久卷、存储类）
- 查看指定命名空间（默认 `dynamo-system`）的资源：
  - Deployments (deploy)
  - DaemonSets (ds)
  - StatefulSets (sts)
  - Services (svc)
  - ConfigMaps (cm)
  - Secrets

**使用方法**:
```bash
chmod +x get-status.sh
./get-status.sh
```

**自定义命名空间**:
```bash
# 修改脚本中的 namespace 变量
namespace=your-namespace
./get-status.sh
```

**说明**: 
- 脚本会依次显示所有资源的当前状态
- 适合快速检查集群健康状态
- 可以修改命名空间变量查看不同命名空间的资源

---

### 3. attach-pods.sh
**用途**: 调试 Pod，附加调试容器到运行中的 Pod

**功能**:
- 查找指定 Pod（示例: `vllm-disagg-0-vllmdecodeworker`）
- 获取 Pod 中的容器名称
- 使用 `kubectl debug` 附加调试容器
- 提供在容器中安装依赖的命令

**使用方法**:
```bash
chmod +x attach-pods.sh
./attach-pods.sh
```

**调试容器配置**:
- 镜像: `nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04`
- 共享进程命名空间: `--share-processes`
- 目标容器: `main`

**在调试容器中安装工具**:
```bash
apt update
apt install -y iproute2 iputils-ping rdma-core pciutils net-tools ibverbs-utils perftest ethtool
```

**说明**:
- 需要根据实际 Pod 名称修改脚本
- 调试容器可以访问主容器的网络和进程
- 适合排查网络、RDMA 等问题的调试

---

### 4. get-resource.sh
**用途**: 获取 GPU 相关资源信息和操作 GPU Operator

**功能**:
- 查看 GPU Operator ClusterPolicy 详情
- 获取所有节点的资源类型
- 查看和编辑 GPU Operator 配置
- 重启 GPU Operator DaemonSet

**使用方法**:
```bash
chmod +x get-resource.sh
./get-resource.sh
```

**常用命令**:
```bash
# 查看 ClusterPolicy
kubectl describe clusterpolicies.nvidia.com cluster-policys

# 查看所有资源类型
kubectl get nodes -o json | jq -r '.items[].status.capacity | keys[]' | sort -u

# 编辑 ClusterPolicy
kubectl edit clusterpolicy cluster-policy
```

**说明**:
- 用于检查 GPU 资源是否正确暴露
- 可以查看 GPU Operator 的配置状态
- 支持动态编辑和重启 GPU Operator

---

### 5. config/containerd-config.toml
**用途**: Containerd 容器运行时配置文件

**关键配置**:

#### NVIDIA 运行时配置
- **默认运行时**: `nvidia`（第 88 行）
- **NVIDIA Runtime**: `/usr/bin/nvidia-container-runtime`
- **Systemd Cgroup**: 启用

#### CNI 配置
- CNI 二进制目录: `/opt/cni/bin`
- CNI 配置目录: `/etc/cni/net.d`

#### 镜像配置
- 使用阿里云镜像: `registry.aliyuncs.com/google_containers/pause:3.10`
- 快照存储: `overlayfs`
- 最大并发下载: 3

#### 其他配置
- 启用 CDI (Container Device Interface)
- 禁用 SELinux
- 启用非特权 ICMP 和端口

**使用方法**:
```bash
# 备份现有配置
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.bak

# 应用新配置
sudo cp config/containerd-config.toml /etc/containerd/config.toml

# 重启 containerd
sudo systemctl restart containerd
```

**说明**:
- 此配置已启用 NVIDIA 容器运行时支持
- 适用于需要 GPU 支持的 Kubernetes 集群
- 需要配合 NVIDIA Container Toolkit 使用

---

### 6. config/register.yaml
**用途**: Containerd 配置文件（备用版本）

**说明**: 
- 与 `containerd-config.toml` 内容相同
- 可作为备用配置文件使用
- 文件名可能用于某些自动化脚本

---

### 7. install-plugin/nvidia-gpu-plugin.sh
**用途**: 安装 NVIDIA GPU 设备插件

**功能**:
- 安装 NVIDIA Container Toolkit
- 配置 Containerd 使用 NVIDIA 运行时
- 使用 Helm 安装 NVIDIA Device Plugin
- 启用 GFD (GPU Feature Discovery) 和 GDRCopy

**安装步骤**:
1. 添加 NVIDIA Container Toolkit 仓库
2. 安装 `nvidia-container-toolkit`
3. 配置 Containerd 运行时
4. 重启 Containerd 和 Kubelet
5. 使用 Helm 安装 Device Plugin

**使用方法**:
```bash
chmod +x install-plugin/nvidia-gpu-plugin.sh
sudo ./install-plugin/nvidia-gpu-plugin.sh
```

**验证安装**:
```bash
# 检查 Device Plugin Pod
kubectl -n kube-system get pods | grep nvidia-device-plugin

# 查看日志
kubectl -n kube-system logs ds/nvidia-device-plugin

# 检查节点资源
kubectl get nodes -o json | jq -r '.items[].status.capacity | keys[]' | sort -u
```

**说明**:
- 需要在所有 GPU 节点上执行
- 安装后需要重启 Containerd 和 Kubelet
- GFD 可以自动发现 GPU 特性（如型号、显存等）

---

### 8. install-plugin/nvidia-gpu-operate.sh
**用途**: 安装 NVIDIA GPU Operator

**功能**:
- 使用 Helm 安装 NVIDIA GPU Operator
- 配置 RDMA 支持
- 启用 GDRCopy 和 GDS (GPU Direct Storage)

**关键配置**:
- **RDMA 支持**: 启用，使用主机 MOFED
- **GDRCopy**: 启用（GPU Direct RDMA）
- **GDS**: 启用（GPU Direct Storage）

**使用方法**:
```bash
chmod +x install-plugin/nvidia-gpu-operate.sh
./install-plugin/nvidia-gpu-operate.sh
```

**升级配置**:
```bash
# 如果需要修改配置，使用 upgrade 命令
helm upgrade gpu-operator nvidia/gpu-operator \
  -n kube-system \
  --reuse-values \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=false \
  --set gdrcopy.enabled=true \
  --set gds.enabled=true
```

**说明**:
- GPU Operator 会自动管理 GPU 驱动、设备插件等组件
- 比单独安装 Device Plugin 更全面
- 支持 RDMA 和 GPU Direct 技术

---

### 9. install-plugin/nfs.sh
**用途**: 安装 NFS 存储类（StorageClass）

**功能**:
- 使用 Helm 安装 NFS Subdir External Provisioner
- 创建动态存储类
- 设置为默认存储类

**配置参数**:
- NFS 服务器: `<NFS_SERVER_IP>`（需要修改）
- NFS 路径: `/raid5/model`
- 存储类名称: `nfs-rwx`
- 默认存储类: 是

**使用方法**:
```bash
# 修改脚本中的 NFS 服务器地址
# 将 <NFS_SERVER_IP> 替换为实际的 NFS 服务器 IP

chmod +x install-plugin/nfs.sh
./install-plugin/nfs.sh
```

**验证安装**:
```bash
# 查看存储类
kubectl get sc

# 查看 PVC
kubectl -n dynamo-system get pvc -o wide
```

**说明**:
- 需要先配置好 NFS 服务器
- 存储类支持 ReadWriteMany (RWX) 访问模式
- 适合共享存储场景（如模型存储）

---

### 10. install-plugin/multus.sh
**用途**: 安装 Multus CNI 插件

**功能**:
- 下载 Multus CNI 官方部署文件
- 部署 Multus DaemonSet
- 验证安装

**安装步骤**:
1. 创建 multus 目录
2. 下载官方部署文件（thick 模式）
3. 应用部署文件
4. 检查 Pod 状态
5. 验证 CNI 配置

**使用方法**:
```bash
chmod +x install-plugin/multus.sh
sudo ./install-plugin/multus.sh
```

**验证安装**:
```bash
# 检查 Multus Pod
kubectl -n kube-system get pods -l app=multus

# 检查 CNI 配置
sudo ls /etc/cni/net.d

# 检查 CNI 二进制文件
sudo ls /opt/cni/bin | egrep "macvlan|ipvlan"

# 检查 NetworkAttachmentDefinition
kubectl get network-attachment-definitions -n kube-system
```

**说明**:
- Multus 支持 Pod 附加多个网络接口
- 需要 root 权限执行部分命令
- 安装后需要重启节点或等待 Pod 就绪

---

## 快速开始

### 1. 初始化 Kubernetes 集群

```bash
# 1. 配置 Containerd（如果需要 GPU 支持）
sudo cp config/containerd-config.toml /etc/containerd/config.toml
sudo systemctl restart containerd

# 2. 初始化主节点（根据实际情况修改参数）
sudo ./init-k8s.sh
```

### 2. 安装基础插件

```bash
# 安装 Multus CNI
sudo ./install-plugin/multus.sh

# 安装 NFS 存储类（修改 NFS 服务器地址）
./install-plugin/nfs.sh

# 安装 GPU 支持（选择其一）
# 方式一: 仅安装 Device Plugin
sudo ./install-plugin/nvidia-gpu-plugin.sh

# 方式二: 安装完整的 GPU Operator（推荐）
./install-plugin/nvidia-gpu-operate.sh
```

### 3. 验证安装

```bash
# 查看集群状态
./get-status.sh

# 查看 GPU 资源
./get-resource.sh

# 检查节点资源
kubectl get nodes -o json | jq -r '.items[].status.capacity | keys[]' | sort -u
```

---

## 配置说明

### Containerd 配置要点

1. **NVIDIA 运行时**:
   - 默认运行时设置为 `nvidia`
   - 使用 `/usr/bin/nvidia-container-runtime`
   - 支持 Systemd Cgroup

2. **CNI 配置**:
   - CNI 二进制文件路径: `/opt/cni/bin`
   - CNI 配置文件路径: `/etc/cni/net.d`

3. **镜像仓库**:
   - 使用阿里云镜像加速
   - 配置了 pause 镜像

### GPU 支持配置

**方式一: Device Plugin（轻量级）**
- 仅安装设备插件
- 需要手动安装 NVIDIA 驱动
- 适合简单场景

**方式二: GPU Operator（推荐）**
- 自动管理所有 GPU 组件
- 支持 RDMA、GDRCopy、GDS
- 适合生产环境

### 存储配置

- **NFS 存储类**: 用于共享存储
- **存储路径**: `/raid5/model`（可修改）
- **访问模式**: ReadWriteMany (RWX)

---

## 常用操作

### 查看集群资源

```bash
# 使用脚本
./get-status.sh

# 手动查看
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
```

### 调试 Pod

```bash
# 使用脚本（需要修改 Pod 名称）
./attach-pods.sh

# 手动调试
kubectl debug pod/<pod-name> -it --image=nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04 --target=main --share-processes -- bash
```

### 管理 GPU 资源

```bash
# 查看 GPU 资源
./get-resource.sh

# 查看节点 GPU 容量
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU-CAP:.status.capacity.nvidia\.com/gpu,GPU-ALLOC:.status.allocatable.nvidia\.com/gpu

# 编辑 GPU Operator 配置
kubectl edit clusterpolicy cluster-policy -n gpu-operator-resources
```

### 管理存储

```bash
# 查看存储类
kubectl get sc

# 查看 PVC
kubectl get pvc -A

# 创建 PVC（使用 NFS 存储类）
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage
  namespace: dynamo-system
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-rwx
  resources:
    requests:
      storage: 100Gi
EOF
```

---

## 故障排查

### 1. Containerd 无法启动

```bash
# 检查配置文件语法
sudo containerd config default > /tmp/test-config.toml
sudo containerd --config /etc/containerd/config.toml config dump

# 查看日志
sudo journalctl -u containerd -f

# 检查 NVIDIA 运行时
which nvidia-container-runtime
```

### 2. GPU 资源未显示

```bash
# 检查 Device Plugin Pod
kubectl -n kube-system get pods -l name=nvidia-device-plugin-daemonset

# 查看 Device Plugin 日志
kubectl -n kube-system logs ds/nvidia-device-plugin-daemonset

# 检查节点标签
kubectl get nodes --show-labels

# 检查 NVIDIA 驱动
nvidia-smi
```

### 3. Multus 未正常工作

```bash
# 检查 Multus Pod
kubectl -n kube-system get pods -l app=multus

# 查看 Multus 日志
kubectl -n kube-system logs -l app=multus

# 检查 CNI 配置
sudo ls -la /etc/cni/net.d/
sudo ls -la /opt/cni/bin/
```

### 4. NFS 存储无法挂载

```bash
# 检查 NFS Provisioner Pod
kubectl -n kube-system get pods | grep nfs

# 查看 NFS Provisioner 日志
kubectl -n kube-system logs -l app=nfs-client-provisioner

# 测试 NFS 连接
showmount -e <NFS_SERVER_IP>
```

### 5. Pod 无法调度

```bash
# 查看 Pod 事件
kubectl describe pod <pod-name> -n <namespace>

# 查看节点资源
kubectl describe node <node-name>

# 检查节点条件
kubectl get nodes -o wide
```

---

## 注意事项

1. **权限要求**:
   - 部分脚本需要 root 权限
   - 使用 `sudo` 执行需要管理员权限的命令

2. **网络配置**:
   - 确保节点间网络连通
   - 配置正确的 Pod 和 Service CIDR

3. **镜像仓库**:
   - 脚本中使用阿里云镜像加速
   - 可根据实际情况修改镜像仓库地址

4. **GPU 驱动**:
   - 使用 Device Plugin 方式需要预先安装 NVIDIA 驱动
   - GPU Operator 可以自动管理驱动

5. **存储配置**:
   - NFS 服务器需要提前配置
   - 确保 NFS 路径可访问

6. **版本兼容性**:
   - Kubernetes 版本: v1.34.1
   - 确保所有组件版本兼容

---

## 相关资源

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Containerd 文档](https://containerd.io/docs/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NFS Subdir External Provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)

---

## 更新日志

- 初始版本: 包含基础集群初始化脚本
- 添加 GPU 支持配置
- 添加 Multus CNI 安装脚本
- 添加 NFS 存储类支持
- 优化 Containerd 配置
