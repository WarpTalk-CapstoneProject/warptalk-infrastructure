# Google Workspace plugin OAuth on production

Connecting the Google Workspace plugin fails at the callback, not at consent:

```
GET https://api.warptalk.io.vn/api/v1/assistant/plugins/google_workspace/oauth/callback
→ {"code":"INTERNAL_SERVER_ERROR", ...}
```

Consent rendering correctly proves only that `GOOGLE_WORKSPACE_CLIENT_ID` reached the
container. The client id is all the authorize leg needs; the secret is spent one leg
later, on the server-to-server token exchange the browser never sees. So a host that
has the id and not the secret looks entirely healthy right up to the redirect back.

`GoogleWorkspaceOAuthClient.ExchangeCodeAsync` has exactly two statements that can
throw: `RequireConfigured(_options.ClientSecret, ...)` when the secret is empty, and
`response.EnsureSuccessStatusCode()` when Google refuses the exchange. Everything below
is about telling those two apart, because the remedies are unrelated — one is a missing
line in `/etc/warptalk/.env.production`, the other is a Google Cloud Console entry.

All commands run on the **App** host, as an operator with `sudo`. Define the container
once, the way `deploy-release.sh` does, so nothing below has to guess at a container
name:

```sh
cd /opt/warptalk/current/deploy/production
compose() {
  sudo docker compose \
    --env-file /etc/warptalk/.env.production \
    -f /opt/warptalk/current/deploy/production/app.compose.yml "$@"
}
ASSISTANT="$(compose ps -q assistant-service)"
test -n "$ASSISTANT" && echo "assistant-service: $ASSISTANT"
```

## 1. Which keys does the environment file hold

Never `cat` this file and never `grep` a value out of it: it is the one place on the
platform that holds every credential at once, and a terminal scrollback is not a secret
store. Print key names and whether each has a non-empty value — nothing else.

```sh
sudo awk -F= '/^GOOGLE_WORKSPACE_/ {
  v = substr($0, index($0, "=") + 1)
  printf "%s = %s (%d chars)\n", $1, (length(v) ? "set" : "EMPTY"), length(v)
}' /etc/warptalk/.env.production
```

Expect two lines, both `set`:

```
GOOGLE_WORKSPACE_CLIENT_ID = set (72 chars)
GOOGLE_WORKSPACE_CLIENT_SECRET = set (35 chars)
```

A key that is missing altogether prints no line at all, so count the lines: one line, or
a line reading `EMPTY`, is the diagnosis. Confirm the container agrees — the file on disk
and the process environment diverge whenever the file was edited without recreating the
container:

```sh
sudo docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$ASSISTANT" \
  | awk -F= '/^Plugins__GoogleWorkspace__OAuth__Client(Id|Secret)=/ {
      v = substr($0, index($0, "=") + 1)
      printf "%s = %d chars\n", $1, length(v)
    }'
```

Read the character counts, not the values. `ClientSecret` at zero is the same finding
from the other side of the boundary.

While you are here, record which release is actually running — it decides whether the
durable fix in step 4 is already deployed or still pending:

```sh
readlink -f /opt/warptalk/current
sudo jq -r '.images[] | select(.service=="assistant-service") | .ref' \
  /opt/warptalk/current/deploy/production/release-manifest.json
```

## 2. Read the assistant-service logs for one correlation id

The error body carries the id. Search the whole retained buffer for it rather than
tailing, because by the time anyone reads a runbook the request is minutes old:

```sh
sudo docker logs "$ASSISTANT" 2>&1 | grep -F "<correlation-id>"
```

For the surrounding lines of the same request — the exception type is on a later line
than the id:

```sh
sudo docker logs "$ASSISTANT" 2>&1 | grep -F -A 40 "<correlation-id>"
```

If nothing matches, the buffer has rotated (`json-file`, capped per service). Reproduce
the connect attempt, then read the tail with timestamps:

```sh
sudo docker logs --timestamps --since 10m "$ASSISTANT" 2>&1 \
  | grep -iE 'GoogleWorkspace|ExchangeCode|oauth/callback'
```

Read the exception, and stop guessing at this line:

- `InvalidOperationException` naming `ClientSecret` — the secret is missing. Step 3.
- `HttpRequestException` from `EnsureSuccessStatusCode`, usually `400 Bad Request` — the
  secret is present and Google rejected the exchange. Almost always
  `redirect_uri_mismatch` or `invalid_client`. Step 5, not step 3.

## 3. Add the secret and recreate the container

A restart is not enough. `docker restart` re-runs the process inside the *existing*
container, and a container's environment is fixed at creation — the new line would sit
in the file, unread, while the callback kept returning 500 and the deploy looked done.
Compose has to build a new container from the changed `--env-file`.

Get the secret from the Google Cloud Console credential (or from the team's password
manager) and write it without it ever appearing in the shell history, on a command line,
or in the process table. `stty -echo` keeps it off the screen; the pipe into `tee` keeps
it out of `ps`:

```sh
sudo install -m 0600 /dev/null /tmp/gw.env
stty -echo; printf 'Google Workspace client secret: '; IFS= read -r GW_SECRET; stty echo; echo
printf 'GOOGLE_WORKSPACE_CLIENT_SECRET=%s\n' "$GW_SECRET" | sudo tee /tmp/gw.env >/dev/null
unset GW_SECRET
```

Never paste the value into a command such as `echo` or `sed` — a secret on a command
line is a secret in the process table of a production host, readable by every user on it.

Apply it with the same script a release uses, so the file keeps its shape, its `0600`
mode and its one-line-per-key invariant:

```sh
sudo env PRODUCTION_ENV_FILE=/etc/warptalk/.env.production \
  RUNTIME_SECRETS_FILE=/tmp/gw.env \
  /opt/warptalk/current/scripts/apply-runtime-secrets.sh
sudo shred -u /tmp/gw.env
```

It prints `changed` or `unchanged`, and nothing else — by design, since it runs with the
secret in hand. `unchanged` means the value you supplied is the value already there, and
the fault is elsewhere; go back to step 2 and re-read the exception.

Validate before recreating anything. The validator requires every key in
`deploy/production/.env.example` to be present, so on a release that carries the
`GOOGLE_WORKSPACE_*` template lines this is also the check that the key landed:

```sh
sudo env PRODUCTION_ENV_FILE=/etc/warptalk/.env.production \
  /opt/warptalk/current/scripts/validate-production-env.sh && echo OK
```

Then recreate just the one service, using the `compose` function defined at the top:

```sh
compose up -d --force-recreate --no-deps assistant-service
```

`--no-deps` keeps `migrator` and the rest of the stack untouched; `--force-recreate`
is what makes the container read the file again. Confirm the new container is a new
container, and that it is healthy:

```sh
compose ps assistant-service
ASSISTANT="$(compose ps -q assistant-service)"
```

The `STATUS` column must read `Up (healthy)` with an uptime of seconds, not days. An
uptime in days means the recreate did not happen and nothing has changed.

Re-run step 1's inspect. `ClientSecret` should now report a non-zero character count.
Then connect the plugin from the app and watch the callback return a redirect rather
than a 500.

## 4. The durable fix: cut a release from `development`

Everything above is a hand edit on one host, and a hand edit survives exactly until the
next release recreates the container from a file nobody re-applied. The pipeline that
makes it stick is on `development`:

- `deploy/production/app.compose.yml` reads `${GOOGLE_WORKSPACE_CLIENT_ID:?}` and
  `${GOOGLE_WORKSPACE_CLIENT_SECRET:?}`. `:?` rather than `:-` — an unset key stops the
  deploy and names the key, instead of starting a service that dies at the callback.
- `deploy/production/.env.example` declares both keys, which is what makes
  `validate-production-env.sh` demand them on all three hosts.
- `.github/workflows/release.yml` calls `add_runtime_secret` for both, pushing
  `vars.GOOGLE_WORKSPACE_CLIENT_ID` and `secrets.GOOGLE_WORKSPACE_CLIENT_SECRET` to
  every host before the containers are recreated.

So the fix is a promotion, not a patch: merge `development` to `main` and dispatch a
release. Two preconditions, both in GitHub, both silent when wrong — `add_runtime_secret`
drops an empty value rather than blanking the key, which is correct behaviour and also
means a missing GitHub secret produces no error anywhere:

1. Repository **variable** `GOOGLE_WORKSPACE_CLIENT_ID` is set.
2. Repository **secret** `GOOGLE_WORKSPACE_CLIENT_SECRET` is set.

If either is missing the release will push nothing for it, and — because `development`
uses `:?` — the deploy will stop with the key's name in the log. That is the intended
outcome, not a regression.

## 5. The redirect URI has to match exactly

Google compares the `redirect_uri` string byte for byte, on both the authorize leg and
the token exchange, against what is registered on the OAuth client. A mismatch fails the
exchange, which surfaces here as the same 500 — with an `HttpRequestException` rather
than a missing-secret exception.

For the release production runs today, the OAuth client in Google Cloud Console must
have this exact authorized redirect URI:

```
https://api.warptalk.io.vn/api/v1/assistant/plugins/google_workspace/oauth/callback
```

No trailing slash, `https`, the API domain and not the app domain.

**Before the release in step 4 lands**, add the second URI as well. WT-646 moves the
callback to one provider-scoped route shared by `google_drive`, `google_calendar` and
`google_meet`, with the plugin key travelling in the protected state:

```
https://api.warptalk.io.vn/api/v1/assistant/plugins/oauth/google/callback
```

Both are registered at once, and both stay registered for the length of the rollout: a
consent granted seconds before the deploy comes back to the old route, and
`Plugins__GoogleWorkspace__OAuth__LegacyRedirectUri` exists to accept it. An
authorization code lives minutes, so once a deploy has settled the legacy URI, the
legacy route and this console entry are retired together.

## What this runbook does not cover

The Data Protection key ring. Every plugin secret and user token in `assistant.plugins`
and `plugin_connections` is encrypted with the ring at
`DataProtection__KeyRingPath: /var/lib/warptalk/keys`, backed by the
`assistant-data-protection-keys` volume in `app.compose.yml`. Recreating the container
as in step 3 keeps the volume and therefore keeps the ring. Removing that volume orphans
every token ever written, silently — `Program.cs` accepts an absent path and holds the
keys in memory, so nothing logs an error and connections simply stop decrypting. If the
volume has been lost, no amount of environment fixing helps: every user reconnects.
