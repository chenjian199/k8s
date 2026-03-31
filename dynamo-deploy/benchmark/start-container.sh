#!/bin/bash
# Start the container
cd $(dirname $(readlink -f $0))/../../..
container/run.sh \
    --image chenjian110/dynamo:vllm-v1.0.1 \
    --mount-workspace \
    -v $HOME/.cache:/home/dynamo/.cache \
    -v /nfs/nfs/models:/models \
    -it \
    --rm false\
    --name CJ-DYNAMO-VLLM-LOCAL-DEV \
    -- bash