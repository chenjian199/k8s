curl -X POST http://192.168.4.14:9080/v1/completions \
  -H "Authorization: Bearer bedilocalpassword10" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/GLM-47-FP8",
    "prompt": "hello world"
  }'
