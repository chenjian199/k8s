#!/bin/bash
# 汇总查看每个节点的 GPU 容量/可分配数
kubectl get nodes \
  -o custom-columns=NAME:.metadata.name,GPU-CAP:.status.capacity.nvidia\.com/gpu,GPU-ALLOC:.status.allocatable.nvidia\.com/gpu

#nvidia containerd toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sudo sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd --set-as-default
sudo systemctl restart containerd
sudo systemctl restart kubelet

#nvidia device plugin
helm repo add nvidia-device-plugin https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install nvidia-device-plugin nvidia-device-plugin/nvidia-device-plugin \
  -n kube-system --create-namespace \
  --set-string args[0]=--fail-on-init-error=false \
  --set gfd.enabled=true \
  --set gdrcopy.enabled=true


kubectl -n kube-system logs ds/nvidia-device-plugin
kubectl -n kube-system get ds,pods | grep -i nvidia
kubectl get nodes -o json | jq -r '.items[].status.capacity | keys[]' | sort -u

kubectl get nodes -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{index .status.capacity "nvidia.com/H800_80GB"}}{{"\t"}}{{index .status.allocatable "nvidia.com/H800_80GB"}}{{"\n"}}{{end}}'
kubectl get nodes -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{index .status.capacity "nvidia.com/gpu"}}{{"\t"}}{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}{{end}}'

kubectl -n kube-system edit ds nvidia-device-plugin-daemonset
kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset
