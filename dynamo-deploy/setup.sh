#!/bin/bash
# This script is used to setup the environment for the dynamo deployment example.

kubectl -n dynamo-system get pods -o wide

kubectl -n dynamo-system apply -f .dynamo-deploy/example/multi/disagg_kvbm_1p1d.yaml
kubectl -n dynamo-system apply -f .dynamo-deploy/example/multi/disagg_kvbm_1p1d_rdma.yaml
kubectl -n dynamo-system get pods -o wide

kubectl -n  dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-frontend 8000:8000 &
kubectl -n  dynamo-system port-forward svc/vllm-disagg-kvbm-1p1d-rdma-frontend 8001:8000 &

curl http://localhost:8000/v1/models
curl http://localhost:8001/v1/models

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'

bash ./dynamo-deploy/benchmark/start-container.sh

#测试容器内
python ./dynamo-deploy/benchmark/aiperf.py

kubectl -n dynamo-system delete dynamographdeployment vllm-disagg-kvbm-1p1d-rdma --ignore-not-found=true
kubectl -n dynamo-system delete dynamographdeployment vllm-disagg-kvbm-1p1d --ignore-not-found=true