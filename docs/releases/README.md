# Release notes

One file per release tag, generated from what was actually promoted to `main`.

## Why generated and not written

A tag is a version number. Without this, answering "what is in v141 that was not in v140"
meant reading four repositories' git logs, so nobody knew what to test and the testing that
happened was whatever somebody remembered asking for.

These notes cannot drift from the release, because their boundary **is** the release: every
promotion leaves a merge commit on `main` reading
`Merge pull request #N from WarpTalk-CapstoneProject/development`, and the notes are the range
between the two most recent of those, in each repo.

## How to produce one

Immediately **after** the four promote PRs are merged — the newest promote merge is what the
script measures back from — and before or after dispatching, either order:

```sh
node scripts/release-notes.mjs --tag prod-20260821-example-v142 --write
```

It prints the notes and writes `docs/releases/<tag>.md`. Commit that to `development`.

The note describes the release that was just dispatched, and rides to `main` with the *next*
promotion. That is deliberate: it is documentation, not part of the deployed bundle, and
holding a release open to commit its own changelog would put a manual step inside the deploy.

## Where the boundary comes from, exactly

Each note ends with the commit it stopped at, per repo, as an HTML comment — invisible wherever
the markdown renders. The next note starts there.

That is not the same as "the previous promotion", and the difference bit on the very first run:
two promote PRs were merged before one dispatch, so the notes covered the second and silently
dropped everything the first carried. Nothing looked wrong. A recorded boundary is the release
before it, which is the thing actually being asked about.

To backfill, or for a note with no predecessor:

```sh
node scripts/release-notes.mjs --tag <tag> --from warptalk-web=<sha> --write
```

## What it cannot do

It reads commit subjects. A release whose commits are titled `fix: stuff` produces a note that
says `stuff`. The conventional-commit prefix decides the heading, so `feat:` and `fix:` are
what make a note readable — anything unrecognised lands under "Other" rather than being dropped.
