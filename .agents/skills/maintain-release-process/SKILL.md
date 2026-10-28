---
name: maintain-release-process
description: Use when asked to prepare, draft, tag, or publish a new GitHub release of the GoogleCloudPlatform/genai-factory repository.
---

# GenAI Factory Release Process

## Overview

Guides repository maintainers through verifying `master`, determining the semantic version bump (`vX.Y.Z`), checking Cloud Foundation Fabric compatibility, drafting release notes for user approval, and publishing a GitHub release via `gh release create`.

## When to Use

- Preparing, drafting, or cutting a new `vX.Y.Z` release of `GoogleCloudPlatform/genai-factory`.
- Checking changes merged since the latest release tag or verifying the Cloud Foundation Fabric version pin in [`README.md`](../../../README.md).

## Quick Reference — Version Bump Rules

| Bump | Criteria | Tag Format |
| :--- | :--- | :--- |
| **Major (`vX.0.0`)** | Breaking refactoring requiring user deployment migration or resource recreation | Must start with `v` |
| **Minor (`vX.Y.0`)** | New Cloud Foundation Fabric tag across factories, new factories, new sample apps, or new stage features | Must start with `v` |
| **Patch (`vX.Y.Z`)** | Bug fixes, dependency/security updates, or documentation-only changes | Must start with `v` |

## Implementation Steps

### 1. Sync `master` & Inspect Changes Since Latest Release

```shell
git checkout master && git pull
LATEST_RELEASE=$(git tag --sort=-v:refname | head -n 1)
echo "Latest release: $LATEST_RELEASE"

# Confirm CI workflows (Linting, Tests, Integration Tests) are green on master
gh run list --branch master --limit 10

# Inspect commits and merged PRs since $LATEST_RELEASE
git log --oneline "$LATEST_RELEASE"..HEAD
gh pr list --state merged --base master --limit 50 \
  --json number,title,mergedAt,url \
  --jq '.[] | "\(.number)\t\(.title)"'
```

### 2. Verify Cloud Foundation Fabric Pin & Local Checks

Ensure all `*.tf` files pin the same Fabric tag and match [`README.md`](../../../README.md), then run pre-commit and pytest:

```shell
grep -rho "ref=v[0-9.]*" --include="*.tf" . | sort -u
grep -n "Cloud Foundation Fabric" README.md | head
uv run pre-commit run --all-files
uv run pytest -n4 tests
```

### 3. Draft Release Notes & Wait for User Approval

Compare with `gh release view "$LATEST_RELEASE"` and draft notes in this format. **STOP and get explicit user approval before creating the release:**

```markdown
## What's Changed

<1-2 sentences describing the theme of the release>

**New Factories**
* ...

**New Features**
* ...

**Compatibility with Cloud Foundation Fabric**
* Compatible with Cloud Foundation Fabric <tag>.

**Fixes, security upgrades**
* ...
```

### 4. Publish & Verify the Release

Write the approved notes to `/tmp/release-notes.md` using the native file-writing tool (never shell heredocs), then run:

```shell
NEW_RELEASE="v2.1.0"
gh release create "$NEW_RELEASE" \
  --target master \
  --title "$NEW_RELEASE" \
  --notes-file /tmp/release-notes.md \
  --generate-notes
rm -f /tmp/release-notes.md
gh release view "$NEW_RELEASE"
git fetch --tags
```

## Common Mistakes

| Mistake | Prevention |
| :--- | :--- |
| Omitting the `v` prefix on the tag (`2.1.0` instead of `v2.1.0`) | Always prefix `NEW_RELEASE` with `v` |
| Writing release notes via `cat << EOF` shell redirection | Backticks in Markdown get evaluated by the shell; always use `write_file` to `/tmp/release-notes.md` |
| Bumping the Fabric tag manually during release | The nightly workflow opens `[GH Actions] Update Fabric to <tag>` PRs; only verify [`README.md`](../../../README.md) matches the pinned tag |
