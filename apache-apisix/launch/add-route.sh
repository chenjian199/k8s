export ADMIN_KEY="example-admin-key"
curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/model_route_v1 \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/v1/*",
    "methods": ["GET", "POST"],
    "plugins": {
      "key-auth": {
        "header": "Authorization",
        "hide_credentials": true
      },

      "limit-conn": {
        "conn": 10,
        "burst": 5,
        "default_conn_delay": 500,
        "key_type": "var_combination",
        "key": "$consumer_name $remote_addr",
        "rejected_code": 429
      },
      "limit-req": {
        "rate": 5,
        "burst": 3,
        "key_type": "var_combination",
        "key": "$consumer_name $remote_addr",
        "rejected_code": 429
      },
      "limit-count": {
        "count": 100,
        "time_window": 60,
        "key_type": "var_combination",
        "key": "$consumer_name $remote_addr",
        "rejected_code": 429
      },

      "prometheus": {},
      "file-logger": { "path": "/usr/local/apisix/logs/access.log" }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": { "192.168.4.14:30010": 1 }
    }
  }'
