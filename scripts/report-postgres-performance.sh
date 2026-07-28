#!/usr/bin/env sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

DATABASES="${WARPTALK_DATABASES:-warptalk_auth warptalk_workspace warptalk_translation_room warptalk_transcript warptalk_notification warptalk_meeting warptalk_billing warptalk_assistant}"
TOP_N="${TOP_N:-20}"

for database in $DATABASES; do
  echo
  echo "=== $database: slow statements by total execution time ==="
  PGDATABASE="$database" psql -X -v ON_ERROR_STOP=1 -P pager=off -c "
    SELECT calls,
           round(total_exec_time::numeric, 2) AS total_ms,
           round(mean_exec_time::numeric, 2) AS mean_ms,
           rows,
           left(regexp_replace(query, '[[:space:]]+', ' ', 'g'), 160) AS query
    FROM pg_stat_statements
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC
    LIMIT $TOP_N;"

  echo "=== $database: sequential-scan/index review ==="
  PGDATABASE="$database" psql -X -v ON_ERROR_STOP=1 -P pager=off -c "
    SELECT schemaname,
           relname,
           seq_scan,
           idx_scan,
           n_live_tup,
           pg_size_pretty(pg_total_relation_size(relid)) AS total_size
    FROM pg_stat_user_tables
    WHERE n_live_tup > 0
    ORDER BY seq_scan DESC, n_live_tup DESC
    LIMIT $TOP_N;"

  echo "=== $database: indexes with no recorded scans ==="
  PGDATABASE="$database" psql -X -v ON_ERROR_STOP=1 -P pager=off -c "
    SELECT schemaname,
           relname,
           indexrelname,
           pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0
      AND indexrelname NOT LIKE '%_pkey'
    ORDER BY pg_relation_size(indexrelid) DESC
    LIMIT $TOP_N;"
done
