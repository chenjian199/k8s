# NFS 模型存储配置

本目录提供在集群节点间搭建 NFS 共享存储的操作脚本，用于将本地模型文件（`/mnt/share`）通过 NFS 导出，供 Dynamo 推理 Pod 通过 PV/PVC 访问。

---

## 架构说明

```
NFS 服务端（192.168.4.6）          NFS 客户端（其他节点）
/mnt/share  ──bind──▶  /nfs  ──────NFS──────▶  /nfs
（实际模型文件）         （导出点）              （挂载点，供 Pod 使用）
```

- **NFS Server**：`192.168.4.6`，导出路径 `/nfs`
- **实际数据**：存放于 `/mnt/share`，通过 bind mount 映射到 `/nfs`
- **客户端挂载点**：`/nfs`，与 Pod 中 PVC 挂载路径一致

---

## 目录结构

```
nfs/
├── setup.sh    # 服务端 + 客户端一键配置脚本
└── README.md
```

---

## 安装步骤

### 服务端配置（在 NFS Server 节点执行）

```bash
# 1. 安装 NFS 服务
apt-get update
apt-get install -y nfs-kernel-server

# 2. 创建导出目录并设置权限
mkdir -p /nfs
chmod 777 /nfs

# 3. 将实际存储路径 bind mount 到导出目录
mount --bind /mnt/share /nfs

# 4. 写入 fstab 使 bind mount 开机自动生效
echo "/mnt/share /nfs none bind 0 0" >> /etc/fstab

# 5. 配置 NFS 导出规则（允许所有客户端读写）
echo "/mnt/share *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports

# 6. 重新加载导出配置并重启服务
exportfs -arv
systemctl restart nfs-kernel-server

# 7. 验证导出是否生效
showmount -e localhost
mount | grep nfs
```

> **导出参数说明**
>
> | 参数 | 含义 |
> |------|------|
> | `rw` | 允许客户端读写 |
> | `sync` | 同步写入，数据更安全 |
> | `no_subtree_check` | 关闭子目录检查，提升性能 |
> | `no_root_squash` | 客户端 root 用户保留 root 权限（容器内需要） |

---

### 客户端配置（在所有 Worker 节点执行）

```bash
# 1. 安装 NFS 客户端工具
apt-get update
apt-get install -y nfs-common

# 2. 创建挂载目录
mkdir -p /nfs

# 3. 临时挂载（测试用）
mount -t nfs 192.168.4.6:/nfs /nfs

# 4. 写入 fstab 使挂载开机自动生效
echo "192.168.4.6:/nfs /nfs nfs defaults 0 0" >> /etc/fstab

# 5. 验证挂载
df -h | grep nfs
```

---

## 验证

服务端验证：

```bash
# 查看已导出的路径
showmount -e localhost

# 查看当前 NFS 服务状态
systemctl status nfs-kernel-server
```

客户端验证：

```bash
# 确认挂载成功
df -h | grep nfs
ls /nfs     # 应能看到模型文件
```

---

## 在 Dynamo 中使用 NFS 存储

NFS 挂载完成后，通过 PV + PVC 将 `/nfs` 路径提供给 Pod 使用：

```bash
# 创建 PV（NFS 类型）
kubectl -n dynamo-system apply -f ../dynamo-deploy/examples/multi/model-pv.yaml

# 创建 PVC
kubectl -n dynamo-system apply -f ../dynamo-deploy/examples/multi/model-cache-nfs.yaml

# 验证
kubectl get pv | grep model-cache
kubectl get pvc -n dynamo-system | grep model-cache
```

PV 配置摘要（`model-pv.yaml`）：

| 参数 | 值 |
|------|----|
| PV 名称 | `model-cache-pv` |
| 容量 | 700Gi |
| NFS Server | `192.168.4.6` |
| NFS 路径 | `/nfs` |
| 访问模式 | `ReadWriteMany` |

---

## 常见问题

**Q: `showmount -e localhost` 无输出**

检查 `/etc/exports` 配置是否正确，并确认已执行 `exportfs -arv`：
```bash
cat /etc/exports
exportfs -v
```

**Q: 客户端 `mount` 超时或失败**

确认服务端防火墙已放行 NFS 相关端口（111、2049）：
```bash
# 服务端
ufw allow from <客户端IP> to any port 2049
ufw allow from <客户端IP> to any port 111
```

**Q: Pod 内无法访问 NFS 挂载的文件**

检查 PV/PVC 是否已绑定（`STATUS` 为 `Bound`），以及 YAML 中 `mountPoint` 路径是否与模型实际路径一致：
```bash
kubectl get pv,pvc -n dynamo-system
```
