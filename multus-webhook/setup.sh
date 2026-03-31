/bin/bash
# This script is used to setup the environment for the Multus webhook example.
mkdir -p multus-webhook
#cd multus-webhook

# 1.1 制作镜像
docker build -t webhook:v6 -f ./multus-webhook/Dockerfile ./multus-webhook/
docker images | grep webhook
docker save -o /nfs/webhook_v6.tar webhook:v6

# 1.2 加载镜像到集群
ctr -n k8s.io images import /nfs/webhook_v6.tar
crictl images | grep webhook

# 2.1 生成 CA
openssl genrsa -out ./multus-webhook/ca.key 2048
openssl req -x509 -new -nodes -key ./multus-webhook/ca.key -subj "/CN=multus-webhook-ca" -days 3650 -out ./multus-webhook/ca.crt

# 2.2 生成 server key/csr
openssl genrsa -out ./multus-webhook/tls.key 2048
openssl req -new -key ./multus-webhook/tls.key -out ./multus-webhook/tls.csr -config ./multus-webhook/csr.conf

# 2.3 CA 签发 server cert
openssl x509 -req -in ./multus-webhook/tls.csr -CA ./multus-webhook/ca.crt -CAkey ./multus-webhook/ca.key -CAcreateserial \
  -out ./multus-webhook/tls.crt -days 3650 -sha256 -extfile ./multus-webhook/cert.conf

# 2.4 创建 secret
kubectl get ns dynamo-system >/dev/null 2>&1 || kubectl create ns dynamo-system
kubectl -n dynamo-system delete secret multus-webhook-tls --ignore-not-found
kubectl -n dynamo-system create secret tls multus-webhook-tls \
  --cert=./multus-webhook/tls.crt --key=./multus-webhook/tls.key

# 2.5 应用 mutatingwebhookconfiguration 的 CA 证书
CA_BUNDLE=$(base64 -w0 ./multus-webhook/ca.crt)
echo "$CA_BUNDLE"
# LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURHVENDQWdHZ0F3SUJBZ0lVVnBKRlltQmNMVSs5cWMxbDYxTkJPNDVSSFJRd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hERWFNQmdHQTFVRUF3d1JiWFZzZEhWekxYZGxZbWh2YjJzdFkyRXdIaGNOTWpZd01UTXdNRGd6TnpFMgpXaGNOTXpZd01USTRNRGd6TnpFMldqQWNNUm93R0FZRFZRUUREQkZ0ZFd4MGRYTXRkMlZpYUc5dmF5MWpZVENDCkFTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTXZ2NDduaHQvR2wrTTRraWV2bloycEkKQnJGZm5lTlhrdzVWV0JZVGRmWFJXektEK2Q5QUJxWDE1cWgyQTZxU3JPYkI3ZUcvNGl2UUtHdWxBQmxqa2tzaQozUTlFZ3FPK2xwZ25jQWZBZDIxc3VUWUhVa05YSHY2bkxvM3BPL3BnamtRcDRGbzh0ZzU5V01IdjNHSkV0RFB2CkFKVHhTNy9MazlUVGJrd2RDK2dFSTJNYUhWTkd4a3EyLzRiVGZqcUtjdlUxcXNJSUx6dG5Fd0NGNDIzK2dneisKZGxRcENhRDVFY21wVXVsSFR4cVhyVG5VTXBBQzliMXJsRjRUeUtUZkhrelo0ZGsydjRhcmIyaklidWJzTEFEVwpKbzNDc0RteTd2ZXd6N3F0NXlJV2xIRlk5VEg5WUt4bmVHSEdHYkF3elRKQkJNdEVwaXdIT1l1dDVyN0FDdk1DCkF3RUFBYU5UTUZFd0hRWURWUjBPQkJZRUZGRFh6Y0hpNnBBTXZyZGNNQVI0VkZmVCtsYjBNQjhHQTFVZEl3UVkKTUJhQUZGRFh6Y0hpNnBBTXZyZGNNQVI0VkZmVCtsYjBNQThHQTFVZEV3RUIvd1FGTUFNQkFmOHdEUVlKS29aSQpodmNOQVFFTEJRQURnZ0VCQUhVYStGbWZYa3ZHZzFZZzBBQ0JONHJ5SHFXdjEzcmVzM2dDcU43eHFVQ0hsR3RKCmNmMzBTaDFxUXo2eHNKUk4rdEtZWTVKczdLL1dNL1c2d2VqVGI0VEJFazFQUmJzSDhqOW80ZXdWUkEyd2ttaFoKdHFvRnBvazdhMFFiQWtvZnd2KzljcVROR0tMV1VGU2NaRU55UTZmOHNsbFp6OUZvamcvTC92UTdESDgrS1ZKMgpkUlFPWVIrSjMyMTJFN0M4NEhJaVY0S25XU1lxd05KdnlZbm5sMHBZMnIrdzUvWWNOazNmRjd3d2c3OE50UGdzCkN2Qy9IVEJiOW9YUW1wbWJNcFZWVUErbTJsd1M5ZU1JV3h4OTVxc0VDQ08rNEk1M2ZKS1kyQVZGdkI1MFMyQmwKN00vTHlZeXgvaDV2dzBaYTRwNkFEOHdpSEtWbVNEalVzRkxzZ2pNPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==

# 2.6 应用 mutatingwebhookconfiguration
kubectl apply -f ./multus-webhook/multus_webhook_mwc.yaml
kubectl apply -f ./multus-webhook/multus_webhook_deploy.yaml
kubectl get mutatingwebhookconfiguration multus-networks-injector -o yaml | grep -n "caBundle"

# 2.7 测试
kubectl apply -f ./multus-webhook/test.yaml
kubectl -n dynamo-system get pod webhook-test-06 -o yaml 
kubectl -n dynamo-system get pod webhook-test-14 -o yaml 

kubectl -n dynamo-system describe pod webhook-test-06
kubectl -n dynamo-system describe pod webhook-test-14

# 2.8 卸载
kubectl delete -f ./multus-webhook/test.yaml --ignore-not-found=true || true

kubectl delete -f ./multus-webhook/multus_webhook_mwc.yaml --ignore-not-found=true || true
kubectl delete mutatingwebhookconfiguration multus-networks-injector --ignore-not-found=true
kubectl delete -f ./multus-webhook/multus_webhook_deploy.yaml --ignore-not-found=true || true
kubectl -n dynamo-system delete secret multus-webhook-tls --ignore-not-found=true

kubectl -n dynamo-system delete serviceaccount multus-webhook --ignore-not-found=true
kubectl -n dynamo-system delete role multus-webhook --ignore-not-found=true
kubectl -n dynamo-system delete rolebinding multus-webhook --ignore-not-found=true
kubectl delete clusterrole multus-webhook --ignore-not-found=true
kubectl delete clusterrolebinding multus-webhook --ignore-not-found=true

# 可选
crictl rmi webhook:v6 2>/dev/null || true
ctr -n k8s.io images rm docker.io/library/webhook:v6 2>/dev/null || true
ctr -n k8s.io images rm webhook:v6 2>/dev/null || true
docker rmi webhook:v6 2>/dev/null || true

rm -f /nfs/webhook_v6.tar
rm -f ./multus-webhook/ca.key ./multus-webhook/ca.crt ./multus-webhook/ca.srl ./multus-webhook/tls.key ./multus-webhook/tls.crt ./multus-webhook/tls.csr