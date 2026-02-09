# Multus Webhook 自动网络注入器

这是一个 Kubernetes Mutating Admission Webhook，用于自动为符合条件的 Pod 注入 Multus CNI 网络配置。

## 功能说明

当在 `dynamo-system` 命名空间中创建带有以下特征的 Pod 时，Webhook 会自动为其添加 Multus 网络注解：

- **命名空间**: `dynamo-system`
- **标签**: `nvidia.com/dynamo-component-type: worker`
- **节点别名**: `worker06` 或 `worker14`（通过 `dynamo.nodeAlias` nodeSelector 指定）

符合条件的 Pod 将自动附加 10 个 RoCE 网络接口（roce5, roce7~roce15），这些网络接口定义在 `rdma-networks` 命名空间中。

## 项目结构

```
multus-webhook/
├── webhook_new.py              # Webhook 主程序（Flask 应用）
├── webhook.py                  # 旧版主程序
├── Dockerfile                  # Docker 镜像构建文件
├── setup.sh                    # 自动化部署脚本
├── cert.conf                   # 证书扩展配置
├── csr.conf                    # 证书签名请求配置
├── multus_webhook_deploy.yaml  # Deployment 和 Service 配置
├── multus_webhook_mwc.yaml     # MutatingWebhookConfiguration 配置
└── test_webhook.yaml           # 测试 Pod 配置
```

## 配置流程

### 前置要求

- 已安装并配置 `kubectl`，且能够访问目标 Kubernetes 集群
- 已安装 `openssl` 工具
- 集群中已安装 Multus CNI
- 已创建 `rdma-networks` 命名空间，并配置了相应的 NetworkAttachmentDefinition（NAD）

### 步骤 1: 构建 Docker 镜像

首先需要构建 Webhook 服务的 Docker 镜像：

```bash
docker build -t webhook:v5 -f Dockerfile .
# 如果使用远程仓库，需要推送镜像
# docker push <your-registry>/webhook:v5
```

**注意**: 确保 `multus_webhook_deploy.yaml` 中的镜像地址与实际镜像地址一致。

### 步骤 2: 运行自动化部署脚本

执行 `setup.sh` 脚本，该脚本会自动完成以下操作：

```bash
./setup.sh
```

#### 脚本执行内容详解：

1. **生成 CA 证书** (第 4-6 行)
   - 创建临时工作目录
   - 生成 2048 位 RSA 私钥 `ca.key`
   - 生成自签名 CA 证书 `ca.crt`，有效期 10 年

2. **生成服务器证书** (第 8-14 行)
   - 生成服务器私钥 `tls.key`
   - 使用 `csr.conf` 配置生成证书签名请求 `tls.csr`
   - 使用 CA 证书签发服务器证书 `tls.crt`，包含 SAN（Subject Alternative Names）

3. **创建 Kubernetes Secret** (第 16-20 行)
   - 检查并创建 `dynamo-system` 命名空间（如果不存在）
   - 删除已存在的 `multus-webhook-tls` Secret（如果存在）
   - 创建新的 TLS Secret，包含服务器证书和私钥

4. **输出 CA Bundle** (第 22-25 行)
   - 将 CA 证书进行 Base64 编码
   - 输出编码后的值，用于更新 `MutatingWebhookConfiguration`

5. **应用 Kubernetes 资源** (第 27-30 行)
   - 应用 `MutatingWebhookConfiguration`（需要手动更新其中的 `caBundle` 字段）
   - 应用 `Deployment` 和 `Service`
   - 验证 `caBundle` 是否正确设置

6. **测试验证** (第 32-34 行)
   - 创建测试 Pod
   - 检查 Pod 是否成功注入了网络注解

### 步骤 3: 更新 MutatingWebhookConfiguration

**重要**: 执行 `setup.sh` 后，脚本会输出 CA 证书的 Base64 编码值。你需要：

1. 复制输出的 CA Bundle 值
2. 编辑 `multus_webhook_mwc.yaml` 文件
3. 将 `caBundle` 字段的值替换为脚本输出的值
4. 重新应用配置：

```bash
kubectl apply -f multus_webhook_mwc.yaml
```

### 步骤 4: 验证部署

检查 Webhook 服务是否正常运行：

```bash
# 检查 Deployment 状态
kubectl -n dynamo-system get deployment multus-webhook

# 检查 Pod 状态
kubectl -n dynamo-system get pods -l app=multus-webhook

# 检查 Service
kubectl -n dynamo-system get svc multus-webhook

# 检查 MutatingWebhookConfiguration
kubectl get mutatingwebhookconfiguration multus-networks-injector
```

### 步骤 5: 测试 Webhook

使用提供的测试 Pod 进行验证：

```bash
kubectl apply -f test_webhook.yaml
kubectl -n dynamo-system get pod webhook-test -o yaml | grep -A2 "k8s.v1.cni.cncf.io/networks"
```

如果配置正确，你应该能看到 Pod 的 annotations 中包含了网络配置注解。

## 工作原理

1. **Pod 创建请求**: 当 Kubernetes API Server 收到创建 Pod 的请求时，会检查是否有匹配的 MutatingWebhookConfiguration

2. **Webhook 匹配**: 如果 Pod 满足以下条件，Webhook 会被触发：
   - 命名空间为 `dynamo-system`
   - 标签包含 `nvidia.com/dynamo-component-type: worker`
   - nodeSelector 中包含 `dynamo.nodeAlias`，且值为 `worker06` 或 `worker14`

3. **网络注入**: Webhook 服务接收请求后，生成 JSON Patch，为 Pod 添加 `k8s.v1.cni.cncf.io/networks` 注解

4. **Pod 创建**: API Server 应用 Patch 后，Pod 被创建，Multus CNI 会根据注解自动附加网络接口

## 自定义配置

### 修改目标节点

编辑 `webhook_new.py` 文件中的第 30 行，修改节点别名判断：

```python
if alias in ("worker06", "worker14"):  # 修改为你需要的节点别名
```

### 修改网络配置

编辑 `webhook_new.py` 文件中的第 31-42 行，修改要注入的网络列表：

```python
nets = [
    {"name": "roce5",  "namespace": "rdma-networks"},
    # 添加或删除网络配置
]
```

### 修改命名空间或标签匹配

编辑 `webhook_new.py` 和 `multus_webhook_mwc.yaml` 中的相应配置。

## 故障排查

### Webhook 未触发

1. 检查 MutatingWebhookConfiguration 的匹配规则是否正确
2. 检查 Pod 的标签和命名空间是否符合条件
3. 查看 API Server 日志：`kubectl logs -n kube-system <api-server-pod>`

### Webhook 调用失败

1. 检查 Webhook Pod 是否正常运行：`kubectl -n dynamo-system logs <webhook-pod>`
2. 检查 Service 是否正常：`kubectl -n dynamo-system get svc multus-webhook`
3. 检查证书是否有效：`kubectl -n dynamo-system get secret multus-webhook-tls -o yaml`
4. 验证 `caBundle` 是否正确设置

### Pod 未注入网络

1. 检查 Pod 的 annotations：`kubectl get pod <pod-name> -o yaml | grep annotations`
2. 检查 Webhook 日志，查看是否有错误信息
3. 确认 NetworkAttachmentDefinition 在 `rdma-networks` 命名空间中存在

## 注意事项

- 确保 Webhook 服务的高可用性，建议在生产环境中部署多个副本
- 证书有效期为 10 年，到期前需要重新生成和更新
- 修改 Webhook 逻辑后，需要重新构建镜像并更新 Deployment
- `failurePolicy: Ignore` 表示即使 Webhook 失败，Pod 创建也不会被阻止

## 许可证

本项目为内部使用项目。
