#!/bin/sh
set -eu

: "${ALERT_EMAIL_TO:?ALERT_EMAIL_TO is required}"
: "${RESEND_API_KEY:?RESEND_API_KEY is required}"
: "${RESEND_FROM_EMAIL:?RESEND_FROM_EMAIL is required}"
: "${ALERTMANAGER_CONFIG_PATH:?ALERTMANAGER_CONFIG_PATH is required}"

case "$ALERT_EMAIL_TO" in
  *@*.*) ;;
  *) echo "ALERT_EMAIL_TO must be an email address" >&2; exit 1 ;;
esac

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
template="$script_dir/../observability/alertmanager.yml.example"

yaml_sed_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")" |
    sed 's/[\\&|]/\\&/g'
}

smtp_smarthost="$(yaml_sed_quote 'smtp.resend.com:587')"
smtp_from_email="$(yaml_sed_quote "$RESEND_FROM_EMAIL")"
smtp_username="$(yaml_sed_quote 'resend')"
smtp_password="$(yaml_sed_quote "$RESEND_API_KEY")"
alert_email_to="$(yaml_sed_quote "$ALERT_EMAIL_TO")"
umask 077
sed \
  -e "s|__SMTP_SMARTHOST__|$smtp_smarthost|" \
  -e "s|__SMTP_FROM_EMAIL__|$smtp_from_email|" \
  -e "s|__SMTP_USERNAME__|$smtp_username|" \
  -e "s|__SMTP_PASSWORD__|$smtp_password|" \
  -e "s|__ALERT_EMAIL_TO__|$alert_email_to|" \
  "$template" >"$ALERTMANAGER_CONFIG_PATH"
grep -q '__[A-Z_]*__' "$ALERTMANAGER_CONFIG_PATH" &&
  { echo "failed to render alertmanager config" >&2; exit 1; }

# Alertmanager runs as nobody (65534). Keep the rendered SMTP credentials hidden
# from other host users while allowing the container process to read it.
chmod 640 "$ALERTMANAGER_CONFIG_PATH"
if [ "$(id -u)" -eq 0 ]; then
  chown 0:65534 "$ALERTMANAGER_CONFIG_PATH"
fi

echo "Alertmanager configuration rendered: $ALERTMANAGER_CONFIG_PATH"
