WORKDIR=$(mktemp -d)
cd "$WORKDIR"

# 2.1 生成 CA
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=multus-webhook-ca" -days 3650 -out ca.crt

# 2.2 生成 server key/csr
openssl genrsa -out tls.key 2048
openssl req -new -key tls.key -out tls.csr -config csr.conf

# 2.3 CA 签发 server cert
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out tls.crt -days 3650 -sha256 -extfile cert.conf

# 2.4 创建 secret
kubectl get ns dynamo-system >/dev/null 2>&1 || kubectl create ns dynamo-system
kubectl -n dynamo-system delete secret multus-webhook-tls --ignore-not-found
kubectl -n dynamo-system create secret tls multus-webhook-tls \
  --cert=tls.crt --key=tls.key

# 2.5 应用 mutatingwebhookconfiguration 的 CA 证书
CA_BUNDLE=$(base64 -w0 ca.crt)
echo "$CA_BUNDLE"
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURHVENDQWdHZ0F3SUJBZ0lVVnBKRlltQmNMVSs5cWMxbDYxTkJPNDVSSFJRd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hERWFNQmdHQTFVRUF3d1JiWFZzZEhWekxYZGxZbWh2YjJzdFkyRXdIaGNOTWpZd01UTXdNRGd6TnpFMgpXaGNOTXpZd01USTRNRGd6TnpFMldqQWNNUm93R0FZRFZRUUREQkZ0ZFd4MGRYTXRkMlZpYUc5dmF5MWpZVENDCkFTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTXZ2NDduaHQvR2wrTTRraWV2bloycEkKQnJGZm5lTlhrdzVWV0JZVGRmWFJXektEK2Q5QUJxWDE1cWgyQTZxU3JPYkI3ZUcvNGl2UUtHdWxBQmxqa2tzaQozUTlFZ3FPK2xwZ25jQWZBZDIxc3VUWUhVa05YSHY2bkxvM3BPL3BnamtRcDRGbzh0ZzU5V01IdjNHSkV0RFB2CkFKVHhTNy9MazlUVGJrd2RDK2dFSTJNYUhWTkd4a3EyLzRiVGZqcUtjdlUxcXNJSUx6dG5Fd0NGNDIzK2dneisKZGxRcENhRDVFY21wVXVsSFR4cVhyVG5VTXBBQzliMXJsRjRUeUtUZkhrelo0ZGsydjRhcmIyaklidWJzTEFEVwpKbzNDc0RteTd2ZXd6N3F0NXlJV2xIRlk5VEg5WUt4bmVHSEdHYkF3elRKQkJNdEVwaXdIT1l1dDVyN0FDdk1DCkF3RUFBYU5UTUZFd0hRWURWUjBPQkJZRUZGRFh6Y0hpNnBBTXZyZGNNQVI0VkZmVCtsYjBNQjhHQTFVZEl3UVkKTUJhQUZGRFh6Y0hpNnBBTXZyZGNNQVI0VkZmVCtsYjBNQThHQTFVZEV3RUIvd1FGTUFNQkFmOHdEUVlKS29aSQpodmNOQVFFTEJRQURnZ0VCQUhVYStGbWZYa3ZHZzFZZzBBQ0JONHJ5SHFXdjEzcmVzM2dDcU43eHFVQ0hsR3RKCmNmMzBTaDFxUXo2eHNKUk4rdEtZWTVKczdLL1dNL1c2d2VqVGI0VEJFazFQUmJzSDhqOW80ZXdWUkEyd2ttaFoKdHFvRnBvazdhMFFiQWtvZnd2KzljcVROR0tMV1VGU2NaRU55UTZmOHNsbFp6OUZvamcvTC92UTdESDgrS1ZKMgpkUlFPWVIrSjMyMTJFN0M4NEhJaVY0S25XU1lxd05KdnlZbm5sMHBZMnIrdzUvWWNOazNmRjd3d2c3OE50UGdzCkN2Qy9IVEJiOW9YUW1wbWJNcFZWVUErbTJsd1M5ZU1JV3h4OTVxc0VDQ08rNEk1M2ZKS1kyQVZGdkI1MFMyQmwKN00vTHlZeXgvaDV2dzBaYTRwNkFEOHdpSEtWbVNEalVzRkxzZ2pNPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==

# 2.6 应用 mutatingwebhookconfiguration
kubectl apply -f multus_webhook_mwc.yaml
kubectl apply -f multus_webhook_deploy.yaml
kubectl get mutatingwebhookconfiguration multus-networks-injector -o yaml | grep -n "caBundle"

# 2.7 测试
kubectl apply -f test-pod.yaml
kubectl -n dynamo-system get pod webhook-test -o yaml | grep -A2 "k8s.v1.cni.cncf.io/networks"