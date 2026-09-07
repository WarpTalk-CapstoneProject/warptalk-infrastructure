FROM python:3.11.13-alpine3.22@sha256:801053a2c35d91edc335c4c478f682de905611fed131007715538c7552d943db

# The explicit openssl floor is not redundant with `apk upgrade`. The release build pins
# this base image by digest and passes `--cache-from` against a registry BuildKit cache
# (scripts/build-release.sh), so this RUN layer is a cache hit on every rebuild and the
# upgrade never actually re-runs -- which is how CVE-2026-14456 (libcrypto3/libssl3
# 3.5.7-r0) survived a rebuild and blocked the release gate. Naming the fixed version
# changes this layer's cache key and fails the build loudly if it is unavailable, rather
# than silently reinstalling the vulnerable one. Raise the floor on the next advisory.
RUN apk upgrade --no-cache \
    && apk add --no-cache 'libcrypto3>=3.5.8-r0' 'libssl3>=3.5.8-r0' 'libuuid>=2.41.6-r0' \
    && apk add --no-cache docker-cli \
    && python -m pip uninstall --yes pip setuptools wheel

WORKDIR /app
COPY health-inspector/inspector.py /app/inspector.py

ENTRYPOINT ["python", "/app/inspector.py"]
