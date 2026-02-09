#!/bin/bash

URL="http://192.168.4.14:9080/v1/completions"
AUTH="Authorization: Bearer bedilocalpassword10"
DATA='{"model":"/models/GLM-47-FP8","prompt":"test"}'

echo "====== QPS 限流测试 (limit-req) ======"
for i in $(seq 1 20); do
  NOW=$(date '+%Y-%m-%d %H:%M:%S')
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$URL" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$DATA")
  echo "$NOW  请求 #$i  状态码: $STATUS"
done

echo
echo "====== 并发连接测试 (limit-conn) ======"

for i in $(seq 1 10); do
  NOW=$(date '+%Y-%m-%d %H:%M:%S')
  curl -s -o /dev/null -w "$NOW Parallel #$i -> %{http_code}\n" \
    -X POST "$URL" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$DATA" &
done
wait

echo
echo "====== 固定窗口计数测试 (limit-count) ======"

for i in $(seq 1 120); do
  NOW=$(date '+%Y-%m-%d %H:%M:%S')
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$URL" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$DATA")
  echo "$NOW  计数请求 #$i  状态码: $STATUS"
done
