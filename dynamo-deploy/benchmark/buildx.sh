docker buildx build --load \
  --add-host host.docker.internal=host-gateway \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  --build-arg HTTP_PROXY=http://host.docker.internal:7890 \
  --build-arg HTTPS_PROXY=http://host.docker.internal:7890 \
  --build-arg ALL_PROXY=socks5h://host.docker.internal:7891 \
  --build-arg NO_PROXY=127.0.0.1,::1,localhost,worker06,worker14,10.0.0.0/8,192.168.0.0/16,.svc,.cluster.local,host.docker.internal \
  --progress=plain \
  -f container/rendered.Dockerfile \
  -t dynamo-vllm-local-dev:v1.0.1 \
  .