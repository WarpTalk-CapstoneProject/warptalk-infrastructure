#!/usr/bin/env bash
set -euo pipefail

readonly vietnix_api_url="${VIETNIX_API_URL:-https://api.vietnix.cloud/v3}"
# Two pins, either of which must match (curl --pinnedpubkey accepts a ';'-separated list):
#   * the api.vietnix.cloud leaf key (Let's Encrypt cert issued 2026-08-28);
#   * the Let's Encrypt YE1 intermediate that issues it (valid to 2028-09-02).
# The single leaf pin broke on 30 Sep when the certificate was renewed with a new key. Pinning the
# issuing intermediate as well keeps renewals working while still refusing any other CA. Verified
# before updating: the same leaf hash from this Mac and from the App VM (a different network), and
# normal CA validation OK on both.
readonly vietnix_api_pin="${VIETNIX_API_PIN:-sha256//ft55JI+5DWCMmmqT3Cozs0KPWgfiD9G8x9LVP+IHuXY=;sha256//brzvtCELCIZUo4sD/qPX0ccRtPsd3DY6RfmxpOU9oB4=}"

curl \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 10 \
  --max-time 20 \
  --pinnedpubkey "$vietnix_api_pin" \
  --output /dev/null \
  "$vietnix_api_url"

echo "Vietnix API TLS pin verified."
