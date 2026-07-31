#!/bin/sh
set -eu

ROLE="${ROLE:-}"
DEVICE="${DEVICE:-}"
MOUNTPOINT="${MOUNTPOINT:-/srv/warptalk}"
FSTAB_PATH="${FSTAB_PATH:-/etc/fstab}"

fail() {
  echo "mount-production-data-volume: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root"
case "$ROLE" in
  data)
    expected_bytes=37580963840
    expected_label=warptalk-data
    ;;
  infra)
    expected_bytes=16106127360
    expected_label=warptalk-infra
    ;;
  *)
    fail "ROLE must be data or infra"
    ;;
esac
[ -n "$DEVICE" ] || fail "DEVICE is required"
[ "$MOUNTPOINT" = "/srv/warptalk" ] ||
  fail "MOUNTPOINT must be /srv/warptalk"

device="$(readlink -f "$DEVICE")"
[ -b "$device" ] || fail "DEVICE must resolve to a block device"
[ "$(lsblk -dno TYPE "$device")" = "disk" ] ||
  fail "DEVICE must be a whole disk"
[ "$(lsblk -bndo SIZE "$device")" = "$expected_bytes" ] ||
  fail "DEVICE size does not match the $ROLE durable volume"
[ "$(lsblk -nrpo NAME "$device" | wc -l | tr -d ' ')" = "1" ] ||
  fail "DEVICE already has partitions"

root_source="$(findmnt -rn -o SOURCE /)"
[ "$(readlink -f "$root_source")" != "$device" ] ||
  fail "refusing to operate on the root device"

install -d -m 0755 /run/lock
exec 9>"/run/lock/warptalk-${ROLE}-volume.lock"
flock -n 9 || fail "another volume mount operation is running"

existing_target="$(findmnt -rn -S "$device" -o TARGET || true)"
if [ -n "$existing_target" ] && [ "$existing_target" != "$MOUNTPOINT" ]; then
  fail "DEVICE is already mounted at $existing_target"
fi

filesystem="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"
label="$(blkid -s LABEL -o value "$device" 2>/dev/null || true)"
if [ -z "$filesystem" ]; then
  mkfs.ext4 -F -L "$expected_label" "$device"
else
  [ "$filesystem" = "ext4" ] && [ "$label" = "$expected_label" ] ||
    fail "existing filesystem is not the expected WarpTalk volume"
fi

uuid="$(blkid -s UUID -o value "$device")"
[ -n "$uuid" ] || fail "could not resolve filesystem UUID"
install -d -m 0750 -o root -g docker "$MOUNTPOINT"

fstab_line="UUID=$uuid $MOUNTPOINT ext4 defaults,nofail 0 2"
if grep -Eq "^[^#]+[[:space:]]+${MOUNTPOINT}[[:space:]]+" "$FSTAB_PATH"; then
  grep -Fq "$fstab_line" "$FSTAB_PATH" ||
    fail "$FSTAB_PATH already contains a conflicting $MOUNTPOINT entry"
else
  printf '%s\n' "$fstab_line" >>"$FSTAB_PATH"
fi

if ! findmnt --mountpoint "$MOUNTPOINT" >/dev/null 2>&1; then
  mount "$MOUNTPOINT"
fi
findmnt --mountpoint "$MOUNTPOINT" >/dev/null 2>&1 ||
  fail "mount verification failed"

mounted_uuid="$(findmnt -rn --mountpoint "$MOUNTPOINT" -o UUID)"
[ "$mounted_uuid" = "$uuid" ] ||
  fail "mounted UUID does not match DEVICE"

echo "mount-production-data-volume: PASS role=$ROLE device=$device uuid=$uuid"
