#!/bin/bash

# 1. 克隆 apisix-docker 仓库
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example

# 2. 启动 apisix
docker-compose -p docker-apisix up -d

# 3. 查看 apisix 容器
docker ps -a | grep apisix

# 4. 修改 admin 账号密码
vim conf/config.yaml
deployment:
  admin:
    admin_key:
      - name: "admin"
        key: newsupersecurekey
        role: admin

# 5. 重启 apisix
docker-compose -p docker-apisix up -d