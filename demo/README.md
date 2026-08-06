# Demo script and its contract

`DEMO-FLOWS.md` is the script the team follows on stage at the capstone defence.
A wrong line is a moment where someone promises the panel something the product
does not do — or fails to demo something it does.

| File | What it is |
|---|---|
| `DEMO-FLOWS.md` | The script. Prose, for humans. Read it on stage. |
| `DEMO-FLOWS.contract.json` | The claims in it a machine can verify. |
| `../scripts/check-demo-flows-contract.mjs` | Runs those checks against `warptalk-web` and `warptalk-backend`. |
| `../scripts/test-demo-flows-contract.sh` | Proves the checker still fires. |

Run it locally — the sibling repos are read from `../warptalk-web` and
`../warptalk-backend` unless you override them:

```bash
./scripts/check-demo-flows-contract.mjs
WARPTALK_WEB_DIR=/path/to/web ./scripts/check-demo-flows-contract.mjs
```

It runs in CI on any PR touching this directory, and every Monday — because a
change in `warptalk-backend` or `warptalk-web` cannot trigger anything in this
repository, so the schedule is the only thing that catches drift coming from
the other side.

## The check failed. Now what?

The failure names the document line, what the document claims, and what the code
actually says. Read those three lines before doing anything else, then:

**Did you mean to change the behaviour?**

- **Yes** — the document is now wrong. Fix the sentence it points at. This is
  the normal case and it is the whole point: change the product, update the
  script.
- **No** — you have found a regression. The document is the spec here; fix the
  code.

**Two failure kinds that are not really about the document:**

- *"contract expects this text … it is not there any more"* — someone reworded
  the document. Re-read the line, decide whether the claim still holds, then
  update that entry's `anchor` (or delete the entry if the claim is gone).
  Never point an anchor at text you have not re-read; a contract describing a
  deleted line is worse than no contract.
- *"could not find … in any of"* — the code was refactored and the list moved.
  This is not a document error. Find where it lives now, add it to that entry's
  `sources`, and re-verify the claim by hand.

**A negative claim failed** — "the document says nothing calls this, something
does now". Someone built the feature. Do not just delete the claim: the document
probably tells the team to apologise for a missing feature they now have. Check
what the section says and rewrite it to sell the feature instead.

## Adding a claim

Add an entry with an `anchor` — exact text from the document — plus the check.
If the document names a route or endpoint you do not check, the checker will say
so; either add a claim or record it under `humanVerifyOnly` with the reason.

Prefer checks that cannot cry wolf. A zero-importer symbol count is solid; a
regex over a component's JSX is not, and a check that false-positives gets
switched off within a week. If a claim can only be checked fragilely, leave it
out and record it in `notCheckable` instead — an honest list of what is
unverified is what makes the rest of the document get read carefully.

The categories under `notCheckable` in the contract are the standing answer to
"what still needs a human": on-screen wording, runtime behaviour, permission
outcomes, empty-state/cache conditions, the Settings field inventory, and all
of the stage advice and preparation checklist.
