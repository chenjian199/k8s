#!/bin/bash

#get gpu operator resource
kubectl describe clusterpolicies.nvidia.com cluster-policys

#get all nodes resource
kubectl get nodes -o json | jq -r '.items[].status.capacity | keys[]' | sort -u

#get gpu operator clusterpolicy
kubectl get clusterpolicy -n gpu-operator-resources

#get gpu operator clusterpolicy detail
kubectl describe clusterpolicy cluster-policy -n gpu-operator-resources

#edit gpu operator clusterpolicy
kubectl edit clusterpolicy cluster-policy

