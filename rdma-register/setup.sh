#!/bin/bash
# This script is used to setup the environment for the RDMA register example.

#查看nad和rdma资源
kubectl get network-attachment-definitions -A
kubectl describe nodes | grep -i -E "Capacity:|Allocatable:|rdma" -B 1 -A 5
kubectl get nodes -o json | jq -r '.items[].status.capacity'

#安装nvidia-network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade -i network-operator nvidia/network-operator \
  -n nvidia-network-operator \
  --create-namespace \
  --version v26.1.0
kubectl -n nvidia-network-operator get pods

# 部署nic
kubectl apply -f ./recipes/nicclusterpolicy.yaml
kubectl get nicclusterpolicy
kubectl describe nicclusterpolicy nic-cluster-policy
kubectl -n nvidia-network-operator get pods
kubectl get crd | grep -Ei 'nv-ipam|ippool|macvlan'
kubectl get node bdsz-node0002.192.168.4.6 -o json | jq '.status.allocatable'
kubectl get node bdsz-node0003.192.168.4.14 -o json | jq '.status.allocatable'

# 部署ippools和macvlans-networks
kubectl apply -f ./recipes/macvlan-ippools.yaml
kubectl apply -f ./recipes/macvlan-networks.yaml
kubectl get crd | grep -Ei 'ippool|macvlan|mellanox|nv-ipam'
kubectl api-resources | grep -Ei 'IPPool|Macvlan|NicClusterPolicy'

kubectl get ippools.nv-ipam.nvidia.com -n nvidia-network-operator
kubectl describe ippools.nv-ipam.nvidia.com rdma-roce1-pool -n nvidia-network-operator
kubectl get ippools.nv-ipam.nvidia.com rdma-roce1-pool -n nvidia-network-operator -o yaml

kubectl get macvlannetwork -A
kubectl describe macvlannetwork macvlan-roce0
kubectl get macvlannetwork -A -o yaml

kubectl get macvlannetworks.mellanox.com -n dynamo-system


# 测试单卡路由
kubectl apply -f ./examples/test-single.yaml
kubectl get pods -n dynamo-system -o wide | grep rdma
kubectl -n dynamo-system exec -it rdma-test-multus-06 -- bash
kubectl -n dynamo-system exec -it rdma-test-multus-14 -- bash

# 在pod内安装测试工具并测试
apt-get update
apt-get install -y rdma-core ibverbs-utils perftest infiniband-diags iproute2
ip addr
rdma link
ibv_devices
ibv_devinfo -v | egrep "id|GID"

ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -R
ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -R 172.16.100.101
ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -x 5
ib_write_bw -d mlx5_10 -q 1 --report_gbits -F -a -x 5 172.16.100.101

kubectl delete pod rdma-test-multus-06 -n dynamo-system
kubectl delete pod rdma-test-multus-14 -n dynamo-system


# 测试聚合路由
kubectl apply -f ./examples/test-agg.yaml
kubectl get pods -n dynamo-system -o wide | grep rdma
kubectl -n dynamo-system exec -it rdma-test-agg-06 -- bash
kubectl -n dynamo-system exec -it rdma-test-agg-14 -- bash
#余下测试步骤测试同上

#（可选）卸载
kubectl delete -f ./examples/test-single.yaml --ignore-not-found=true
kubectl delete -f ./examples/test-agg.yaml --ignore-not-found=true

kubectl delete pod rdma-test-multus-06 -n dynamo-system --ignore-not-found=true
kubectl delete pod rdma-test-multus-14 -n dynamo-system --ignore-not-found=true
kubectl delete pod rdma-test-agg-06 -n dynamo-system --ignore-not-found=true
kubectl delete pod rdma-test-agg-14 -n dynamo-system --ignore-not-found=true

kubectl delete dynamographdeployment vllm-disagg-kvbm-1p1d-rdma -n dynamo-system --ignore-not-found=true
kubectl delete dynamographdeployment vllm-disagg-kvbm-1p1d -n dynamo-system --ignore-not-found=true

kubectl delete -f ./recipes/macvlan-networks.yaml --ignore-not-found=true
kubectl delete -f ./recipes/macvlan-ippools.yaml --ignore-not-found=true

kubectl get network-attachment-definitions -A || true

kubectl delete -f ./recipes/nicclusterpolicy.yaml --ignore-not-found=true
kubectl delete nicclusterpolicies.mellanox.com nic-cluster-policy --ignore-not-found=true
kubectl -n nvidia-network-operator get pods -w || true

# 可选
kubectl delete clusterrolebinding multus-kube-system-cluster-admin --ignore-not-found=true

helm uninstall network-operator -n nvidia-network-operator || true
kubectl delete namespace nvidia-network-operator --ignore-not-found=true

# 检查
kubectl get crd | grep -Ei 'nicclusterpolicy|macvlan|nv-ipam|ippool|mellanox' || true
kubectl api-resources | grep -Ei 'IPPool|Macvlan|NicClusterPolicy' || true

# 可选
kubectl delete crd nicclusterpolicies.mellanox.com
kubectl delete crd macvlannetworks.mellanox.com
kubectl delete crd ippools.nv-ipam.nvidia.com
