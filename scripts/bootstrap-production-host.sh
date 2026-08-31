#!/bin/sh
set -eu

ROLE="${ROLE:-}"
# One or more trusted CIDRs, separated by spaces or commas. Every entry gets its
# own SSH allow rule so the team does not share a single operator /32.
ADMIN_CIDR="${ADMIN_CIDR:-}"
# The tailnet is the primary SSH transport for both operators and the
# release workflow, so the rule that permits it must be rebuilt here.
TAILSCALE_SSH="${TAILSCALE_SSH:-true}"
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
ADMIN_CIDR_LIST="$(printf '%s' "$ADMIN_CIDR" | tr ',' ' ')"
[ -n "$(printf '%s' "$ADMIN_CIDR_LIST" | tr -d ' ')" ] ||
  fail "ADMIN_CIDR is required to avoid locking out SSH"
for admin_cidr_entry in $ADMIN_CIDR_LIST; do
  case "$admin_cidr_entry" in
    0.0.0.0/0|::/0) fail "ADMIN_CIDR must not allow the entire Internet" ;;
    */*) ;;
    *) fail "ADMIN_CIDR entry is not CIDR notation: $admin_cidr_entry" ;;
  esac
done
case "$TAILSCALE_SSH" in
  true|false) ;;
  *) fail "TAILSCALE_SSH must be true or false" ;;
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

# WT-595: this host's OWN private address, which its containers publish onto. Required now,
# because the docker drop-in installed below waits for it — and a host whose own address the
# operator cannot name is a host where this whole class of failure stays possible.
case "$ROLE" in
  app) OWN_PRIVATE_IP="$APP_PRIVATE_IP" ;;
  data) OWN_PRIVATE_IP="$DATA_PRIVATE_IP" ;;
  infra) OWN_PRIVATE_IP="$INFRA_PRIVATE_IP" ;;
esac
[ -n "$OWN_PRIVATE_IP" ] ||
  fail "the ${ROLE} role needs its own private IP ($(echo "$ROLE" | tr '[:lower:]' '[:upper:]')_PRIVATE_IP) so Docker can be made to wait for it"

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

# WT-595 — Docker must not start before the address its containers publish onto exists.
#
# On 30/08/2026 all three production VMs rebooted and production stayed down for 27 hours. Every
# container that publishes to a private IP — postgres, pgbouncer, qdrant, minio, redis, rabbitmq,
# prometheus, grafana, seq, alertmanager, otel-collector — failed at CREATE time with:
#
#   failed to bind host port 10.20.0.20:5432/tcp: cannot assign requested address
#
# because eth0 gets its 10.20.0.x address from DHCP and docker.service had already started. This
# is not a crash, so `restart: unless-stopped` never retried it: the containers sat in
# Exited (255) until a person intervened. Only the exporters survived, because they bind no
# private IP — which is why monitoring looked fine.
#
# docker.service already carried After=network-online.target and systemd-networkd-wait-online was
# enabled, and it still lost the race: "the network is up" is not "eth0 holds THIS address".
# So the condition is stated exactly. ExecStartPre blocks the unit, so nothing docker starts can
# run before the bind target is assignable.
#
# The lasting fix is a STATIC private address on all three VMs — see deploy/production/README.md.
# This drop-in is what makes a reboot survivable either way, and is deliberately kept even once
# the addresses are static: it costs nothing when the address is already there, and it turns a
# reintroduced DHCP lease from a 27-hour outage into a slower boot.
if [ "$DRY_RUN" = "true" ]; then
  echo "DRY-RUN: install /usr/local/sbin/warptalk-wait-for-bind-address"
  echo "DRY-RUN: install /etc/systemd/system/docker.service.d/10-wait-for-bind-address.conf"
else
  cat >/usr/local/sbin/warptalk-wait-for-bind-address <<'WAIT_SCRIPT'
#!/bin/sh
# Blocks until $1 is assigned to a local interface. WT-595.
#
# Bounded: a host that genuinely never gets the address must fail loudly rather than hang the
# boot forever. Docker then starts anyway and the bind errors are the same as before — but the
# journal names the cause on line one instead of leaving it to be reconstructed from container
# exit codes.
set -eu
address="${1:?usage: warptalk-wait-for-bind-address <ip>}"
deadline="${2:-120}"
elapsed=0
while [ "$elapsed" -lt "$deadline" ]; do
  if ip -o address show scope global | grep -Fq " $address/"; then
    [ "$elapsed" -eq 0 ] ||
      echo "warptalk-wait-for-bind-address: $address appeared after ${elapsed}s"
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
echo "warptalk-wait-for-bind-address: $address never appeared in ${deadline}s;" \
     "containers that publish onto it will fail to bind" >&2
exit 0
WAIT_SCRIPT
  chmod 0755 /usr/local/sbin/warptalk-wait-for-bind-address

  install -m 0755 -d /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/10-wait-for-bind-address.conf <<DROP_IN
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStartPre=/usr/local/sbin/warptalk-wait-for-bind-address ${OWN_PRIVATE_IP}
DROP_IN
  systemctl daemon-reload
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
for admin_cidr_entry in $ADMIN_CIDR_LIST; do
  run ufw allow from "$admin_cidr_entry" to any port "$SSH_PORT" proto tcp
done

# Without this rule a re-run of this script silently severs every tailnet SSH
# path, including the release workflow's production job, which joins the tailnet
# and then connects to the App host.
if [ "$TAILSCALE_SSH" = "true" ]; then
  run ufw allow in on tailscale0 to any port "$SSH_PORT" proto tcp comment "SSH over Tailscale"
fi

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
