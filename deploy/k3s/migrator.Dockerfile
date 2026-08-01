FROM postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15

RUN apk upgrade --no-cache \
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
