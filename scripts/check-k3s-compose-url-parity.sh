#!/usr/bin/env bash
# Every public URL the production compose stack builds from ${APP_DOMAIN} / ${API_DOMAIN} must be
# rendered IDENTICALLY by the Kubernetes chart, given the same two domains.
#
# These are the addresses registered outside this repository - Google OAuth redirect URIs, MCP
# client metadata, Stripe return pages, LiveKit's egress template - so a cutover that changed any
# one of them breaks sign-in or payments without a single failing pod. The chart built the
# ${API_DOMAIN} callbacks from the app host until this check existed.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$root_dir/deploy/production/app.compose.yml"
chart_dir="${K3S_CHART_DIR:-$root_dir/deploy/k3s/chart}"
app_domain="app.parity.invalid"
api_domain="api.parity.invalid"

rendered="$(mktemp "${TMPDIR:-/tmp}/warptalk-url-parity.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

"$root_dir/scripts/helm-locked.sh" template warptalk "$chart_dir" \
  --namespace warptalk \
  --set-string "global.domain=$app_domain" \
  --set-string "global.apiDomain=$api_domain" >"$rendered"

python3 - "$compose_file" "$rendered" "$app_domain" "$api_domain" <<'PY'
import re
import sys

compose_path, rendered_path, app_domain, api_domain = sys.argv[1:5]

domain_pattern = re.compile(r"\$\{(APP_DOMAIN|API_DOMAIN)(?::[?-][^}]*)?\}")
compose_line = re.compile(r"^\s+([A-Za-z_][A-Za-z0-9_]*):\s+(\S*\$\{(?:APP|API)_DOMAIN[^}]*\}\S*)\s*$")

expected = {}
for line in open(compose_path, encoding="utf-8"):
    match = compose_line.match(line)
    if not match:
        continue
    key, value = match.groups()
    # Caddy's own site addresses are not application configuration.
    if key in ("APP_DOMAIN", "API_DOMAIN"):
        continue
    value = domain_pattern.sub(
        lambda m: app_domain if m.group(1) == "APP_DOMAIN" else api_domain, value
    ).strip("\"'")
    previous = expected.setdefault(key, value)
    if previous != value:
        sys.exit(f"compose sets {key} to two different URLs: {previous} / {value}")

if not expected:
    sys.exit("found no ${APP_DOMAIN}/${API_DOMAIN} URLs in compose; the parser is broken")

rendered = open(rendered_path, encoding="utf-8").read().splitlines()
found = {}
for index, line in enumerate(rendered):
    config = re.match(r"^\s+([A-Za-z_][A-Za-z0-9_]*):\s+\"?(.*?)\"?\s*$", line)
    if config and config.group(1) in expected:
        found.setdefault(config.group(1), set()).add(config.group(2))
    env = re.match(r"^\s+- name:\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
    if env and env.group(1) in expected and index + 1 < len(rendered):
        value = re.match(r"^\s+value:\s+\"?(.*?)\"?\s*$", rendered[index + 1])
        if value:
            found.setdefault(env.group(1), set()).add(value.group(1))

failures = []
for key, url in sorted(expected.items()):
    values = found.get(key)
    if not values:
        failures.append(f"{key}: compose sets {url}; the chart does not set it at all")
    elif values != {url}:
        failures.append(f"{key}: compose {url} != chart {sorted(values)}")

if failures:
    print("compose/k8s URL parity: FAIL", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    sys.exit(1)
print(f"compose/k8s URL parity: PASS ({len(expected)} domain-derived URLs identical)")
PY
