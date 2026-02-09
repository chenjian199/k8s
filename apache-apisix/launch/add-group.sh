curl -X PUT http://127.0.0.1:9180/apisix/admin/consumer_groups/local_models_group \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "plugins": {
      "limit-count": {
        "count": 300,
        "time_window": 60,
        "key": "remote_addr"
      }
    }
  }'
