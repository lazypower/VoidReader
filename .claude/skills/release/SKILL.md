---
name: release
description: Prep and publish a VoidReader release — version bump, CHANGELOG, house-style notes, tag, and edit the release body after CI publishes
disable-model-invocation: true
user-invocable: true
arguments: [version]
---

# Release VoidReader v$version

The full pipeline for **$version**. A human pushes a `v$version` tag; GitHub's `release.yml` does the build / sign / notarize / GitHub-release / Homebrew-cask work automatically. Everything before the tag is prep; the nice release body is edited in *after* CI publishes.

## How it works (so the steps make sense)

`.github/workflows/release.yml` triggers on any `v*` tag push and, on a macOS runner:

1. Asserts `project.yml`'s version (both generated `Info.plist`s) `== the tag`, or **fails** before building.
2. Builds + signs + notarizes the DMG (`make dmg-signed`; Apple creds are CI secrets).
3. Asserts the **built** `.app`'s `CFBundleShortVersionString == the tag`, or refuses to publish.
4. Creates the GitHub Release with the DMG attached and **auto-generated** notes (`--generate-notes`).
5. Updates the Homebrew cask in `lazypower/homebrew-tap` (version + SHA256).

Two consequences: the **tag is the trigger**, the version gate is strict (drift fails the job), and the good release body is **not** written by CI — you replace the auto notes in Step 7.

**Remotes:** `github` is where releases live (the workflow is GitHub-only); `origin` (gitea) only runs the test/perf CI. The release tag must reach **`github`** to fire the workflow.

## Semver — no features = patch

- **Patch** (`x.y.Z`): fixes, hardening, packaging, cleanup — no new user-facing feature. However chonky. (1.2.1 "Trust Issues" was ~30 fixes and is still a patch.)
- **Minor** (`x.Y.0`): a genuine new capability shipped.

Don't inflate a fixes release to a minor because it's big.

## Step 1 — Pre-flight

- On `main`, clean tree, the release work merged.
- CI green on **both** gitea and github for `HEAD`.
- Review what's shipping: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`

## Step 2 — Version bump

Set `CFBundleShortVersionString` to `$version` in **both** targets in `project.yml`:
- `VoidReader` (~line 54)
- `VoidReaderQuickLook` (~line 100)

Both must match the tag or the release job fails the version gate (pre-build *and* post-build). `make project` regenerates the `Info.plist`s if you want to verify locally with `PlistBuddy`.

## Step 3 — CHANGELOG

Add a top entry to `CHANGELOG.md` (just below the intro `---`), newest-first, in house format:

```
## [$version] - YYYY-MM-DD

### The "<Name>" Release

<one-line tagline>

#### Fixed
- ...
#### Added / Performance / Housekeeping   (as applicable)
- ...
#### The Numbers   (optional, for big releases)
- ...
```

## Step 4 — (optional) Perf data — only if the lab actually ran

**Reality check first.** `.gitea/workflows/test-perf-lab.yml` is **path-gated** — it only runs when `scripts/perf/**`, `PERFORMANCE.md`, or its fixtures change. A normal fixes/hardening release touches none of those, so there's usually **no fresh perf run on the release commit** (0 test-perf-lab runs in the last 50 pushes, as of 1.2.1). Don't document numbers that don't exist.

- **Fixes/hardening release → skip the perf table.** That's most releases (1.2.1 had none). Move on to Step 5.
- **Perf-relevant release, or you specifically want fresh numbers →** the lab has `workflow_dispatch`, so trigger it *first*: run **Performance Lab → "Run workflow"** in the Gitea Actions UI (or dispatch via API), wait for it to complete, then pull:

```bash
# most recent COMPLETED perf-lab run (widen the window; it's rare)
tea api --login gitea.wabash.place "repos/chuck/VoidReader/actions/runs?limit=50" | python3 -c "
import json,sys
for r in json.load(sys.stdin).get('workflow_runs',[]):
    if r.get('path','').split('@')[0]=='test-perf-lab.yml' and r['status']=='completed':
        print(r['id']); break"
# jobs, then the '=== window ===' summaries
tea api --login gitea.wabash.place repos/chuck/VoidReader/actions/runs/<RUN_ID>/jobs
tea api --login gitea.wabash.place repos/chuck/VoidReader/actions/jobs/<JOB_ID>/logs | grep -A20 '=== window ==='
```

Scenarios: `open-large`, `scroll-to-bottom`, `search-navigate`, `edit-toggle`. Summarize samples, idle-vs-work ratio, top app frames for the notes table.

## Step 5 — Release notes (the GitHub release body)

House voice — self-aware, cheeky, technically grounded:
- Title: `VoidReader X.Y.Z — "Subtitle"`
- Bold **"The one where…"** tagline
- Sections framed by *user impact* (with jokes), not a commit list
- Optional perf table (Step 4), a **The Numbers** block, install instructions, changelog link
- Tone reference: 1.2.1 "Trust Issues", 1.2.0 "Reading the Fine Print", 1.1.0 "We Measure Twice Now", 1.0.4 "Math Is Hard"

Save it to a file (e.g. `scratchpad/RELEASE_NOTES_$version.md`) for Step 7.

## Step 6 — Commit, then tag (SEPARATELY)

```bash
git add project.yml CHANGELOG.md
git commit -m "release: v$version"

git push github main            # 1) commits first
git tag v$version
git push github v$version        # 2) tag SEPARATELY — THIS fires release.yml
```

Push commits and the tag as **separate** pushes (a combined push can miss the tag trigger). Then keep gitea in sync: `git push origin main` (and `git push origin v$version` to mirror the tag if you like — gitea won't publish, it just keeps history aligned).

## Step 7 — Replace the auto notes with the house body

CI created the release with `--generate-notes`. Swap in the real body:

```bash
gh release edit v$version --repo lazypower/VoidReader --notes-file scratchpad/RELEASE_NOTES_$version.md
```

Verify:
```bash
gh release view v$version --repo lazypower/VoidReader   # body + DMG asset attached
# confirm the cask bumped: check lazypower/homebrew-tap Casks/voidreader.rb
```

## Gotchas & rollback

- **Version gate failed?** Bump both `project.yml` targets, then re-tag:
  `git push github :v$version && git tag -d v$version` → fix → re-tag → push tag again.
- **Don't hand-build the release DMG.** CI signs + notarizes with Apple creds; a local `make dmg-signed` needs your Developer ID + notarization credentials and won't match CI's artifact.
- The release body is the **only** manual step after tagging — everything else (build, sign, notarize, GitHub release, Homebrew) is automatic once the tag lands on `github`.
