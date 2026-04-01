# Multus Network Injector Webhook

本目录实现了一个 Kubernetes **Mutating Admission Webhook**，用于自动为 Dynamo Worker Pod 注入 Multus 二级网络注解（`k8s.v1.cni.cncf.io/networks`），从而修复无法在每个部署dynamo YAML 中配置 RDMA 网卡绑定的问题。

---

## 工作原理

```
Pod 创建请求
    │
    ▼
API Server ──(MutatingWebhookConfiguration)──▶ multus-webhook (HTTPS :8443)
                                                      │
                                          检查 namespace == dynamo-system
                                          检查 label: dynamo-component-type=worker
                                          检查 resources 中是否含 rdma/rdma_roce*
                                                      │
                                              自动追加 networks 注解
                                                      │
                                                      ▼
                                          Pod 挂载对应 RDMA 网卡并获得 IP
```

### 触发条件（同时满足）


| 条件        | 值                                                          |
| --------- | ---------------------------------------------------------- |
| 命名空间      | `dynamo-system`                                            |
| Pod Label | `nvidia.com/dynamo-component-type: worker`                 |
| 申请资源      | 含 `rdma/rdma_roce` 或 `rdma/rdma_roce0` ~ `rdma/rdma_roce9` |


### 资源与网卡映射规则


| 申请资源              | 注入网络                                       | 说明            |
| ----------------- | ------------------------------------------ | ------------- |
| `rdma/rdma_roce`  | `macvlan-roce0` ~ `macvlan-roce9`（全部 10 张） | 聚合模式，一次挂载所有网卡 |
| `rdma/rdma_roce0` | `macvlan-roce0`                            | 单口精确映射        |
| `rdma/rdma_roce1` | `macvlan-roce1`                            | 单口精确映射        |
| …                 | …                                          | …             |
| `rdma/rdma_roce9` | `macvlan-roce9`                            | 单口精确映射        |


- 若 Pod 已有 `k8s.v1.cni.cncf.io/networks` 注解，则**合并追加**而非覆盖
- 重复网络条目会自动去重

---

## 目录结构

```
multus-webhook/
├── webhook.py                   # Webhook 核心逻辑（Flask HTTPS 服务）
├── Dockerfile                   # 镜像构建文件
├── multus_webhook_deploy.yaml   # Deployment + Service（端口 443→8443）
├── multus_webhook_mwc.yaml      # MutatingWebhookConfiguration
├── csr.conf                     # TLS CSR 配置（含 SAN）
├── cert.conf                    # TLS 证书扩展配置
├── ca.key / ca.crt              # 自签 CA 密钥和证书（已生成）
├── tls.key / tls.crt / tls.csr  # Server TLS 密钥和证书（已生成）
├── test.yaml                    # 功能验证测试 Pod
└── setup.sh                     # 完整操作手册
```

---

## 安装步骤

> 所有命令从项目根目录（`k8s/` 的父目录）执行。

### 第一步：构建并分发镜像

```bash
# 构建镜像
docker build -t webhook:v6 -f ./multus-webhook/Dockerfile ./multus-webhook/

# 导出到 NFS，分发给集群各节点
docker save -o /nfs/webhook_v6.tar webhook:v6

# 在每个节点上导入（或通过 containerd）
ctr -n k8s.io images import /nfs/webhook_v6.tar
```

### 第二步：生成 TLS 证书

> 若目录中已存在 `ca.crt`、`tls.crt` 等文件，可跳过此步骤直接使用已有证书。

```bash
# 2.1 生成自签 CA
openssl genrsa -out ./multus-webhook/ca.key 2048
openssl req -x509 -new -nodes -key ./multus-webhook/ca.key \
  -subj "/CN=multus-webhook-ca" -days 3650 \
  -out ./multus-webhook/ca.crt

# 2.2 生成 Server 密钥和 CSR
openssl genrsa -out ./multus-webhook/tls.key 2048
openssl req -new -key ./multus-webhook/tls.key \
  -out ./multus-webhook/tls.csr \
  -config ./multus-webhook/csr.conf

# 2.3 CA 签发 Server 证书（含 SAN）
openssl x509 -req \
  -in ./multus-webhook/tls.csr \
  -CA ./multus-webhook/ca.crt \
  -CAkey ./multus-webhook/ca.key \
  -CAcreateserial \
  -out ./multus-webhook/tls.crt \
  -days 3650 -sha256 \
  -extfile ./multus-webhook/cert.conf
```

证书 SAN 包含以下域名，确保 API Server 能正确验证：

- `multus-webhook`
- `multus-webhook.dynamo-system`
- `multus-webhook.dynamo-system.svc`

### 第三步：创建 TLS Secret

```bash
kubectl get ns dynamo-system >/dev/null 2>&1 || kubectl create ns dynamo-system

kubectl -n dynamo-system delete secret multus-webhook-tls --ignore-not-found
kubectl -n dynamo-system create secret tls multus-webhook-tls \
  --cert=./multus-webhook/tls.crt \
  --key=./multus-webhook/tls.key
```

### 第四步：更新 caBundle 并部署

`multus_webhook_mwc.yaml` 中的 `caBundle` 字段需要与当前 CA 证书一致。若重新生成了 CA，执行以下命令获取新的 base64 编码值并手动更新：

```bash
CA_BUNDLE=$(base64 -w0 ./multus-webhook/ca.crt)
echo "$CA_BUNDLE"
# 将输出值填入 multus_webhook_mwc.yaml 的 caBundle 字段
```

然后部署：

```bash
kubectl apply -f ./multus-webhook/multus_webhook_mwc.yaml
kubectl apply -f ./multus-webhook/multus_webhook_deploy.yaml
```

验证部署状态：

```bash
kubectl -n dynamo-system get pods -l app=multus-webhook
kubectl get mutatingwebhookconfiguration multus-networks-injector -o yaml | grep -n "caBundle"
```

---

## 功能验证

`test.yaml` 中包含两个测试 Pod，分别覆盖两种资源请求模式：


| Pod               | 节点              | 申请资源                  | 预期注入              |
| ----------------- | --------------- | --------------------- | ----------------- |
| `webhook-test-06` | `bdsz-node0002` | `rdma/rdma_roce`（聚合）  | 全部 10 张网卡         |
| `webhook-test-14` | `bdsz-node0003` | `rdma/rdma_roce0`（单口） | 仅 `macvlan-roce0` |


```bash
kubectl apply -f ./multus-webhook/test.yaml

# 检查 Pod 的 annotations 是否已自动注入 networks 字段
kubectl -n dynamo-system get pod webhook-test-06 -o yaml | grep -A5 "k8s.v1.cni.cncf.io"
kubectl -n dynamo-system get pod webhook-test-14 -o yaml | grep -A5 "k8s.v1.cni.cncf.io"

# 查看详细事件
kubectl -n dynamo-system describe pod webhook-test-06
kubectl -n dynamo-system describe pod webhook-test-14
```

---

## 卸载

```bash
# 删除测试 Pod
kubectl delete -f ./multus-webhook/test.yaml --ignore-not-found=true

# 删除 Webhook 配置和 Deployment
kubectl delete -f ./multus-webhook/multus_webhook_mwc.yaml --ignore-not-found=true
kubectl delete -f ./multus-webhook/multus_webhook_deploy.yaml --ignore-not-found=true
kubectl -n dynamo-system delete secret multus-webhook-tls --ignore-not-found=true

# 删除 RBAC 资源
kubectl -n dynamo-system delete serviceaccount multus-webhook --ignore-not-found=true
kubectl -n dynamo-system delete role multus-webhook --ignore-not-found=true
kubectl -n dynamo-system delete rolebinding multus-webhook --ignore-not-found=true
kubectl delete clusterrole multus-webhook --ignore-not-found=true
kubectl delete clusterrolebinding multus-webhook --ignore-not-found=true

# 可选：清理镜像和导出文件
docker rmi webhook:v6 2>/dev/null || true
rm -f /nfs/webhook_v6.tar
rm -f ./multus-webhook/ca.key ./multus-webhook/ca.crt ./multus-webhook/ca.srl \
       ./multus-webhook/tls.key ./multus-webhook/tls.crt ./multus-webhook/tls.csr
```

---

## 常见问题

**Q: Pod 创建后没有自动注入 networks 注解**

检查以下三个条件是否都满足：

1. Pod 所在命名空间是 `dynamo-system`
2. Pod 含有 Label `nvidia.com/dynamo-component-type: worker`
3. Pod resources 中含有 `rdma/rdma_roce` 或 `rdma/rdma_roceN`

查看 Webhook 日志：

```bash
kubectl -n dynamo-system logs -l app=multus-webhook
```

**Q: Webhook 返回 TLS 错误 / x509 证书验证失败**

`multus_webhook_mwc.yaml` 中的 `caBundle` 与当前 `ca.crt` 不匹配。重新生成证书后需更新 `caBundle` 字段，再重新 apply。

**Q: MutatingWebhookConfiguration 的 `failurePolicy: Ignore` 是什么含义**

当 Webhook 服务不可用时，Pod 创建请求会被**放行**（不会阻塞），但不会注入网络注解。这是为了避免 Webhook 本身的故障影响整个集群。若需强制注入，可改为 `failurePolicy: Fail`。

**Q: 如何扩展支持新的 RDMA 网卡**

修改 `webhook.py` 中的 `RESOURCE_TO_NETWORK` 字典，添加新的资源名到 MacVLAN 网络的映射，然后重新构建镜像并重新部署即可。