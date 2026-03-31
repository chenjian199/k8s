#!/bin/bash
# Setup source code
cd $(dirname $(readlink -f $0))/..

echo "1. Building source code..."
cargo build --locked --features dynamo-llm/block-manager --workspace

echo "2. Installing Python bindings..."
cd /workspace/lib/bindings/python && maturin develop --uv && cd /workspace

echo "3. Installing KVBM Python bindings..."
cd /workspace/lib/bindings/kvbm && maturin develop --uv && cd /workspace

echo "4. Installing Python packages..."
uv pip install --no-deps -e /workspace

echo "5. Running sanity check..."
deploy/sanity_check.py