#!/bin/sh
set -eu

: "${ALERT_WEBHOOK_URL:?ALERT_WEBHOOK_URL is required}"
: "${ALERTMANAGER_CONFIG_PATH:?ALERTMANAGER_CONFIG_PATH is required}"

case "$ALERT_WEBHOOK_URL" in
  https://*) ;;
  *) echo "ALERT_WEBHOOK_URL must use HTTPS" >&2; exit 1 ;;
esac

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
template="$script_dir/../observability/alertmanager.yml.example"
escaped_url="$(printf '%s' "$ALERT_WEBHOOK_URL" | sed 's/[&|]/\\&/g')"
umask 077
sed "s|__ALERT_WEBHOOK_URL__|$escaped_url|" "$template" >"$ALERTMANAGER_CONFIG_PATH"
grep -q '__ALERT_WEBHOOK_URL__' "$ALERTMANAGER_CONFIG_PATH" &&
  { echo "failed to render alertmanager config" >&2; exit 1; }

# Alertmanager runs as nobody (65534). Keep the rendered webhook URL hidden
# from other host users while allowing the container process to read it.
chmod 640 "$ALERTMANAGER_CONFIG_PATH"
if [ "$(id -u)" -eq 0 ]; then
  chown 0:65534 "$ALERTMANAGER_CONFIG_PATH"
fi

echo "Alertmanager configuration rendered: $ALERTMANAGER_CONFIG_PATH"
