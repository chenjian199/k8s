#!/bin/bash
#gpu operate
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  -n kube-system \
  --create-namespace

helm upgrade gpu-operator nvidia/gpu-operator \
  -n kube-system \
  --reuse-values \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=false \
  --set gdrcopy.enabled=true \
  --set gds.enabled=true 
