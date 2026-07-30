#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
BILLING_TEMPLATE="$ROOT_DIR/observability/billing-cost-queries.yml.example"
LIVEKIT_TEMPLATE="$ROOT_DIR/observability/livekit-cost-queries.yml.example"
WORKSPACE_STORAGE_TEMPLATE="$ROOT_DIR/observability/workspace-storage-queries.yml.example"
RULES_TEMPLATE="$ROOT_DIR/observability/alerts/warptalk.cost.rules.yml.example"
BILLING_OUTPUT="${BILLING_COST_QUERIES_PATH:-$ROOT_DIR/observability/billing-cost-queries.yml}"
LIVEKIT_OUTPUT="${LIVEKIT_COST_QUERIES_PATH:-$ROOT_DIR/observability/livekit-cost-queries.yml}"
WORKSPACE_STORAGE_OUTPUT="${WORKSPACE_STORAGE_QUERIES_PATH:-$ROOT_DIR/observability/workspace-storage-queries.yml}"
RULES_OUTPUT="${COST_RULES_PATH:-$ROOT_DIR/observability/alerts/warptalk.cost.rules.yml}"

required_values="
AI_COST_STT_USD_PER_MINUTE
AI_COST_TRANSLATION_USD_PER_MINUTE
AI_COST_TTS_USD_PER_MINUTE
AI_COST_VOICE_CLONE_USD_PER_MINUTE
AI_BUDGET_STT_USD
AI_BUDGET_TRANSLATION_USD
AI_BUDGET_TTS_USD
AI_BUDGET_VOICE_CLONE_USD
LIVEKIT_COST_USD_PER_ROOM_MINUTE
LIVEKIT_MONTHLY_BUDGET_USD
OBJECT_STORAGE_BUDGET_GB
"

for name in $required_values; do
  eval "value=\${$name:-}"
  if ! printf '%s\n' "$value" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
    echo "$name must be a non-negative decimal number" >&2
    exit 1
  fi
done

render() {
  input="$1"
  output="$2"
  shift 2
  temporary="$(mktemp "${output}.tmp.XXXXXX")"
  cp "$input" "$temporary"
  while [ "$#" -gt 0 ]; do
    token="$1"
    value="$2"
    shift 2
    sed "s|$token|$value|g" "$temporary" > "${temporary}.next"
    mv "${temporary}.next" "$temporary"
  done
  chmod 600 "$temporary"
  mv "$temporary" "$output"
}

render "$BILLING_TEMPLATE" "$BILLING_OUTPUT" \
  __STT_COST_USD_PER_MINUTE__ "$AI_COST_STT_USD_PER_MINUTE" \
  __TRANSLATION_COST_USD_PER_MINUTE__ "$AI_COST_TRANSLATION_USD_PER_MINUTE" \
  __TTS_COST_USD_PER_MINUTE__ "$AI_COST_TTS_USD_PER_MINUTE" \
  __VOICE_CLONE_COST_USD_PER_MINUTE__ "$AI_COST_VOICE_CLONE_USD_PER_MINUTE" \
  __STT_MONTHLY_BUDGET_USD__ "$AI_BUDGET_STT_USD" \
  __TRANSLATION_MONTHLY_BUDGET_USD__ "$AI_BUDGET_TRANSLATION_USD" \
  __TTS_MONTHLY_BUDGET_USD__ "$AI_BUDGET_TTS_USD" \
  __VOICE_CLONE_MONTHLY_BUDGET_USD__ "$AI_BUDGET_VOICE_CLONE_USD"

render "$LIVEKIT_TEMPLATE" "$LIVEKIT_OUTPUT" \
  __LIVEKIT_COST_USD_PER_ROOM_MINUTE__ "$LIVEKIT_COST_USD_PER_ROOM_MINUTE" \
  __LIVEKIT_MONTHLY_BUDGET_USD__ "$LIVEKIT_MONTHLY_BUDGET_USD" \
  __OBJECT_STORAGE_BUDGET_GB__ "$OBJECT_STORAGE_BUDGET_GB"

render "$WORKSPACE_STORAGE_TEMPLATE" "$WORKSPACE_STORAGE_OUTPUT"

render "$RULES_TEMPLATE" "$RULES_OUTPUT" \
  __OBJECT_STORAGE_BUDGET_GB__ "$OBJECT_STORAGE_BUDGET_GB"

echo "Cost observability configuration rendered."
