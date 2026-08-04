#!/bin/sh
set -eu

VIETNIX_SSH_KEY="${VIETNIX_SSH_KEY:-$HOME/.ssh/warptalk_vietnix_codex_ed25519}"
VIETNIX_SSH_USER="${VIETNIX_SSH_USER:-cloud-user}"
VIETNIX_APP_IP="${VIETNIX_APP_IP:-100.72.255.18}"
VIETNIX_DATA_IP="${VIETNIX_DATA_IP:-10.20.0.20}"
VIETNIX_INFRA_IP="${VIETNIX_INFRA_IP:-10.20.0.30}"

fail() {
  echo "vietnix-shell: $*" >&2
  exit 1
}

role="${1:-}"
[ -n "$role" ] || fail "usage: vietnix-shell.sh app|data|infra [remote-command...]"
shift

case "$role" in
  app|data|infra) ;;
  *) fail "role must be app, data, or infra" ;;
esac

[ -f "$VIETNIX_SSH_KEY" ] || fail "SSH key not found: $VIETNIX_SSH_KEY"

case "$role" in
  app)
    exec ssh -i "$VIETNIX_SSH_KEY" -o StrictHostKeyChecking=accept-new \
      "$VIETNIX_SSH_USER@$VIETNIX_APP_IP" "$@"
    ;;
  data)
    target_ip="$VIETNIX_DATA_IP"
    ;;
  infra)
    target_ip="$VIETNIX_INFRA_IP"
    ;;
esac

exec ssh -i "$VIETNIX_SSH_KEY" -o StrictHostKeyChecking=accept-new \
  -o ProxyCommand="ssh -i $VIETNIX_SSH_KEY -W %h:%p $VIETNIX_SSH_USER@$VIETNIX_APP_IP" \
  "$VIETNIX_SSH_USER@$target_ip" "$@"
