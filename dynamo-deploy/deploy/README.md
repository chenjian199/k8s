# Dynamo Platform 安装部署

本目录包含 `dynamo-platform` Helm Chart 的完整安装、配置与卸载操作手册（`setup.sh`），涵盖 Grove（拓扑调度）、KAI Scheduler（GPU 队列调度）、Dynamo Operator（CRD + 控制器）的全栈安装，以及 NFS 模型存储配置。

---

## 组件架构

```
dynamo-platform (Helm)
  ├── dynamo-operator        # DynamoGraphDeployment CRD + 控制器
  ├── kai-scheduler          # GPU 队列调度器（run.ai 协议）
  ├── grove                  # 集群拓扑感知调度
  ├── etcd                   # 服务发现（dynamo 内置）
  └── nats                   # 消息总线（dynamo 内置）
```

---

## 前置条件


| 工具/环境                               | 最低版本   | 检查命令                                                                  |
| ----------------------------------- | ------ | --------------------------------------------------------------------- |
| kubectl                             | v1.24+ | `kubectl version`                                                     |
| Helm                                | v3.0+  | `helm version`                                                        |
| NVIDIA GPU Operator 或 Device Plugin | 已部署    | `kubectl get pods -A | egrep 'gpu-operator|nvidia-device-plugin|nfd'` |


---

## 安装步骤

### 第一步：拉取代码并做预检

```bash
git clone https://github.com/ai-dynamo/dynamo.git
cd dynamo/
./deploy/pre-deployment/pre-deployment-check.sh
```

### 第二步：设置版本与命名空间

```bash
export RELEASE_VERSION=1.0.1
export NAMESPACE=dynamo-system
```

### 第三步：下载并解包 Helm Chart

```bash
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${RELEASE_VERSION}.tgz
tar -xzf "dynamo-platform-${RELEASE_VERSION}.tgz"
ls -l dynamo-platform/charts
```

解包后目录结构：

```
dynamo-platform/
├── charts/
│   ├── grove-charts/        # Grove 拓扑调度
│   ├── kai-scheduler/       # KAI GPU 调度器
│   └── dynamo-operator/     # CRD + 控制器
└── ...
```

### 第四步：安装 Grove（拓扑调度）

> **注意**：需先修复 Grove CRD 中的 `x-kubernetes-validations` 字段，否则在低版本 K8s 上会报验证错误。

```bash
# 查找需要删除的行（约 86~91 行）
grep -n "x-kubernetes-validations" ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml

# 删除不兼容的校验规则
sed -i '86,91d' ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml

# 安装 Grove
helm upgrade -i grove ./dynamo-platform/charts/grove-charts \
  -n dynamo-system \
  --create-namespace

# 验证
kubectl get crd | grep grove.io
kubectl get pods -n ${NAMESPACE} | grep -i grove
```

### 第五步：安装 KAI Scheduler

```bash
helm upgrade -i kai-scheduler ./dynamo-platform/charts/kai-scheduler \
  -n ${NAMESPACE} \
  --create-namespace

# 验证
kubectl get pods -n ${NAMESPACE}
kubectl api-resources | grep scheduling.run.ai
kubectl get queues
```

### 第六步：安装 dynamo-platform

```bash
helm upgrade -i dynamo-platform ./dynamo-platform \
  -n "${NAMESPACE}" \
  --create-namespace \
  --set "global.kai-scheduler.enabled=true" \
  --set "global.grove.enabled=true" \
  --set "global.etcd.install=true"
```

验证安装：

```bash
kubectl get crd | grep dynamo
kubectl api-resources | grep dynamo
kubectl get pods -n "${NAMESPACE}" | grep -i dynamo
```

---

## 常见安装问题

### CRD 冲突（升级时）

若 Helm 升级时报 CRD 冲突，先手动下发 CRD 再跳过自动安装：

```bash
# 强制下发 CRD
kubectl apply --server-side --force-conflicts \
  -f ./dynamo-platform/charts/dynamo-operator/crds/

# 跳过 CRD 安装升级 Helm
helm upgrade -i dynamo-platform ./dynamo-platform \
  -n "${NAMESPACE}" \
  --create-namespace \
  --skip-crds \
  --set "global.kai-scheduler.enabled=true" \
  --set "global.grove.enabled=true" \
  --set "global.etcd.install=true"
```

### 队列控制器超时

如升级时 queue-controller 出现超时，检查端点是否就绪：

```bash
kubectl get pods -n dynamo-system | grep queue-controller
kubectl get endpoints queue-controller -n dynamo-system
kubectl logs deploy/queue-controller -n dynamo-system --tail=20
```

---

## 运行时镜像预拉取

在各 GPU 节点提前拉取推理运行时镜像，避免首次调度时超时：

```bash
crictl pull nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1
crictl pull nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.0.1
```

---

## 完整卸载

> 按以下顺序执行，确保无资源残留。

### 1. 清理 Dynamo 资源对象（处理 finalizer 死锁）

```bash
# 删除所有 Dynamo 自定义资源
for r in $(kubectl api-resources --api-group=nvidia.com -o name | grep -i '^dynamo'); do
  echo "Deleting $r ..."
  kubectl delete "$r" --all -A --ignore-not-found || true
done

# 若资源卡在删除中，清除 finalizer
for r in $(kubectl api-resources --api-group=nvidia.com -o name | grep -i '^dynamo'); do
  for obj in $(kubectl get "$r" -A -o name 2>/dev/null); do
    kubectl patch "$obj" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
  done
done
```

### 2. 卸载 Helm Release

```bash
helm uninstall dynamo-platform -n dynamo-system || true
helm uninstall kai-scheduler -n dynamo-system || true
helm uninstall grove -n dynamo-system || true
kubectl delete namespace dynamo-system --wait=false || true
```

### 3. 删除 CRD

```bash
# Dynamo CRD
kubectl get crd -o name | \
  grep -E 'customresourcedefinition.apiextensions.k8s.io/dynamo.*\.nvidia\.com$' | \
  xargs -r kubectl delete

# KAI CRD
kubectl get crd -o name | \
  grep -E '(\.scheduling\.run\.ai|\.kai\.scheduler)$' | \
  xargs -r kubectl delete

# Grove CRD
kubectl get crd -o name | \
  grep -E '(\.grove\.io|\.scheduler\.grove\.io)$' | \
  xargs -r kubectl delete
```

### 4. 清理 Webhook 和 RBAC

```bash
# 删除 Webhook 配置
kubectl get validatingwebhookconfigurations -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
kubectl get mutatingwebhookconfigurations -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete

# 删除 ClusterRole / ClusterRoleBinding
kubectl get clusterrole -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
kubectl get clusterrolebinding -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
```

### 5. 删除 etcd / NATS PVC

```bash
kubectl delete pvc -n dynamo-system data-dynamo-platform-etcd-0 --ignore-not-found
kubectl delete pvc -n dynamo-system dynamo-platform-nats-js-dynamo-platform-nats-0 --ignore-not-found
```

### 6. 验证清理完成

```bash
helm list -A | grep -E 'dynamo|kai|grove' || true
kubectl get ns | grep -E 'dynamo-system|kai-scheduler|grove' || true
kubectl get crd | grep -E 'dynamo|grove|run.ai|kai.scheduler' || true
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -E 'dynamo|kai|grove' || true
kubectl get clusterrole,clusterrolebinding | grep -E 'dynamo|kai|grove' || true
```

---

## 相关文档

- [部署示例](../examples/README.md) — `DynamoGraphDeployment` CRD 配置示例
- [基准测试工具](../benchmark/README.md) — 推理性能测试
- [RDMA 网络配置](../../rdma-register/README.md) — RoCE 网卡注册

