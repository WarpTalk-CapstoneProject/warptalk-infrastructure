FROM postgres:18-alpine

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
