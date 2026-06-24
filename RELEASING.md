# Releasing a new version

This project ships as **source you deploy** (no installable package), and uses
**manual tagged releases**. A "release" is a named, frozen snapshot of the repo
(for example `v1.0.0`) that people can install or roll back to.

This guide is written so you can follow it the first time without prior release
experience. You only need the [GitHub CLI (`gh`)](https://cli.github.com) and
`git`. Everything here runs from the project root.

> First time publishing this repository to GitHub? Create a private or public repo,
> push `main`, and enable Actions. See GitHub's
> [creating a new repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)
> guide. Come back here when you want to cut a versioned release.

## Versioning, in plain terms

This project follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

| Bump      | When                                                           | Example         |
| --------- | -------------------------------------------------------------- | --------------- |
| **PATCH** | Bug fixes only, no behavior change for existing configs        | `1.0.0 → 1.0.1` |
| **MINOR** | New backward-compatible feature (new Check Method, new field)  | `1.0.0 → 1.1.0` |
| **MAJOR** | A change that breaks existing Check Sets/Rules or the Apex API | `1.x → 2.0.0`   |

The current version lives in [`package.json`](package.json) (`"version"`).

## Step 1: Make sure `main` is green

Releases are cut from `main`. Confirm everything passes locally first:

```bash
git checkout main
git pull
npm ci
npm run prettier:verify
npm run lint
npm test                    # 61 Jest tests
npm run test:unit:coverage  # coverage thresholds enforced
```

If you changed Apex since the last release, also run a validation deploy with
tests against a clean scratch org (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Step 2: Decide the new version number

Use the table above. For the very first release this is **`v1.0.0`**. Below,
replace `X.Y.Z` with your chosen number (no leading `v` for `package.json`).

## Step 3: Update the version and changelog

1. Bump the version in `package.json`:

   ```bash
   npm version X.Y.Z --no-git-tag-version
   ```

   (`--no-git-tag-version` just edits the file; you will tag manually in Step 5
   so the changelog commit and the tag stay together.)

2. In [`CHANGELOG.md`](CHANGELOG.md), rename the **`## Unreleased`** heading to
   **`## vX.Y.Z: YYYY-MM-DD`** and add a fresh empty `## Unreleased` section
   above it for future work.

## Step 4: Commit the release prep

```bash
git add package.json CHANGELOG.md
git commit -m "Release vX.Y.Z"
git push
```

## Step 5: Tag and publish the GitHub Release

The `gh` CLI creates the tag and the release page in one command, pulling the
notes straight from your changelog section:

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "See CHANGELOG.md for details." \
  --target main
```

Or, to write richer notes interactively, omit `--notes` and `gh` opens an editor.

> Prefer the website? Go to **Releases → Draft a new release → Choose a tag →**
> type `vX.Y.Z` → **Create new tag on publish**, paste your changelog notes, and
> click **Publish release**.

## Step 6: Verify the installable artifacts

1. On the repo's **Releases** page, confirm `vX.Y.Z` is listed and the notes look right.
2. Test the tagged Deploy URL in a sandbox by appending the tag as `ref`:
   ```
   https://githubsfdeploy.herokuapp.com/?owner=gkolan&repo=recordHealthCheck&ref=vX.Y.Z
   ```
   The README's default button installs `main`; this URL pins the exact release.

## Step 7: Announce

Point people at the release page:
`https://github.com/gkolan/recordHealthCheck/releases/tag/vX.Y.Z`.
Non-technical teammates keep using the one-click Deploy button in the
[README](README.md), which always installs the latest `main`.

## Rolling back

A release is just a tag, so rollback is "install the previous tag":

```
https://githubsfdeploy.herokuapp.com/?owner=gkolan&repo=recordHealthCheck&ref=vPREVIOUS
```

Because the component is **advisory** (it never blocks saves or writes records),
deploying an older version is low-risk: it changes how checks are evaluated and
displayed, not your data.
