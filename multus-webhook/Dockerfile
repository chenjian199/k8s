FROM python:3.12-slim

RUN pip install --no-cache-dir flask

WORKDIR /app
COPY webhook.py /app/webhook.py

CMD ["python", "webhook.py", "--port", "8443", "--cert", "/certs/tls.crt", "--key", "/certs/tls.key"]