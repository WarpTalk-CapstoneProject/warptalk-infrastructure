#!/bin/sh
# Scan every desired digest with the current vulnerability DB and verify its
# Sigstore identity. Newly built digests are signed and attested first.
set -eu

retry_sigstore() {
  attempt=1
  while [ "$attempt" -le 5 ]; do
    if "$@"; then
      return 0
    fi
    [ "$attempt" -lt 5 ] || return 1
    echo "release security: Sigstore request failed ($attempt/5); retrying" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}

if [ "${1:-}" = "--worker" ]; then
  sbom_dir="$2"
  encoded_image="$3"
  image="$(printf '%s' "$encoded_image" | base64 --decode)"
  name="$(printf '%s' "$image" | jq -er '.name')"
  ref="$(printf '%s' "$image" | jq -er '.ref')"
  digest="$(printf '%s' "$image" | jq -er '.digest')"
  source_repository="$(printf '%s' "$image" | jq -er '.sourceRepository')"
  source_commit="$(printf '%s' "$image" | jq -er '.sourceCommit')"
  build_fingerprint="$(printf '%s' "$image" | jq -er '.buildFingerprint')"
  reused="$(printf '%s' "$image" | jq -r '.reused // false')"
  subject="$ref@$digest"
  sbom="$sbom_dir/$name.spdx.json"
  provenance="$sbom_dir/$name.provenance.json"
  verified_provenance="$sbom_dir/$name.provenance.verify.json"

  printf '%s' "$name" | grep -Eq '^[a-z0-9][a-z0-9-]*$'
  printf '%s' "$digest" | grep -Eq '^sha256:[a-f0-9]{64}$'
  printf '%s' "$source_repository" | grep -Eq '^[a-z0-9][a-z0-9-]*$'
  printf '%s' "$source_commit" | grep -Eq '^[a-f0-9]{40}$'
  printf '%s' "$build_fingerprint" | grep -Eq '^[a-f0-9]{64}$'
  case "$reused" in true|false) ;; *) exit 1 ;; esac

  jq -n \
    --arg sourceRepository "$source_repository" \
    --arg sourceCommit "$source_commit" \
    --arg buildFingerprint "$build_fingerprint" \
    '{
      sourceRepository: $sourceRepository,
      sourceCommit: $sourceCommit,
      buildFingerprint: $buildFingerprint
    }' >"$provenance"

  trivy image \
    --format spdx-json \
    --output "$sbom" \
    "$subject"
  trivy sbom \
    --skip-db-update \
    --exit-code 1 \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    "$sbom"

  if [ "$reused" = "false" ]; then
    retry_sigstore cosign sign --yes "$subject"
    retry_sigstore cosign attest --yes \
      --predicate "$sbom" \
      --type spdxjson \
      "$subject"
    retry_sigstore cosign attest --yes \
      --predicate "$provenance" \
      --type custom \
      "$subject"
  fi

  retry_sigstore cosign verify \
    --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
    "$subject" >/dev/null
  retry_sigstore cosign verify-attestation \
    --type spdxjson \
    --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
    "$subject" >/dev/null
  retry_sigstore cosign verify-attestation \
    --type custom \
    --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
    "$subject" >"$verified_provenance"
  jq -s -e \
    --arg sourceRepository "$source_repository" \
    --arg sourceCommit "$source_commit" \
    --arg buildFingerprint "$build_fingerprint" '
    any((.[] | if type == "array" then .[] else . end | .payload);
      (@base64d | fromjson | .predicate |
        if (type == "object" and ((.Data? | type) == "string"))
        then (.Data | fromjson)
        else .
        end
      ) as $predicate |
      $predicate.sourceRepository == $sourceRepository and
      $predicate.sourceCommit == $sourceCommit and
      $predicate.buildFingerprint == $buildFingerprint
    )
  ' "$verified_provenance" >/dev/null
  rm -f "$verified_provenance"
  echo "release security: verified $name ($reused)" >&2
  exit 0
fi

MANIFEST="${RELEASE_MANIFEST:-}"
SBOM_DIR="${SBOM_OUTPUT_DIR:-}"
# Trivy shares a process-wide cache lock and keyless Cosign obtains a GitHub
# OIDC token for every signing operation. The release workflow intentionally
# keeps this at one unless callers provide isolated caches and token handling.
SECURITY_PARALLELISM="${SECURITY_PARALLELISM:-1}"
: "${COSIGN_CERTIFICATE_IDENTITY_REGEXP:?COSIGN_CERTIFICATE_IDENTITY_REGEXP is required}"
: "${COSIGN_CERTIFICATE_OIDC_ISSUER:?COSIGN_CERTIFICATE_OIDC_ISSUER is required}"

[ -r "$MANIFEST" ] || {
  echo "release security: RELEASE_MANIFEST is not readable" >&2
  exit 1
}
[ -n "$SBOM_DIR" ] || {
  echo "release security: SBOM_OUTPUT_DIR is required" >&2
  exit 1
}
case "$SECURITY_PARALLELISM" in
  ''|*[!0-9]*|0) echo "release security: invalid SECURITY_PARALLELISM" >&2; exit 1 ;;
esac
for dependency in base64 cosign jq trivy xargs; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "release security: missing dependency: $dependency" >&2
    exit 1
  }
done

jq -e '
  .schemaVersion == 1 and
  (.images | length > 0) and
  all(.images[];
    (.name | test("^[a-z0-9][a-z0-9-]*$")) and
    (.ref | test("^[^[:space:]@]+$")) and
    (.digest | test("^sha256:[a-f0-9]{64}$")) and
    (.sourceRepository | test("^[a-z0-9][a-z0-9-]*$")) and
    (.sourceCommit | test("^[a-f0-9]{40}$")) and
    (.buildFingerprint | test("^[a-f0-9]{64}$")) and
    ((.reused // false) | type == "boolean")
  )
' "$MANIFEST" >/dev/null

mkdir -p "$SBOM_DIR"
trivy image --download-db-only
export COSIGN_CERTIFICATE_IDENTITY_REGEXP COSIGN_CERTIFICATE_OIDC_ISSUER
jq -r '.images[] | @base64' "$MANIFEST" |
  xargs -P "$SECURITY_PARALLELISM" -n 1 \
    "$0" --worker "$SBOM_DIR"

expected="$(jq '.images | length' "$MANIFEST")"
actual="$(find "$SBOM_DIR" -type f -name '*.spdx.json' | wc -l | tr -d ' ')"
[ "$actual" -eq "$expected" ] || {
  echo "release security: incomplete SBOM set ($actual/$expected)" >&2
  exit 1
}

echo "release security: PASS ($expected images)"
