#!/bin/bash
# This script is used to setup the environment for the dynamo deployment example.

#1.资源预装
kubectl version  #1.24+
helm version 	#3.0+
kubectl get pods -A | egrep 'gpu-operator|nvidia-device-plugin|nfd'

#2.拉取代码和压缩包
git clone https://github.com/ai-dynamo/dynamo.git
cd dynamo/
./deploy/pre-deployment/pre-deployment-check.sh

#3.选择版本与资源预装
export RELEASE_VERSION=1.0.1
export NAMESPACE=dynamo-system

#4.解包crds
helm fetch https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${RELEASE_VERSION}.tgz
tar -xzf "dynamo-platform-${RELEASE_VERSION}.tgz"
ls -l dynamo-platform/charts

#5.获取grove和kai版本
export KAI_CHART=./dynamo-platform/charts/kai-scheduler
export GROVE_CHART=./dynamo-platform/charts/grove-charts
echo "$KAI_CHART"
echo "$GROVE_CHART"
helm show chart "$KAI_CHART"
helm show chart "$GROVE_CHART"

#6.安装grove
#修改topology
grep -n "x-kubernetes-validations" ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml
nl -ba ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml | sed -n '80,95p'
sed -i '86,91d' ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml
grep -n "x-kubernetes-validations" ./dynamo-platform/charts/grove-charts/crds/grove.io_clustertopologies.yaml

helm upgrade -i grove "$GROVE_CHART" \
  -n dynamo-system \
  --create-namespace 

kubectl get crd | grep grove.io
kubectl api-resources | grep grove
kubectl get pods -n "${NAMESPACE}" | grep -i grove

#7.安装kai
helm upgrade -i kai-scheduler "$KAI_CHART" \
  -n ${NAMESPACE} \
  --create-namespace 

kubectl get pods -n "${NAMESPACE}"
kubectl api-resources | grep scheduling.run.ai
kubectl get queues

#8.安装dynamo-platform
helm upgrade -i dynamo-platform ./dynamo-platform \
  -n "${NAMESPACE}" \
  --create-namespace	\
  --set "global.kai-scheduler.enabled=true" \
--set "global.grove.enabled=true" \
  --set "global.etcd.install=true"

kubectl get crd | grep dynamo
kubectl api-resources | grep dynamo
kubectl get pods -n "${NAMESPACE}" | grep -i dynamo

#9.若升级超时，查看队列服务端点是否正常（可选）
kubectl get pods -n dynamo-system | grep queue-controller
kubectl get endpoints queue-controller -n dynamo-system
kubectl logs deploy/queue-controller -n dynamo-system --tail=20

#10.若crds冲突，先预装crds
kubectl apply --server-side --force-conflicts \
  -f ./dynamo-platform/charts/dynamo-operator/crds/

helm upgrade -i dynamo-platform ./dynamo-platform \
  -n "${NAMESPACE}" \
  --create-namespace \
  --skip-crds \
  --set "global.kai-scheduler.enabled=true" \
  --set "global.grove.enabled=true" \
  --set "global.etcd.install=true"

#拉取所需运行镜像
crictl pull nvcr.io/nvidia/ai-dynamo/tensorrtllm-runtime:1.0.1
crictl pull nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.0.1

#13.#(可选）卸载残留
helm list -A | grep -E 'dynamo|kai|grove'

#14.删除api-resource
for r in $(kubectl api-resources --api-group=nvidia.com -o name | grep -i '^dynamo'); do
  echo "Deleting $r ..."
  kubectl delete "$r" --all -A --ignore-not-found || true
done

#15.验证删除
for r in $(kubectl api-resources --api-group=nvidia.com -o name | grep -i '^dynamo'); do
  echo "Checking $r ..."
  kubectl get "$r" -A --ignore-not-found
done

#16.检查是否有残留的死锁
for r in $(kubectl api-resources --api-group=nvidia.com -o name | grep -i '^dynamo'); do
  for obj in $(kubectl get "$r" -A -o name 2>/dev/null); do
    kubectl patch "$obj" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
  done
done

#17.卸载安装
helm uninstall dynamo-platform -n dynamo-system || true
helm uninstall kai-scheduler -n dynamo-system || true
helm uninstall grove -n dynamo-system || true
helm list -A | grep -E 'dynamo|kai|grove' || true
kubectl delete namespace dynamo-system --wait=false || true

#18.删除dynamo-crds
kubectl get crd -o name | \
grep -E 'customresourcedefinition.apiextensions.k8s.io/dynamo.*\.nvidia\.com$' | \
xargs -r kubectl delete

#19.删除kai-crds
kubectl get crd -o name | \
grep -E '(\.scheduling\.run\.ai|\.kai\.scheduler)$' | \
xargs -r kubectl delete

#20.删除grove-crds
kubectl get crd -o name | \
grep -E '(\.grove\.io|\.scheduler\.grove\.io)$' | \
xargs -r kubectl delete

kubectl get crd | grep -E 'dynamo|grove|run.ai|kai.scheduler' || true

#21.删除相关policy
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -E 'dynamo|kai|grove' || true
kubectl get validatingwebhookconfigurations -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
kubectl get mutatingwebhookconfigurations -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
kubectl get clusterrole,clusterrolebinding | grep -E 'dynamo|kai|grove' || true
kubectl get clusterrole -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete
kubectl get clusterrolebinding -o name | grep -E 'dynamo|kai|grove' | xargs -r kubectl delete

#22.删除pv-pvc
kubectl get pvc -A
kubectl delete pvc -n dynamo-system data-dynamo-platform-etcd-0 --ignore-not-found
kubectl delete pvc -n dynamo-system dynamo-platform-nats-js-dynamo-platform-nats-0 --ignore-not-found


#23.验证资源是否有残留
helm list -A | grep -E 'dynamo|kai|grove' || true
kubectl get ns | grep -E 'dynamo-system|kai-scheduler|grove' || true
kubectl get crd | grep -E 'dynamo|grove|run.ai|kai.scheduler' || true
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -E 'dynamo|kai|grove' || true
kubectl get clusterrole,clusterrolebinding | grep -E 'dynamo|kai|grove' || true