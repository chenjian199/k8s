#!/bin/bash
#查看kubernetes资源状态

namespace=dynamo-system
# 这些资源不属于任何命名空间
kubectl get nodes          # 节点
kubectl get namespaces     # 命名空间
kubectl get persistentvolumes  # 持久卷
kubectl get storageclasses    # 存储类

# 这些资源属于特定命名空间
kubectl get deploy -n $namespace    # 部署
kubectl get ds -n $namespace        # 守护进程集
kubectl get sts -n $namespace       # 有状态副本集
kubectl get svc -n $namespace       # 服务
kubectl get cm -n $namespace        # 配置映射
kubectl get secret -n $namespace    # 密钥