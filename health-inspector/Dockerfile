FROM python:3.11.13-alpine3.22@sha256:801053a2c35d91edc335c4c478f682de905611fed131007715538c7552d943db

RUN apk add --no-cache docker-cli

WORKDIR /app
COPY health-inspector/inspector.py /app/inspector.py

ENTRYPOINT ["python", "/app/inspector.py"]
