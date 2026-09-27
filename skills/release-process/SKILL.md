---
name: release-process
description: Guide for cutting a new release of the GenAI Factory repository. Use this skill when asked to create, prepare, or draft a new release.
---

# GenAI Factory Release Process

This skill guides maintainers through the process of cutting a new release for the GenAI Factory repository.

> **CRITICAL:** Release names and tags MUST ALWAYS be prefixed with `v` (e.g., `v2.0.0`, `v2.1.0`).

GenAI Factory has no `CHANGELOG.md` and no changelog tooling: releases are GitHub releases whose notes combine a short hand-written summary with GitHub's auto-generated commit list.

## Prerequisites

- **Permissions:** You must have write/release permissions on the repository.
- **GitHub CLI:** An authenticated `gh` (check with `gh auth status`).
- **Environment:** Python dependencies installed with `uv sync --all-groups`, plus `terraform` and `gcloud` if you intend to run the tests locally.

## 1. Preparation

Start from the `master` branch and ensure you are up to date:

```bash
git checkout master
git pull
```

Identify the **latest released version**:

```bash
LATEST_RELEASE=$(git tag --sort=-v:refname | head -n 1)
echo "Latest release is: $LATEST_RELEASE"
```

Confirm `master` is green before releasing — the nightly [Linting](../../.github/workflows/linting.yml), [Tests](../../.github/workflows/tests.yml), and [Integration Tests](../../.github/workflows/tests-integration.yml) workflows all gate the release:

```bash
gh run list --branch master --limit 10
```

If anything is red, fix it (or wait for the fix to merge) before proceeding.

## 2. Review the Changes Since the Last Release

Collect what went in, which also determines the bump type:

```bash
git log --oneline $LATEST_RELEASE..HEAD
gh pr list --state merged --base master --limit 50 \
  --json number,title,mergedAt,url \
  --jq '.[] | "\(.number)\t\(.title)"'
```

Choose the bump:

- **major** — factories restructured, variables or `data/projects` YAML interfaces changed in a backwards-incompatible way, or anything that forces users to change their `terraform.tfvars` or recreate state.
- **minor** — new factories, new sample applications, new features on existing stages.
- **patch** — fixes, dependency and security upgrades, documentation only.

Read the merged PR bodies for `**Breaking Changes**` sections: those are what the release notes must surface.

```bash
NEW_RELEASE="v2.1.0"   # set to the version you decided on
echo "New release is: $NEW_RELEASE"
```

## 3. Check the Cloud Foundation Fabric Compatibility Statement

Every factory pins the same Fabric tag. Verify the pin and make sure the compatibility statement in the [main README.md](../../README.md) matches it:

```bash
grep -rho "ref=v[0-9.]*" --include="*.tf" . | sort -u
grep -n "Cloud Foundation Fabric" README.md | head
```

If the statement is stale, update it in a normal PR (or a small commit on `master`) **before** cutting the release, so the tag points at accurate documentation. The pinned ref itself is bumped by the nightly integration workflow, which opens an `[GH Actions] Update Fabric to <tag>` PR; do not bump it by hand as part of the release.

## 4. Run the Checks Locally

```bash
uv run pre-commit run --all-files
uv run pytest -n4 tests
```

Both must pass on the exact commit you are about to tag.

## 5. Draft the Release Notes

Write the notes in the style of the previous releases (`gh release view $LATEST_RELEASE` to see one). The structure is:

```markdown
## What's Changed

<one or two sentences describing the theme of the release>

**New Features**
* ...

**Compatibility with Cloud Foundation Fabric**
* Compatible with Cloud Foundation Fabric <tag>.

**Fixes, security upgrades**
* ...
```

For a major release, add a `**Breaking Changes**` section at the top with the concrete upgrade steps, taken from the merged PR bodies.

> **CRITICAL:** Show the drafted notes to the user and wait for their approval before creating the release.

## 6. Create the GitHub Release

You can create the release either automatically via the GitHub CLI or manually via the GitHub UI.

### Option A: Automated via GitHub CLI (Recommended)

Write the approved notes to a file **using your file-writing tool** (not a heredoc or shell redirection: backticks in the notes would be evaluated by the shell), then create the release. `--generate-notes` appends GitHub's auto-generated commit and contributor list, including the "Full Changelog" link, after your hand-written notes.

```bash
gh release create "$NEW_RELEASE" \
  --target master \
  --title "$NEW_RELEASE" \
  --notes-file /tmp/release-notes.md \
  --generate-notes
```

`gh` creates the tag on `--target` for you, so there is no separate `git tag` step.

### Option B: Manual via GitHub UI

Go to the [GitHub Releases UI](https://github.com/GoogleCloudPlatform/genai-factory/releases/new) and configure the release:

1. **Tag:** Create a new tag matching the new version (e.g., `v2.1.0`), targeting `master`.
2. **Title:** Use the exact same version string as the tag.
3. **Release Notes:** Click the **"Generate release notes"** button, then paste your hand-written notes at the **top** of the generated content.

Click **Publish release**.

## 7. Verify

```bash
gh release view "$NEW_RELEASE"
git fetch --tags
```

Check that the tag points at the intended commit and that the notes render as expected.
