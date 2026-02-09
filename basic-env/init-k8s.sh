#!/bin/bash
#install kubeadm

#kubeadm init
sudo kubeadm init \
  --kubernetes-version=v1.34.1 \
  --apiserver-advertise-address=192.168.4.6 \
  --control-plane-endpoint=k8s-master \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.233.0.0/16 \
  --image-repository=registry.aliyuncs.com/google_containers

#delete cluster
sudo systemctl stop kubelet
sudo rm -f /etc/kubernetes/manifests/kube-apiserver.yaml \
            /etc/kubernetes/manifests/kube-controller-manager.yaml \
            /etc/kubernetes/manifests/kube-scheduler.yaml \
            /etc/kubernetes/manifests/etcd.yaml
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/pki/* /etc/kubernetes/*.conf /var/lib/etcd/*
sudo rm -rf /etc/cni/net.d/*
sudo ip link del cni0 2>/dev/null || true
sudo ip link del flannel.1 2>/dev/null || true
sudo ip link del tunl0 2>/dev/null || true
sudo ss -ltnp | egrep ':(6443|10257|10250|2379|2380)' || true
sudo systemctl restart containerd
sudo systemctl start kubelet

#join node
kubeadm join k8s-master:6443 --token xcgd5i.1h90pfsv08wqsy4b \
	--discovery-token-ca-cert-hash sha256:87f4ef37d7123f597aaffafeab98ac71318bbe1a8c78204a8744f61fdd69f87f \
	--control-plane 
kubeadm join k8s-master:6443 --token xcgd5i.1h90pfsv08wqsy4b \
	--discovery-token-ca-cert-hash sha256:87f4ef37d7123f597aaffafeab98ac71318bbe1a8c78204a8744f61fdd69f87f 