#!/bin/bash
#install multus

mkdir -p multus && cd multus

# download multus thick image deployment file
wget https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml -O multus-daemonset-thick.yml

# if wget is not working, use curl
# curl -L https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml -o multus-daemonset-thick.yml

# apply to cluster
kubectl apply -f multus-daemonset-thick.yml

# check multus pods
kubectl -n kube-system get pods -l app=multus

# check CNI config directory
sudo ls /etc/cni/net.d

sudo ls /opt/cni/bin | egrep "macvlan|ipvlan"

kubectl get network-attachment-definitions -n kube-system