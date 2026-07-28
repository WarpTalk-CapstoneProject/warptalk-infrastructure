# WarpTalk disaster-recovery runbook

## Targets and ownership

Initial two-VM production targets an RPO of 24 hours and an RTO of 4 hours.
Daily backups contain eight independent PostgreSQL dumps plus one Qdrant
snapshot per collection. Every payload is encrypted with `age` before it is
uploaded to a versioned offsite S3/R2 bucket.

Retention is 7 daily, 4 weekly and 3 monthly recovery sets. A production
operator owns the incident; a second operator verifies the selected backup,
DNS/firewall changes and the final smoke-test report.

Never restore over a running production database. Restore to a clean Data node,
validate it, then switch the App inventory/private address.

## Before an incident

1. Keep `/etc/warptalk/backup.env` mode `0600` and owned by `warptalk`.
2. Keep the `age` private identity outside both production VMs.
3. Enable versioning and retention/lifecycle rules on the offsite bucket.
4. Enable and inspect the timer:

   ```sh
   sudo systemctl enable --now warptalk-backup.timer
   systemctl list-timers warptalk-backup.timer
   journalctl -u warptalk-backup.service
   ```

5. Run `scripts/restore-drill.sh` monthly against the newest downloaded set.
   A drill is successful only when all eight databases and every Qdrant
   collection report `restored`.

## Loss of the App node

1. Declare the App node unavailable and preserve its disk snapshot for
   forensics.
2. Provision a clean supported Linux VM from the production inventory.
3. Restrict SSH and permit Data ports only from the new App private IP.
4. Install Docker, copy the immutable release manifest and protected
   `.env.production`, then run the preflight.
5. Pull the exact image digests from the manifest and start `app.compose.yml`.
6. Move the floating IP or update DNS after `/health/live`,
   `/health/ready`, login, workspace and room smoke tests pass.

No data restore is required because the App node is stateless.

## Loss of the Data node

1. Fence the failed node so two PostgreSQL/RabbitMQ instances cannot accept
   writes simultaneously.
2. Provision a clean Data VM and attach a new encrypted volume.
3. Download one complete backup set from the versioned offsite bucket and
   verify `encrypted-files.sha256`.
4. Run the disposable restore drill before touching the replacement services:

   ```sh
   BACKUP_SET=/srv/recovery/20260727T121609Z \
   AGE_IDENTITY_FILE=/run/secrets/warptalk-backup.agekey \
   RESTORE_REPORT=/srv/recovery/restore-report.json \
   ./scripts/restore-drill.sh
   ```

5. Start the replacement Data stack, restore the same dumps into its eight
   logical databases, and upload each Qdrant collection snapshot with
   `priority=snapshot`.
6. Recreate RabbitMQ exchanges/queues by starting the application against an
   empty broker. Replay Billing outbox records and inspect every DLQ.
7. Point the App inventory at the replacement private IP, then run full smoke
   and settlement checks before reopening traffic.

Redis is treated as rebuildable cache/stream state. PostgreSQL outbox/inbox and
source media are the durable recovery sources.

## Loss or corruption of one PostgreSQL database

1. Stop only the owning service and its workers.
2. Restore that service dump to a new database name, never over the corrupt
   database.
3. Run the service migration runner to forward-fix the restored database.
4. Validate table counts, constraints and the service integration suite.
5. Change only that service's database route and restart it.
6. Reconcile external side effects:
   - Billing: Stripe events, ledger balances, outbox and inbox.
   - Transcript: Redis stream replay and recording-derived recovery.
   - Workspace: object metadata versus the versioned object bucket.

## Loss of RabbitMQ or Redis

- RabbitMQ: start an empty broker, let applications recreate durable topology,
  replay unpublished/failed PostgreSQL outbox messages, and drain DLQs.
- Redis: restore AOF if usable; otherwise start empty. Rebuild projections from
  source services/events. Active meetings must be explicitly ended/restarted
  because in-flight audio stream entries are not reconstructable.

Do not report recovery complete until queue lag and worker heartbeat dashboards
are normal.

## Object storage credential compromise

1. Disable the compromised key without deleting bucket versions.
2. Create a least-privilege replacement key scoped to the required bucket and
   prefix.
3. Rotate `LIVEKIT_EGRESS_S3_*`, Workspace storage and backup credentials in
   protected environment files; application images do not need rebuilding.
4. Restart only consumers of the changed secret.
5. Verify document upload/download, LiveKit Egress output and an encrypted
   backup upload.
6. Review immutable audit logs and bucket access logs for unauthorized reads or
   deletes. Preserve affected versions for forensics.

## Recovery completion checklist

- Restore report says `passed` for 8/8 databases and all Qdrant collections.
- Auth login and refresh work.
- Workspace, room join, SignalR and transcript APIs work.
- LiveKit audio publication and Egress object are verified.
- A Stripe Sandbox event produces exactly one ledger change.
- Outbox backlog, RabbitMQ queues, Redis Streams and worker heartbeats are
  healthy.
- Incident timestamps, selected recovery point, achieved RPO/RTO and follow-up
  actions are recorded.
