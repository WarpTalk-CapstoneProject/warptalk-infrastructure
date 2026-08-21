# Pin every service in the running Compose to the exact digest this release built.
#
# WHAT GOES WRONG WITHOUT IT
#   app.compose.yml writes `${IMAGE_REGISTRY}/name:${IMAGE_TAG}`, and those variables come from a
#   .env on the host that no release rewrites — on production they still hold values from July.
#   The override is what makes that harmless: every service is replaced by ref@sha256 before
#   anything is pulled. A service the override MISSES falls through to the stale pair and pulls a
#   tag that no longer exists, which is a 403 that stops the whole deploy after every other image
#   has already been fetched.
#
#   That is exactly what v144 did. `translation-backfill-worker` was added to the Compose file and
#   not to the matrix, and it resolved to a registry path and tag from 2026-07-30.
#
# ONE IMAGE, SEVERAL SERVICES
#   `alsoServices` exists because two containers can legitimately run the same image with
#   different commands — the live translation worker and the post-meeting backfill worker are the
#   same code reading different streams. Listing the second service here is cheaper and more
#   honest than building, scanning and signing an identical image twice under another name.
#
#   Services are only written when the base Compose actually has them, so a matrix entry naming a
#   service this role does not run stays a no-op rather than inventing one.
{
  services: (
    reduce .images[] as $image ({};
      reduce ([$image.service] + ($image.alsoServices // []))[] as $service (.;
        if ($base[0].services | has($service))
        then .[$service] = {
          image: ($image.ref + "@" + $image.digest)
        }
        else .
        end
      )
    )
  )
}
