#!/bin/bash
#attach docker to pod

# get pod name
kubectl -n dynamo-system get pods | grep vllm-disagg-0-vllmdecodeworker

# get container name
kubectl -n dynamo-system get pod vllm-disagg-0-vllmdecodeworker-nhp4q -o jsonpath='{.spec.containers[*].name}'

# attach docker to pod
kubectl -n dynamo-system debug pod/vllm-disagg-0-vllmdecodeworker-nhp4q \
  -it --image=nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04 \
  --target=main --share-processes -- bash

# install dependencies in container
apt update
apt install -y iproute2 iputils-ping rdma-core pciutils net-tools ibverbs-utils perftest ethtool