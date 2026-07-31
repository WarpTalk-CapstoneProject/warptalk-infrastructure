param(
    [string]$Container = "warptalk-postgres",
    [string]$Database = "warptalk",
    [string]$User = "postgres",
    [int]$Workers = 10
)

$ErrorActionPreference = "Stop"

function Invoke-Db([string]$Sql) {
    $Sql | docker exec -i $Container psql -U $User -d $Database -v ON_ERROR_STOP=1 -qAt
}

$setup = @"
DELETE FROM subscription.credit_transactions WHERE subscription_id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.usage_records WHERE subscription_id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.subscriptions WHERE id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.plans WHERE id = '11000000-0000-0000-0000-000000000041';

INSERT INTO subscription.plans (
    id, name, slug, tier, price, billing_cycle, credits_per_cycle,
    overage_cap_credits, overage_price_per_credit, low_balance_threshold_credits,
    rollover_cap_credits, invoice_terms_days, invoice_grace_hours,
    max_participants, max_languages, features
) VALUES (
    '11000000-0000-0000-0000-000000000041', 'Phase 3 Concurrency', 'phase3-concurrency-041', 'enterprise', 1000000, 'monthly', 1000,
    5000, 4.0000, 6000, 100, 15, 360,
    10, 5, '{}'::jsonb
);

INSERT INTO subscription.subscriptions (
    id, user_id, workspace_id, plan_id, status, credits_remaining, credits_used_this_cycle,
    current_period_start, current_period_end, is_active
) VALUES
(
    '21000000-0000-0000-0000-000000000041',
    '31000000-0000-0000-0000-000000000041',
    '41000000-0000-0000-0000-000000000041',
    '11000000-0000-0000-0000-000000000041',
    'active', 1000, 0,
    now() - interval '1 month', now() + interval '1 month', true
),
(
    '22000000-0000-0000-0000-000000000041',
    '32000000-0000-0000-0000-000000000041',
    '42000000-0000-0000-0000-000000000041',
    '11000000-0000-0000-0000-000000000041',
    'active', 1000, 0,
    now() - interval '1 month', now() + interval '1 month', true
);
"@

Invoke-Db $setup | Out-Null

$jobs = 1..$Workers | ForEach-Object {
    $key = "phase3-concurrency-different-$($_)"
    $sql = @"
SELECT applied
FROM subscription.settle_usage_charge(
    '21000000-0000-0000-0000-000000000041',
    '31000000-0000-0000-0000-000000000041',
    '41000000-0000-0000-0000-000000000041',
    'AI_ASSISTANT',
    'AI_ASSISTANT',
    NULL,
    'usage',
    NULL,
    NULL,
    150,
    'token_out',
    150,
    '$key',
    NULL,
    1.000000,
    'VND',
    '{"source":"phase3-concurrency"}'::jsonb
);
"@
    Start-Job -ScriptBlock {
        param($Container, $Database, $User, $Sql)
        $Sql | docker exec -i $Container psql -U $User -d $Database -v ON_ERROR_STOP=1 -qAt
    } -ArgumentList $Container, $Database, $User, $sql
}

$jobs | Receive-Job -Wait -AutoRemoveJob | Out-Null

$differentResult = Invoke-Db @"
SELECT credits_remaining || ',' || credits_used_this_cycle || ',' || overage_credits_this_cycle || ',' || service_state || ',' || count(t.id)
FROM subscription.subscriptions s
JOIN subscription.credit_transactions t ON t.subscription_id = s.id
WHERE s.id = '21000000-0000-0000-0000-000000000041'
GROUP BY s.credits_remaining, s.credits_used_this_cycle, s.overage_credits_this_cycle, s.service_state;
"@

if ($differentResult -ne "-500,1500,500,in_overage,$Workers") {
    throw "Different-key concurrency failed. Actual: $differentResult"
}

$jobs = 1..$Workers | ForEach-Object {
    $sql = @"
SELECT applied
FROM subscription.settle_usage_charge(
    '22000000-0000-0000-0000-000000000041',
    '32000000-0000-0000-0000-000000000041',
    '42000000-0000-0000-0000-000000000041',
    'AI_ASSISTANT',
    'AI_ASSISTANT',
    NULL,
    'usage',
    NULL,
    NULL,
    150,
    'token_out',
    150,
    'phase3-concurrency-same-key',
    NULL,
    1.000000,
    'VND',
    '{"source":"phase3-concurrency"}'::jsonb
);
"@
    Start-Job -ScriptBlock {
        param($Container, $Database, $User, $Sql)
        $Sql | docker exec -i $Container psql -U $User -d $Database -v ON_ERROR_STOP=1 -qAt
    } -ArgumentList $Container, $Database, $User, $sql
}

$jobs | Receive-Job -Wait -AutoRemoveJob | Out-Null

$sameKeyResult = Invoke-Db @"
SELECT credits_remaining || ',' || credits_used_this_cycle || ',' || overage_credits_this_cycle || ',' || service_state || ',' || count(t.id)
FROM subscription.subscriptions s
JOIN subscription.credit_transactions t ON t.subscription_id = s.id
WHERE s.id = '22000000-0000-0000-0000-000000000041'
GROUP BY s.credits_remaining, s.credits_used_this_cycle, s.overage_credits_this_cycle, s.service_state;
"@

if ($sameKeyResult -ne "850,150,0,low_balance,1") {
    throw "Same-key idempotency concurrency failed. Actual: $sameKeyResult"
}

$cleanup = @"
DELETE FROM subscription.credit_transactions WHERE subscription_id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.usage_records WHERE subscription_id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.subscriptions WHERE id IN (
    '21000000-0000-0000-0000-000000000041',
    '22000000-0000-0000-0000-000000000041'
);
DELETE FROM subscription.plans WHERE id = '11000000-0000-0000-0000-000000000041';
"@

Invoke-Db $cleanup | Out-Null

Write-Host "Phase 3 settlement concurrency smoke passed."
