# Kubernetes 配置和部署

本仓库包含 Kubernetes 集群的基础环境配置、网络设置、API 网关以及自动化工具。

## 目录结构

### 📦 [basic-env](./basic-env/)
Kubernetes 集群基础环境配置和初始化脚本。

**主要功能**:
- 集群初始化（kubeadm init/join）
- Containerd 运行时配置（支持 NVIDIA GPU）
- 插件安装脚本（Multus CNI、NVIDIA GPU Operator、NFS 存储类）
- 集群资源管理和调试工具

**适用场景**: 新集群初始化、基础组件安装、环境配置

---

### 🌐 [rdma-register](./rdma-register/)
RDMA（Remote Direct Memory Access）网络注册和配置。

**主要功能**:
- Multus CNI 部署和权限配置
- SR-IOV 网络节点策略配置
- RDMA 设备插件配置
- Macvlan 网络定义（RoCE 网络）
- RDMA 测试 Pod 配置

**适用场景**: 高性能计算、AI/ML 训练、需要低延迟网络的应用

---

### 🚪 [apache-apisix](./apache-apisix/)
Apache APISIX API 网关配置和部署。

**主要功能**:
- APISIX 服务启动脚本
- 用户认证配置（30 个预配置用户）
- 多层限流策略（QPS、并发连接、固定窗口计数）
- 路由配置和监控集成
- 性能测试脚本

**适用场景**: API 网关部署、流量管理、限流和监控

---

### 🔧 [multus-webhook](./multus-webhook/)
Multus CNI 自动网络注入 Webhook。

**主要功能**:
- Kubernetes Mutating Admission Webhook
- 自动为符合条件的 Pod 注入 Multus 网络配置
- 支持基于标签和节点选择器的条件匹配
- 自动证书生成和部署脚本

**适用场景**: 自动化网络配置、简化 Pod 网络管理

---

## 详细文档

每个目录都包含详细的 README.md 文档，请查看对应目录的 README 了解：
- 详细的配置说明
- 完整的使用步骤
- 故障排查指南
- 最佳实践建议

---

## 相关资源

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Apache APISIX](https://apisix.apache.org/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
