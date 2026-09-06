FROM postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15

# The explicit openssl floor is not redundant with `apk upgrade`. The release build pins
# this base image by digest and passes `--cache-from` against a registry BuildKit cache
# (scripts/build-release.sh), so this RUN layer is a cache hit on every rebuild and the
# upgrade never actually re-runs -- which is how CVE-2026-14456 (libcrypto3/libssl3
# 3.5.7-r0) survived a rebuild and blocked the release gate. Naming the fixed version
# changes this layer's cache key and fails the build loudly if it is unavailable, rather
# than silently reinstalling the vulnerable one. Raise the floor on the next advisory.
RUN apk upgrade --no-cache \
    && apk add --no-cache 'libcrypto3>=3.5.8-r0' 'libssl3>=3.5.8-r0' 'libuuid>=2.42.3-r0' \
    && rm -f /usr/local/bin/gosu

COPY scripts /scripts
RUN chmod 0555 \
      /scripts/run-k3s-migrations.sh \
      /scripts/run-migrations.sh \
      /scripts/provision-service-db-users.sh \
      /scripts/extract-logical-databases.sh \
      /scripts/run-logical-database-migrations.sh \
      /scripts/enable-postgres-performance-observability.sh

USER 70:70
ENTRYPOINT ["/scripts/run-k3s-migrations.sh"]
