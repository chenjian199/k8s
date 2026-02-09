import base64
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

def create_patch(pod):
    metadata = pod.get("metadata", {})
    spec = pod.get("spec", {})
    labels = metadata.get("labels", {}) or {}
    annotations = metadata.get("annotations", {}) or {}

    namespace = metadata.get("namespace")
    if namespace != "dynamo-system":
        return None

    if labels.get("nvidia.com/dynamo-component-type") != "worker":
        return None

    node_selector = spec.get("nodeSelector", {}) or {}
    alias = node_selector.get("dynamo.nodeAlias")
    if not alias:
        return None
    # hostname = node_selector.get("kubernetes.io/hostname")
    # if not hostname:
    #     return None

    # 你现在的 NAD 都在 rdma-networks ns
    # 这里按节点 worker06/worker14 都挂 8 张网卡（对应 roce7~roce15 或你实际的8张）
    if alias in ("worker06", "worker14"):
        nets = [
            {"name": "roce5",  "namespace": "rdma-networks"},
            {"name": "roce7",  "namespace": "rdma-networks"},
            {"name": "roce8",  "namespace": "rdma-networks"},
            {"name": "roce9",  "namespace": "rdma-networks"},
            {"name": "roce10", "namespace": "rdma-networks"},
            {"name": "roce11", "namespace": "rdma-networks"},
            {"name": "roce12", "namespace": "rdma-networks"},
            {"name": "roce13", "namespace": "rdma-networks"},
            {"name": "roce14", "namespace": "rdma-networks"},
            {"name": "roce15", "namespace": "rdma-networks"},
        ]
    else:
        return None

    networks_str = json.dumps(nets)
    patch = []
    key_path = "/metadata/annotations/k8s.v1.cni.cncf.io~1networks"

    if "annotations" not in metadata:
        patch.append({
            "op": "add",
            "path": "/metadata/annotations",
            "value": {"k8s.v1.cni.cncf.io/networks": networks_str}
        })
    elif "k8s.v1.cni.cncf.io/networks" in annotations:
        patch.append({"op": "replace", "path": key_path, "value": networks_str})
    else:
        patch.append({"op": "add", "path": key_path, "value": networks_str})

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
