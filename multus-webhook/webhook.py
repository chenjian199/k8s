import base64
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

# 根据 Pod 和 nodeSelector 决定要不要打 Multus 注解
def create_patch(pod):
    metadata = pod.get("metadata", {})
    spec = pod.get("spec", {})
    labels = metadata.get("labels", {}) or {}
    annotations = metadata.get("annotations", {}) or {}

    namespace = metadata.get("namespace")
    if namespace != "dynamo-system":
        print("Namespace is not dynamo-system")
        return None

    # 只处理 worker 的 Pod（假设 vllm worker 有这个 label）
    if labels.get("nvidia.com/dynamo-component-type") != "worker":
        print("Component type is not worker")
        return None

    node_selector = spec.get("nodeSelector", {}) or {}
    hostname = node_selector.get("kubernetes.io/hostname")
    if not hostname:
        # 没有 nodeSelector，不知道要去哪台机器，没法选 NAD，直接放过
        print("No nodeSelector")
        return None

    # 根据节点名选择 NAD 列表（8 张卡）
    if hostname == "worker06":
        print("Hostname is worker06")
        nets = [
            {"name": "rdma-net-172-16-8-node06",  "namespace": "kube-system"},
            {"name": "rdma-net-172-16-9-node06",  "namespace": "kube-system"},
            {"name": "rdma-net-172-16-10-node06", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-11-node06", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-12-node06", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-13-node06", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-14-node06", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-15-node06", "namespace": "kube-system"},
        ]
    elif hostname == "worker14":
        print("Hostname is worker14")
        nets = [
            {"name": "rdma-net-172-16-8-node14",  "namespace": "kube-system"},
            {"name": "rdma-net-172-16-9-node14",  "namespace": "kube-system"},
            {"name": "rdma-net-172-16-10-node14", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-11-node14", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-12-node14", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-13-node14", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-14-node14", "namespace": "kube-system"},
            {"name": "rdma-net-172-16-15-node14", "namespace": "kube-system"},
        ]
    else:
        # 其他节点一律不动
        print("Hostname is not worker06 or worker14")
        return None

    networks_str = json.dumps(nets)

    patch = []

    # JSONPatch 的 path 里 / 要变成 ~1
    key_path = "/metadata/annotations/k8s.v1.cni.cncf.io~1networks"

    if "annotations" not in metadata:
        print("Annotations not in metadata")
        # annotations 整块都没有
        patch.append({
            "op": "add",
            "path": "/metadata/annotations",
            "value": {
                "k8s.v1.cni.cncf.io/networks": networks_str
            }
        })
    elif "k8s.v1.cni.cncf.io/networks" in annotations:
        print("k8s.v1.cni.cncf.io/networks in annotations")
        patch.append({
            "op": "replace",
            "path": key_path,
            "value": networks_str
        })
    else:
        print("k8s.v1.cni.cncf.io/networks not in annotations")
        patch.append({
            "op": "add",
            "path": key_path,
            "value": networks_str
        })

    return patch


@app.route("/mutate", methods=["POST"])
def mutate():
    admission_review = request.get_json()
    req = admission_review["request"]
    pod = req["object"]

    patch = create_patch(pod)

    if patch is None:
        print("No patch needed")
        # 不改，直接放过
        response = {
            "uid": req["uid"],
            "allowed": True,
        }
    else:
        print("Patching pod")
        patch_bytes = json.dumps(patch).encode("utf-8")
        patch_b64 = base64.b64encode(patch_bytes).decode("utf-8")
        response = {
            "uid": req["uid"],
            "allowed": True,
            "patchType": "JSONPatch",
            "patch": patch_b64,
        }

    return jsonify({
        "apiVersion": "admission.k8s.io/v1",
        "kind": "AdmissionReview",
        "response": response,
    })


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--cert", type=str, default="/certs/tls.crt")
    parser.add_argument("--key", type=str, default="/certs/tls.key")
    args = parser.parse_args()

    # https server
    app.run(host="0.0.0.0", port=args.port, ssl_context=(args.cert, args.key))