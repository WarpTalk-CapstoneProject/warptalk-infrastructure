#!/bin/sh
# Refuse to start a release on this host unless there is enough free disk to
# pull and extract the whole image set for this role.
#
# Release run 31060647847 (prod-20260806-livekit-reconnect-fix-v9) deployed the
# data and infra roles, then died mid-pull on the app role with
# "no space left on device" while extracting a layer to overlayfs. Production
# was left split across two release versions, which is a worse failure than a
# release that declines to begin. This gate makes that failure mode impossible:
# the disk is checked before the first byte is pulled, so a release either runs
# everywhere or nowhere.
#
# Sizing is done against the actual image set, not a round number. For every
# image this role will pull we ask the registry for the compressed layer sizes,
# skip the ones already resident, and scale the total by an extraction factor
# because containerd holds both the compressed blob in the content store and
# the decompressed layer in the overlayfs snapshotter.
set -eu

OVERRIDE_FILE="${1:-}"
[ -n "$OVERRIDE_FILE" ] || {
  echo "usage: preflight-release-disk.sh <compose-override.json>" >&2
  exit 1
}
test -r "$OVERRIDE_FILE" || {
  echo "preflight: cannot read compose override: $OVERRIDE_FILE" >&2
  exit 1
}

# Percentage of the compressed pull size to reserve for the extracted layers
# plus the retained blobs. 250 means "reserve 2.5x the download".
DISK_EXTRACT_FACTOR_PERCENT="${DISK_EXTRACT_FACTOR_PERCENT:-250}"
# Absolute margin kept free on top of the computed requirement, in MiB.
DISK_MARGIN_MIB="${DISK_MARGIN_MIB:-3072}"
# Floor that applies even when the registry cannot be queried, in MiB. Sized
# from a measured full app-role pull (~8 GiB of extracted layers).
DISK_MIN_FREE_MIB="${DISK_MIN_FREE_MIB:-8192}"
# Per-image fallback when a single manifest cannot be inspected, in MiB.
DISK_UNKNOWN_IMAGE_MIB="${DISK_UNKNOWN_IMAGE_MIB:-600}"
TARGET_PATH="${DISK_TARGET_PATH:-/var/lib/containerd}"

value=""
for var in DISK_EXTRACT_FACTOR_PERCENT DISK_MARGIN_MIB DISK_MIN_FREE_MIB \
  DISK_UNKNOWN_IMAGE_MIB; do
  eval "value=\$$var"
  echo "$value" | grep -Eq '^[0-9]+$' || {
    echo "preflight: $var must be a non-negative integer" >&2
    exit 1
  }
done

command -v jq >/dev/null 2>&1 || {
  echo "preflight: jq is required" >&2
  exit 1
}

# Fall back to the filesystem root if the containerd directory is absent (for
# example on a host that stores images elsewhere).
[ -d "$TARGET_PATH" ] || TARGET_PATH=/

available_mib="$(df -Pm "$TARGET_PATH" | awk 'NR==2 {print $4}')"
echo "$available_mib" | grep -Eq '^[0-9]+$' || {
  echo "preflight: could not determine free space on $TARGET_PATH" >&2
  exit 1
}

pull_mib=0
missing_images=0
resident_images=0
unsized_images=0

# .services[].image is written by release-override.jq as "<ref>@<digest>".
for image in $(jq -r '.services[]?.image // empty' "$OVERRIDE_FILE"); do
  if docker image inspect "$image" >/dev/null 2>&1; then
    resident_images=$((resident_images + 1))
    continue
  fi
  missing_images=$((missing_images + 1))

  layer_bytes=''
  if manifest="$(docker manifest inspect "$image" 2>/dev/null)"; then
    layer_bytes="$(printf '%s' "$manifest" |
      jq '[.. | objects | select(has("size") and has("digest")) | .size]
          | add // empty' 2>/dev/null || true)"
  fi

  if echo "$layer_bytes" | grep -Eq '^[0-9]+$' && [ "$layer_bytes" -gt 0 ]; then
    pull_mib=$((pull_mib + layer_bytes / 1048576))
  else
    unsized_images=$((unsized_images + 1))
    pull_mib=$((pull_mib + DISK_UNKNOWN_IMAGE_MIB))
  fi
done

required_mib=$(((pull_mib * DISK_EXTRACT_FACTOR_PERCENT) / 100 + DISK_MARGIN_MIB))
if [ "$required_mib" -lt "$DISK_MIN_FREE_MIB" ]; then
  required_mib="$DISK_MIN_FREE_MIB"
fi

echo "preflight: $resident_images image(s) already resident, $missing_images to pull" >&2
if [ "$unsized_images" -gt 0 ]; then
  echo "preflight: $unsized_images image(s) could not be sized from the registry;" \
    "using ${DISK_UNKNOWN_IMAGE_MIB}MiB each" >&2
fi
echo "preflight: compressed pull ~${pull_mib}MiB, required ${required_mib}MiB," \
  "available ${available_mib}MiB on $TARGET_PATH" >&2

if [ "$available_mib" -lt "$required_mib" ]; then
  cat >&2 <<EOF
preflight: refusing to start this release — insufficient disk on $(hostname).

  available : ${available_mib}MiB
  required  : ${required_mib}MiB
  shortfall : $((required_mib - available_mib))MiB

Reclaim space before retrying, for example:
  sh scripts/prune-release-artifacts.sh

Deploying now would risk leaving production split across two release versions,
which is what this gate exists to prevent.
EOF
  exit 1
fi

echo "preflight: disk check passed" >&2
