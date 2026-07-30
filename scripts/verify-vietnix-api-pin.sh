#!/usr/bin/env bash
set -euo pipefail

readonly vietnix_api_url="${VIETNIX_API_URL:-https://api.vietnix.cloud/v3}"
readonly vietnix_api_pin="${VIETNIX_API_PIN:-sha256//wRusC9rJSg0e4iS6Epo0GZVCBMFB/96t7mL51KBFS4Y=}"

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
