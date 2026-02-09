# Apache APISIX 配置和部署

本目录包含用于部署、配置和管理 Apache APISIX API 网关的脚本和配置文件。APISIX 是一个高性能、可扩展的云原生 API 网关，支持丰富的插件生态，包括认证、限流、监控等功能。

## 目录结构

```
apache-apisix/
├── setup.sh                    # APISIX 初始化和启动脚本
├── config/
│   └── apisix.yaml            # APISIX 声明式配置文件
└── launch/
    ├── admin-account.sh       # 设置管理员密钥
    ├── add-user.sh            # 批量添加用户
    ├── add-group.sh           # 添加消费者组
    ├── add-route.sh           # 添加路由配置
    ├── test.sh                # API 测试脚本
    └── benchmark.sh           # 限流性能测试脚本
```

## 文件说明

### 1. setup.sh
**用途**: 初始化和启动 Apache APISIX 服务

**功能**:
- 克隆 `apisix-docker` 仓库
- 使用 Docker Compose 启动 APISIX 服务
- 检查容器运行状态

**使用方法**:
```bash
chmod +x setup.sh
./setup.sh
```

**说明**: 
- 脚本会从 GitHub 克隆官方 APISIX Docker 仓库
- 使用 `docker-compose` 在后台启动服务
- 默认使用 `docker-apisix` 作为项目名称

---

### 2. config/apisix.yaml
**用途**: APISIX 声明式配置文件

**内容**:
- **Consumer Groups**: 定义消费者组，统一管理限流规则
- **Consumers**: 定义 30 个用户（bedilocaluser1 到 bedilocaluser30），每个用户配置了 API Key
- **Routes**: 定义路由规则，配置了认证、限流、监控等插件

**关键配置**:

#### Consumer Group
- `local_models_group`: 本地模型用户组
  - 限流规则: 每分钟 100 次请求（按 IP）
  - 时间窗口: 60 秒

#### Consumers
- 30 个用户，用户名格式: `bedilocaluser{1-30}`
- API Key 格式: `bedilocalpassword{1-30}`
- 所有用户都属于 `local_models_group` 组

#### Routes
- **URI**: `/v1/*`
- **方法**: GET, POST
- **插件配置**:
  - `key-auth`: API Key 认证
  - `limit-conn`: 并发连接限制（10 个连接，突发 5 个）
  - `limit-req`: 请求速率限制（每秒 5 个请求，突发 3 个）
  - `limit-count`: 固定窗口计数（60 秒内最多 50 次请求）
  - `prometheus`: Prometheus 指标收集
  - `access-log`: 访问日志记录
- **Upstream**: 后端服务地址 `192.168.4.14:30001`

**使用场景**: 这是 APISIX 的核心配置文件，定义了所有路由、用户和限流策略。

**部署方式**:
```bash
# 如果使用声明式配置模式
kubectl apply -f config/apisix.yaml

# 或者通过 Admin API 导入
curl -X PUT http://127.0.0.1:9180/apisix/admin/config \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d @config/apisix.yaml
```

---

### 3. launch/admin-account.sh
**用途**: 设置 APISIX 管理员密钥

**内容**:
```bash
export ADMIN_KEY="example-admin-key"
```

**使用方法**:
```bash
source launch/admin-account.sh
# 或者
export ADMIN_KEY="your-admin-key"
```

**说明**: 
- 设置环境变量 `ADMIN_KEY`，用于后续脚本调用 Admin API
- 请根据实际环境修改密钥值
- 默认密钥为 `example-admin-key`，生产环境请使用强密码

---

### 4. launch/add-user.sh
**用途**: 批量创建用户（Consumer）

**功能**:
- 通过循环创建 30 个用户（bedilocaluser1 到 bedilocaluser30）
- 每个用户配置对应的 API Key（bedilocalpassword1 到 bedilocalpassword30）
- 使用 Admin API 的 PUT 方法创建/更新用户

**使用方法**:
```bash
# 先设置管理员密钥
source launch/admin-account.sh

# 执行脚本
chmod +x launch/add-user.sh
./launch/add-user.sh
```

**说明**:
- 脚本会向 `http://127.0.0.1:9180/apisix/admin/consumers/` 发送请求
- 如果用户已存在，会更新用户信息
- 确保 APISIX Admin API 可访问（默认端口 9180）

---

### 5. launch/add-group.sh
**用途**: 创建消费者组（Consumer Group）

**功能**:
- 创建 `local_models_group` 消费者组
- 配置组级别的限流规则（limit-count）
  - 每分钟 300 次请求
  - 时间窗口 60 秒
  - 按客户端 IP 统计

**使用方法**:
```bash
# 先设置管理员密钥
source launch/admin-account.sh

# 执行脚本
chmod +x launch/add-group.sh
./launch/add-group.sh
```

**说明**:
- 消费者组可以统一管理多个用户的限流策略
- 组级别的限流规则会应用到组内所有用户
- 可以与路由级别的限流规则叠加使用

---

### 6. launch/add-route.sh
**用途**: 创建路由配置

**功能**:
- 创建路由 `model_route_v1`
- 配置 URI 匹配规则: `/v1/*`
- 配置多个限流插件:
  - `limit-conn`: 并发连接限制
  - `limit-req`: 请求速率限制
  - `limit-count`: 固定窗口计数
- 配置认证插件: `key-auth`
- 配置监控插件: `prometheus`, `file-logger`
- 配置上游服务: `192.168.4.14:30010`

**使用方法**:
```bash
# 先设置管理员密钥
source launch/admin-account.sh

# 执行脚本
chmod +x launch/add-route.sh
./launch/add-route.sh
```

**关键配置参数**:
- **并发连接限制**: 10 个连接，突发 5 个
- **请求速率限制**: 每秒 5 个请求，突发 3 个
- **固定窗口计数**: 60 秒内最多 100 次请求
- **限流键**: `$consumer_name $remote_addr`（组合键，按用户和 IP）

**说明**:
- 路由配置了多层限流保护
- 使用组合键可以更精确地控制限流
- 上游地址需要根据实际后端服务修改

---

### 7. launch/test.sh
**用途**: 测试 API 请求

**功能**:
- 发送 POST 请求到 `/v1/completions` 端点
- 使用 API Key 认证（bedilocalpassword10）
- 测试模型推理接口

**使用方法**:
```bash
chmod +x launch/test.sh
./launch/test.sh
```

**请求示例**:
```bash
curl -X POST http://192.168.4.14:9080/v1/completions \
  -H "Authorization: Bearer bedilocalpassword10" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/GLM-47-FP8",
    "prompt": "hello world"
  }'
```

**说明**:
- 测试目标地址: `192.168.4.14:9080`（APISIX 数据面端口）
- 使用用户 `bedilocaluser10` 的 API Key
- 可以修改请求参数测试不同的模型和提示词

---

### 8. launch/benchmark.sh
**用途**: 限流功能性能测试

**功能**:
- 测试三种限流策略:
  1. **QPS 限流测试** (limit-req): 发送 20 个请求，观察速率限制
  2. **并发连接测试** (limit-conn): 同时发起 10 个并发请求
  3. **固定窗口计数测试** (limit-count): 发送 120 个请求，观察计数限制

**使用方法**:
```bash
chmod +x launch/benchmark.sh
./launch/benchmark.sh
```

**测试说明**:
- **QPS 测试**: 快速发送 20 个请求，观察哪些请求被限流（返回 429）
- **并发测试**: 同时发起 10 个请求，测试并发连接限制
- **计数测试**: 在短时间内发送 120 个请求，观察固定窗口计数限制

**预期结果**:
- QPS 限制: 每秒超过 5 个请求会被限流
- 并发限制: 超过 10 个并发连接会被拒绝
- 计数限制: 60 秒内超过 50 个请求会被限流

---

## 快速开始

### 1. 启动 APISIX

```bash
# 方式一: 使用 setup.sh（推荐首次使用）
./setup.sh

# 方式二: 手动启动（如果已有 docker-compose 配置）
cd apisix-docker/example
docker-compose -p docker-apisix up -d
```

### 2. 配置管理员密钥

```bash
# 编辑 admin-account.sh 设置实际的管理员密钥
export ADMIN_KEY="your-secure-admin-key"
```

### 3. 创建消费者组

```bash
source launch/admin-account.sh
./launch/add-group.sh
```

### 4. 创建用户

```bash
source launch/admin-account.sh
./launch/add-user.sh
```

### 5. 创建路由

```bash
source launch/admin-account.sh
./launch/add-route.sh
```

### 6. 测试 API

```bash
# 简单测试
./launch/test.sh

# 限流测试
./launch/benchmark.sh
```

---

## 配置说明

### 限流策略详解

本配置使用了三种限流策略，它们可以同时生效：

1. **limit-req (请求速率限制)**
   - 类型: 漏桶算法
   - 配置: 每秒 5 个请求，突发 3 个
   - 作用: 平滑请求流量，防止突发流量

2. **limit-conn (并发连接限制)**
   - 类型: 连接数限制
   - 配置: 最多 10 个并发连接，突发 5 个
   - 作用: 限制同时处理的连接数，保护后端服务

3. **limit-count (固定窗口计数)**
   - 类型: 固定时间窗口计数
   - 配置: 60 秒内最多 50 次请求
   - 作用: 限制总请求数，防止滥用

### 认证机制

- **认证方式**: API Key 认证（key-auth 插件）
- **Header**: `Authorization: Bearer <api-key>`
- **用户数量**: 30 个预配置用户
- **密钥格式**: `bedilocalpassword{1-30}`

### 监控和日志

- **Prometheus**: 启用指标收集，可用于监控和告警
- **访问日志**: 记录所有请求日志到 `/usr/local/apisix/logs/access.log`
- **指标端点**: 可通过 Prometheus 查询 APISIX 指标

---

## 常用操作

### 查看路由列表

```bash
curl http://127.0.0.1:9180/apisix/admin/routes \
  -H "X-API-KEY: $ADMIN_KEY"
```

### 查看用户列表

```bash
curl http://127.0.0.1:9180/apisix/admin/consumers \
  -H "X-API-KEY: $ADMIN_KEY"
```

### 查看消费者组

```bash
curl http://127.0.0.1:9180/apisix/admin/consumer_groups \
  -H "X-API-KEY: $ADMIN_KEY"
```

### 查看 Prometheus 指标

```bash
curl http://127.0.0.1:9091/apisix/prometheus/metrics
```

### 查看访问日志

```bash
# 如果使用 Docker
docker exec -it <apisix-container> tail -f /usr/local/apisix/logs/access.log
```

---

## 端口说明

- **9080**: APISIX 数据面端口（处理客户端请求）
- **9180**: APISIX Admin API 端口（管理配置）
- **9091**: Prometheus 指标端口（如果启用）
- **9443**: HTTPS 数据面端口（如果启用 SSL）
- **9444**: HTTPS Admin API 端口（如果启用 SSL）

---

## 故障排查

### 1. 容器无法启动

```bash
# 检查容器状态
docker ps -a | grep apisix

# 查看容器日志
docker logs <container-id>

# 检查端口占用
netstat -tulpn | grep -E '9080|9180'
```

### 2. API 请求返回 401

- 检查 API Key 是否正确
- 确认 Header 格式: `Authorization: Bearer <key>`
- 验证用户是否已创建

### 3. API 请求返回 429

- 这是正常的限流响应
- 检查是否超过限流阈值
- 使用 `benchmark.sh` 测试限流行为

### 4. 无法访问 Admin API

- 检查 `ADMIN_KEY` 环境变量是否正确
- 确认 Admin API 端口（默认 9180）可访问
- 检查防火墙规则

### 5. 路由不生效

- 检查路由配置是否正确创建
- 验证 URI 匹配规则
- 查看 APISIX 错误日志

---

## 安全建议

1. **修改默认密钥**: 
   - 修改 `admin-account.sh` 中的默认管理员密钥
   - 使用强密码作为 API Key

2. **限制 Admin API 访问**:
   - 在生产环境中限制 Admin API 的访问来源
   - 使用防火墙规则或网络策略

3. **启用 HTTPS**:
   - 配置 SSL 证书
   - 使用 9443 和 9444 端口

4. **定期轮换密钥**:
   - 定期更新用户 API Key
   - 监控异常访问行为

5. **日志审计**:
   - 定期检查访问日志
   - 配置日志聚合和分析

---

## 性能优化

1. **调整限流参数**:
   - 根据实际业务需求调整限流阈值
   - 监控限流效果，避免过度限制

2. **启用缓存**:
   - 使用 `proxy-cache` 插件缓存响应
   - 减少后端服务压力

3. **负载均衡**:
   - 配置多个上游节点
   - 使用合适的负载均衡算法

4. **监控和告警**:
   - 配置 Prometheus 监控
   - 设置告警规则

---

## 相关资源

- [Apache APISIX 官方文档](https://apisix.apache.org/)
- [APISIX Docker 仓库](https://github.com/apache/apisix-docker)
- [APISIX 插件列表](https://apisix.apache.org/docs/apisix/plugins/)
- [APISIX Admin API 文档](https://apisix.apache.org/docs/apisix/admin-api/)

---

## 注意事项

1. **IP 地址配置**: 脚本中的 IP 地址（如 `192.168.4.14`）需要根据实际环境修改
2. **端口配置**: 确保相关端口未被占用
3. **Docker 环境**: 需要安装 Docker 和 Docker Compose
4. **网络连通性**: 确保 APISIX 可以访问后端服务
5. **资源限制**: 根据实际负载调整限流参数和容器资源限制

---

## 更新日志

- 初始版本: 包含基础配置和脚本
- 支持 30 个用户和消费者组管理
- 配置多层限流策略
- 集成 Prometheus 监控
