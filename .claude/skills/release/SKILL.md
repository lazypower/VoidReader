---
name: release
description: Prep and publish a VoidReader release — version bump, perf data from Gitea CI, release notes, tag, push
disable-model-invocation: true
user-invocable: true
arguments: [version]
---

# Release VoidReader v$version

Run the full release pipeline for version **$version**. GitHub CI will create the tag + release artifact (DMG) automatically when the tag is pushed — we edit the release afterward to add notes.

## Step 1: Pre-flight

- Confirm `main` is clean (`git status`)
- Confirm all CI is green on Gitea for the current HEAD
- List commits since the last tag: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`

## Step 2: Version bump

Update `CFBundleShortVersionString` in **both** targets in `project.yml`:
- `VoidReader` target (around line 54)
- `VoidReaderQuickLook` target (around line 100)

Both must read `"$version"`. This is critical — we shipped 1.0.1 with "1.0.0" in About once. Don't repeat that.

## Step 3: Pull performance data from Gitea

Fetch the latest `test-perf-lab.yml` run results from Gitea CI:

```bash
# Find the most recent completed perf lab run
tea api repos/chuck/VoidReader/actions/runs 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
runs = data.get('workflow_runs', [])
for r in runs:
    path = r.get('path','').split('@')[0]
    if path == 'test-perf-lab.yml' and r['status'] == 'completed':
        print(r['id'])
        break
"
```

Then pull the job logs for each scenario and extract the `=== window ===` summary lines:

```bash
# Get jobs for the perf run
tea api repos/chuck/VoidReader/actions/runs/<RUN_ID>/jobs

# For each scenario job, extract the profile summary
tea api repos/chuck/VoidReader/actions/jobs/<JOB_ID>/logs | grep -A 20 "=== window ==="
```

Scenarios to collect:
- **open-large** — document open time, first paint
- **scroll-to-bottom** — sustained scroll, frame drops
- **search-navigate** — find-bar responsiveness
- **edit-toggle** — reader/editor switch latency

Summarize key numbers for the release notes (total samples, idle vs work ratio, top app frames).

## Step 4: Draft release notes

Write release notes in VoidReader's established voice:
- Self-aware, cheeky, technically grounded
- Title format: `VoidReader X.Y.Z — "Subtitle Here"`
- Subtitle is a quip that captures the release theme
- Structure: tagline → feature sections → perf data table → install instructions → changelog link → co-author quip
- Include perf lab numbers in a table or inline
- End with install instructions (brew + DMG)
- Co-author line references the Claude model used

Reference prior releases for tone:
- v1.1.0: "We Measure Twice Now"
- v1.0.4: "Math Is Hard"

**Do NOT publish yet.** Draft the notes and show them to the user for approval.

## Step 5: Commit, tag, push

Once the user approves the notes:

```bash
git add project.yml
git commit -m "bump: version $version"
git tag -a "v$version" -m "Release v$version"
git push github main && git push github "v$version"
git push gitea main && git push gitea "v$version"
```

Push to **both** remotes (github + gitea).

## Step 6: Publish notes

Wait for GitHub Actions to create the release (triggered by the tag push), then edit it with the approved notes:

```bash
gh release edit "v$version" --repo lazypower/VoidReader --notes "$(cat <<'EOF'
<release notes here>
EOF
)"
```

Confirm the release is live and the DMG artifact is attached before reporting done.

## Reminders

- Version in project.yml must match the git tag
- Push to both github and gitea remotes
- GitHub CI publishes the release — we just edit the notes onto it
- Never skip the perf data — we promised numbers with every release starting v1.2.0
