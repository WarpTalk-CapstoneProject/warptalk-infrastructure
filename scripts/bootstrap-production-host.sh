#!/bin/sh
set -eu

ROLE="${ROLE:-}"
ADMIN_CIDR="${ADMIN_CIDR:-}"
APP_PRIVATE_IP="${APP_PRIVATE_IP:-}"
DATA_PRIVATE_IP="${DATA_PRIVATE_IP:-}"
INFRA_PRIVATE_IP="${INFRA_PRIVATE_IP:-}"
SSH_PORT="${SSH_PORT:-22}"
DEPLOY_USER="${DEPLOY_USER:-cloud-user}"
DRY_RUN="${DRY_RUN:-false}"

fail() {
  echo "bootstrap-production-host: $*" >&2
  exit 1
}

run() {
  if [ "$DRY_RUN" = "true" ]; then
    printf 'DRY-RUN:'
    printf ' %s' "$@"
    printf '\n'
    return
  fi
  "$@"
}

[ "$(id -u)" -eq 0 ] || fail "run as root"
[ "$ROLE" = "app" ] || [ "$ROLE" = "data" ] || [ "$ROLE" = "infra" ] ||
  fail "ROLE must be app, data, or infra"
[ -n "$ADMIN_CIDR" ] || fail "ADMIN_CIDR is required to avoid locking out SSH"
case "$ADMIN_CIDR" in
  0.0.0.0/0|::/0) fail "ADMIN_CIDR must not allow the entire Internet" ;;
esac
case "$SSH_PORT" in
  *[!0-9]*|"") fail "SSH_PORT must be numeric" ;;
esac
id "$DEPLOY_USER" >/dev/null 2>&1 ||
  fail "DEPLOY_USER does not exist"
if [ "$ROLE" = "data" ]; then
  [ -n "$APP_PRIVATE_IP" ] || fail "APP_PRIVATE_IP is required for the data role"
  [ -n "$INFRA_PRIVATE_IP" ] || fail "INFRA_PRIVATE_IP is required for the data role"
fi
if [ "$ROLE" = "infra" ]; then
  [ -n "$APP_PRIVATE_IP" ] || fail "APP_PRIVATE_IP is required for the infra role"
  [ -n "$DATA_PRIVATE_IP" ] || fail "DATA_PRIVATE_IP is required for the infra role"
fi

if [ -r /etc/os-release ]; then
  . /etc/os-release
else
  fail "cannot identify the operating system"
fi
[ "${ID:-}" = "ubuntu" ] || fail "supported host OS is Ubuntu"
case "${VERSION_ID:-}" in
  24.04|26.04) ;;
  *) fail "supported Ubuntu releases are 24.04 and 26.04" ;;
esac

export DEBIAN_FRONTEND=noninteractive
run apt-get update
run apt-get install -y \
  ca-certificates curl gnupg jq ufw fail2ban unattended-upgrades \
  age postgresql-client

if ! command -v docker >/dev/null 2>&1; then
  run install -m 0755 -d /etc/apt/keyrings
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: install Docker repository signing key"
  else
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    architecture="$(dpkg --print-architecture)"
    printf '%s\n' \
      "deb [arch=$architecture signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
      >/etc/apt/sources.list.d/docker.list
  fi
  run apt-get update
  run apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if [ "$DRY_RUN" = "true" ]; then
  echo "DRY-RUN: write /etc/docker/daemon.json"
  echo "DRY-RUN: write /etc/sysctl.d/99-warptalk.conf"
else
  install -m 0755 -d /etc/docker
  if [ "$ROLE" = "app" ]; then
    printf '%s\n' \
      '{' \
      '  "live-restore": true,' \
      '  "log-driver": "json-file",' \
      '  "log-opts": {' \
      '    "max-size": "20m",' \
      '    "max-file": "5"' \
      '  }' \
      '}' >/etc/docker/daemon.json
  else
    printf '%s\n' \
      '{' \
      '  "data-root": "/srv/warptalk/docker",' \
      '  "live-restore": true,' \
      '  "log-driver": "json-file",' \
      '  "log-opts": {' \
      '    "max-size": "20m",' \
      '    "max-file": "5"' \
      '  }' \
      '}' >/etc/docker/daemon.json
  fi
  printf '%s\n' \
    'vm.swappiness=10' \
    'fs.file-max=1048576' \
    'net.core.somaxconn=4096' \
    'net.ipv4.tcp_syncookies=1' \
    >/etc/sysctl.d/99-warptalk.conf
  sysctl --system
fi

run systemctl enable --now docker
run systemctl restart docker
run usermod -aG docker "$DEPLOY_USER"
run systemctl enable --now fail2ban
run systemctl enable --now unattended-upgrades

if [ "$ROLE" = "data" ] && ! id warptalk >/dev/null 2>&1; then
  run useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin warptalk
fi

run ufw --force reset
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow from "$ADMIN_CIDR" to any port "$SSH_PORT" proto tcp

if [ "$ROLE" = "app" ]; then
  run ufw allow 80/tcp
  run ufw allow 443/tcp
  run ufw allow 443/udp
elif [ "$ROLE" = "data" ]; then
  for port in 22 5432 6432 9000 9001 6333 6334; do
    run ufw allow from "$APP_PRIVATE_IP" to any port "$port" proto tcp
  done
  for port in 5432 9000 6333 6334; do
    run ufw allow from "$INFRA_PRIVATE_IP" to any port "$port" proto tcp
  done
else
  for port in 22 6379 5672 15672 15692 4317 4318 5341 9090 9093 3001; do
    run ufw allow from "$APP_PRIVATE_IP" to any port "$port" proto tcp
  done
fi

run ufw --force enable
run install -d -m 0750 -o root -g docker /opt/warptalk
run install -d -m 0750 /etc/warptalk
if [ "$ROLE" = "data" ]; then
  run install -d -m 0700 -o warptalk -g warptalk /var/backups/warptalk
else
  run install -d -m 0750 /var/backups/warptalk
fi

echo "bootstrap-production-host: PASS role=$ROLE"
