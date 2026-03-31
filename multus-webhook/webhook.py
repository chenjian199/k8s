import base64
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

TARGET_NAMESPACE = "dynamo-system"
TARGET_LABEL_KEY = "nvidia.com/dynamo-component-type"
TARGET_LABEL_VALUE = "worker"

# 单口资源 -> 单张网卡
RESOURCE_TO_NETWORK = {
    "rdma/rdma_roce0": {"name": "macvlan-roce0", "namespace": "dynamo-system"},
    "rdma/rdma_roce1": {"name": "macvlan-roce1", "namespace": "dynamo-system"},
    "rdma/rdma_roce2": {"name": "macvlan-roce2", "namespace": "dynamo-system"},
    "rdma/rdma_roce3": {"name": "macvlan-roce3", "namespace": "dynamo-system"},
    "rdma/rdma_roce4": {"name": "macvlan-roce4", "namespace": "dynamo-system"},
    "rdma/rdma_roce5": {"name": "macvlan-roce5", "namespace": "dynamo-system"},
    "rdma/rdma_roce6": {"name": "macvlan-roce6", "namespace": "dynamo-system"},
    "rdma/rdma_roce7": {"name": "macvlan-roce7", "namespace": "dynamo-system"},
    "rdma/rdma_roce8": {"name": "macvlan-roce8", "namespace": "dynamo-system"},
    "rdma/rdma_roce9": {"name": "macvlan-roce9", "namespace": "dynamo-system"},
}

# 聚合资源 -> 挂 10 张网卡
AGGREGATE_RESOURCE = "rdma/rdma_roce"
AGGREGATE_NETWORKS = [
    {"name": "macvlan-roce0", "namespace": "dynamo-system"},
    {"name": "macvlan-roce1", "namespace": "dynamo-system"},
    {"name": "macvlan-roce2", "namespace": "dynamo-system"},
    {"name": "macvlan-roce3", "namespace": "dynamo-system"},
    {"name": "macvlan-roce4", "namespace": "dynamo-system"},
    {"name": "macvlan-roce5", "namespace": "dynamo-system"},
    {"name": "macvlan-roce6", "namespace": "dynamo-system"},
    {"name": "macvlan-roce7", "namespace": "dynamo-system"},
    {"name": "macvlan-roce8", "namespace": "dynamo-system"},
    {"name": "macvlan-roce9", "namespace": "dynamo-system"},
]


def get_requested_rdma_resources(spec: dict) -> set[str]:
    """收集 Pod 所有 container 中请求/限制到的 rdma 资源名。"""
    found = set()
    for c in spec.get("containers", []) or []:
        resources = c.get("resources", {}) or {}
        requests = resources.get("requests", {}) or {}
        limits = resources.get("limits", {}) or {}

        for k in set(list(requests.keys()) + list(limits.keys())):
            if k == AGGREGATE_RESOURCE or k in RESOURCE_TO_NETWORK:
                found.add(k)
    return found


def parse_existing_networks(annotations: dict) -> list[dict]:
    raw = annotations.get("k8s.v1.cni.cncf.io/networks")
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return parsed
        return []
    except Exception:
        return []


def dedup_networks(networks: list[dict]) -> list[dict]:
    seen = set()
    result = []
    for net in networks:
        key = (net.get("namespace", ""), net.get("name", ""))
        if key not in seen:
            seen.add(key)
            result.append(net)
    return result


def create_patch(pod: dict):
    metadata = pod.get("metadata", {}) or {}
    spec = pod.get("spec", {}) or {}
    labels = metadata.get("labels", {}) or {}
    annotations = metadata.get("annotations", {}) or {}

    # 1) 只处理 dynamo-system
    if metadata.get("namespace") != TARGET_NAMESPACE:
        return None

    # 2) 只处理 dynamo worker
    if labels.get(TARGET_LABEL_KEY) != TARGET_LABEL_VALUE:
        return None

    # 3) 只看是否申请了 rdma/rdma_roce* 或 rdma/rdma_roce
    rdma_resources = get_requested_rdma_resources(spec)
    if not rdma_resources:
        return None

    to_add = []

    # 聚合资源优先：挂 10 张网卡
    if AGGREGATE_RESOURCE in rdma_resources:
        to_add.extend(AGGREGATE_NETWORKS)

    # 单口资源：按资源名精确映射
    for res in sorted(rdma_resources):
        if res in RESOURCE_TO_NETWORK:
            to_add.append(RESOURCE_TO_NETWORK[res])

    to_add = dedup_networks(to_add)

    if not to_add:
        return None

    # 如果已有 networks 注解，则合并而不是粗暴覆盖
    existing = parse_existing_networks(annotations)
    merged = dedup_networks(existing + to_add)
    networks_str = json.dumps(merged)

    patch = []
    key_path = "/metadata/annotations/k8s.v1.cni.cncf.io~1networks"

    if "annotations" not in metadata:
        patch.append({
            "op": "add",
            "path": "/metadata/annotations",
            "value": {"k8s.v1.cni.cncf.io/networks": networks_str}
        })
    elif "k8s.v1.cni.cncf.io/networks" in annotations:
        patch.append({
            "op": "replace",
            "path": key_path,
            "value": networks_str
        })
    else:
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
        response = {"uid": req["uid"], "allowed": True}
    else:
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

    app.run(host="0.0.0.0", port=args.port, ssl_context=(args.cert, args.key))