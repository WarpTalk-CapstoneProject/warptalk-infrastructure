$migrationsDir = "scripts/migrations"
$files = @(
  "000-init-migrations.sql",
  "001-14-04-2026-rename-meeting.sql",
  "002-16-04-2026-rename-meeting-columns.sql",
  "003-17-04-2026-uppercase-type.sql",
  "004-01-05-2026-add-notification-message-table.sql",
  "005-09-05-2026-add-admin-notifications-table.sql",
  "006-14-05-2026-convert-transcript-status-to-enum.sql",
  "006-15-05-2026-rename-participant-is-translation-audio-enabled.sql",
  "007-16-05-2026-add-meeting-schema.sql",
  "008-20-05-2026-add-translation-room-views.sql",
  "007-03-06-2026-separate-workspace-schema-from-auth.sql",
  "008-03-06-2026-add-workspace-documents-and-glossary.sql",
  "009-04-06-2026-add-meeting-chat.sql",
  "009-05-06-2026-rename-role-key-to-subject-key.sql",
  "010-12-06-2026-add-chat-mentions.sql",
  "010-12-06-2026-add-can-create-meetings-to-workspace-members.sql",
  "011-12-06-2026-convert-enums-to-varchar.sql",
  "012-14-06-2026-add-meeting-invitation.sql",
  "013-14-06-2026-add-meeting-active-host.sql",
  "014-15-06-2026-convert-translation-and-transcript-enums-to-varchar.sql",
  "015-16-06-2026-add-translation-room-invitations.sql",
  "016-03-07-2026-enforce-single-active-subscription.sql",
  "016-14-07-2026-remove-is-sensitive-from-workspace-documents.sql",
  "016-16-07-2026-add-segment-id-to-usage-records.sql",
  "017-15-07-2026-translation-cluster-finalize.sql",
  "018-16-07-2026-fix-users-user-settings-fk-direction.sql",
  "019-16-07-2026-billing-schema-mismatch-and-idempotency.sql",
  "020-17-07-2026-refresh-token-family-reuse-detection.sql",
  "021-20-07-2026-add-translation-room-sessions.sql",
  "022-20-07-2026-add-transcript-segment-id-to-billing.sql",
  "023-20-07-2026-switch-payment-provider-to-stripe.sql",
  "024-20-07-2026-drop-transcript-translations.sql"
)

# Initialize migrations table
Write-Host "Initializing tracking table..."
Get-Content "$migrationsDir/000-init-migrations.sql" -Raw | docker exec -i warptalk-postgres psql -U postgres -d warptalk

foreach ($f in $files) {
    if ($f -eq "000-init-migrations.sql") { continue }
    $filePath = "$migrationsDir/$f"
    if (Test-Path $filePath) {
        # Check if already applied
        $isApplied = docker exec -i warptalk-postgres psql -U postgres -d warptalk -tAc "SELECT 1 FROM public.schema_migrations WHERE version='$f';" 2>$null
        if ($isApplied -eq $null -or $isApplied.Trim() -ne "1") {
            Write-Host "Applying migration: $f"
            # run SQL
            Get-Content $filePath -Raw | docker exec -i warptalk-postgres psql -U postgres -d warptalk
            # insert into log
            docker exec -i warptalk-postgres psql -U postgres -d warptalk -c "INSERT INTO public.schema_migrations(version) VALUES ('$f');" -q
        } else {
            Write-Host "Skipping migration: $f (already applied)"
        }
    } else {
        Write-Warning "Migration file not found: $filePath"
    }
}
Write-Host "All migrations processed!"
