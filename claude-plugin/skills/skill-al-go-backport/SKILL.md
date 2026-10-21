---
name: skill-al-go-backport
description: Build a signed backport of a DSC AL-Go AppSource app (dyna-*) for an older Business Central major — a long-lived release/bcN branch cut from the release tag, the minimal app.json and .AL-Go/settings.json changes (application/platform/runtime, artifact, skipUpgrade), dependency probing on the backport branch, CICD dispatch on that ref, verifying the signed .app, and a pre-release GitHub release that PublishToAppSource never picks. Use whenever a customer still on an older BC version (e.g. BC 27 while main targets BC 28) needs a released AppSource product, the user says backport, "versione per BC 27", release/bc27, or an AppSourceCop baseline error (AL1153 runtime reference version, AS0091) appears on an older-major build.
---

# AL-Go backport of an AppSource app to an older BC major

A customer on BC `N` needs a product whose `main` already targets BC `N+1`. The backport is
**the same code as an already-released, already-validated version**, recompiled against BC `N`
and signed by the same CI. Nothing on `main` or in `.github/` changes.

Read `skill-al-go-workflows` §1–2 first if you do not know the repo's branch model. This skill
applies to the `al-appsource` flavour (`.github/AL-Go-Settings.json` `type: "AppSource App"`);
a PTE has no signing or AppSource baseline, so most of it does not apply.

## 🔒 Human gate — before touching anything

Present this to the user and wait for an explicit yes:

- which apps, from which release tag, for which BC major (`N`), in dependency order;
- that the backport sets `"skipUpgrade": true`. Claude Code's auto-mode classifier rightly flags
  it as a CI bypass. It is safe **here** because the code is the released version that already
  passed the AppSourceCop baseline on BC `N+1`; the baseline cannot be loaded by the BC `N`
  compiler (see Pitfalls). Never set it on `main` or on a branch carrying new code;
- that the build number will be higher than the BC `N+1` build of the same `major.minor` (see
  Pitfalls), so moving that customer to BC `N+1` later needs the next minor.

## Procedure

Use `release/bc<N>` and `<version>-bc<N>` throughout, e.g. `release/bc27`, `28.2.0-bc27`.

### 1. Branch from the release tag

```bash
git fetch --tags
git switch -c release/bc27 28.2.0      # the tag of the released version, not main
```

The branch is long-lived: later backport builds of the same line go on it. Template Sync opens
its PRs against `main` only, so it never touches `release/*`.

### 2. Commit only these changes

| File | Change |
|---|---|
| `app/app.json`, `app-performance/app.json` (and `app-test/app.json` if it sets them) | `"application": "27.0.0.0"`, `"platform": "27.0.0.0"` where present, `"runtime": "16.0"` (the runtime of BC `N`) |
| `.AL-Go/settings.json` | `"artifact": "//27/it/latest"` — compile against real BC `N` symbols; `"skipUpgrade": true` |
| `.AL-Go/settings.json` of a **dependent** repo | in `appDependencyProbingPaths`, the backported dependency's entry gets `"branch": "release/bc27"` instead of `main` |

Do not change the code, `version`, dependencies' `version`, `.github/` or any workflow. One
commit: `chore(backport): build 28.2.0 for BC 27`.

### 3. Build in dependency order

```bash
git push -u origin release/bc27
gh workflow run CICD.yaml --ref release/bc27
gh run list --workflow CICD.yaml --branch release/bc27 --limit 1
gh run watch <run-id> --exit-status
```

Dependencies first (Dyna HR before Expense Notes): a dependent repo's build pulls the
dependency's latest successful build **from the branch named in its probing path**, so that
build must exist before you dispatch the dependent one. `CustomJobSignLocal` signs on any ref;
Deliver to AppSource stays gated to `main`, so nothing reaches AppSource.

A failing build: `gh run view <run-id> --log-failed`, then Pitfalls below before touching code.

### 4. Verify the `.app`

```bash
gh api repos/{owner}/{repo}/actions/runs/<run-id>/artifacts -q '.artifacts[].name'   # the *-Apps-* one
gh run download <run-id> --name "<the -Apps- artifact>" --dir ./backport
```

On each `.app`:

- Authenticode signature is valid (`Get-AuthenticodeSignature <file>.app` → `Valid`);
- `NavxManifest.xml` inside it (the `.app` is a zip after the NAVX header — extract with the AL
  CLI or 7-Zip) has `Application` = `27.0.0.0`, `Platform` = `27.0.0.0` where set,
  `Runtime` = `16.0`, and each dependency's minimum version is one that exists on BC 27.

### 5. Release it without making it "latest"

```bash
git tag 28.2.0-bc27 <headSha of the run>       # gh run view <run-id> --json headSha
git push origin 28.2.0-bc27
Compress-Archive ./backport/*.app ./dyna-hr-base-28.2.0-bc27.zip
gh release create 28.2.0-bc27 ./dyna-hr-base-28.2.0-bc27.zip `
  --prerelease --latest=false `
  --title "28.2.0 for BC 27" --notes "Backport of 28.2.0 for Business Central 27. Same code as 28.2.0."
```

- `--prerelease --latest=false`: `PublishToAppSource` with `appVersion=current` and
  `Publish To Environment` read the latest release, so neither can pick the backport.
- Semver: `28.2.0-bc27` sorts **below** `28.2.0`, which is what you want.
- Attach the build **zipped**: GitHub rejects `.app` assets with HTTP 422 "file extension not
  allowed".
- Never use `CreateRelease.yaml` for a backport: it bumps `main` and promotes `main` builds.

## Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `AL1153 … runtime reference version '17.0' cannot be loaded by the compiler with version '16.0'`, then `AS0091`, then cascading `AS0004` / `AS0068` with `__MissingTypeSymbol__` | AppSourceCop downloads the previous release (BC `N+1`, runtime 17) as baseline; the BC `N` compiler cannot read it. The code itself compiles. | `"skipUpgrade": true` on the backport branch only (gate above) |
| Dependent app fails to install/compile on the BC `N` container, dependency built for BC `N+1` | its `appDependencyProbingPaths` still points the dependency at `main` | `"branch": "release/bc<N>"` on that entry; rebuild the dependency's backport first |
| Backport build `28.2.16` while the BC 28 build is `28.2.11` | AL-Go stamps the run number into the build field | expected; say it to the user. The customer's later move to BC `N+1` needs `28.3.x` or the next minor, or BC sees a downgrade |
| `gh release create` fails with HTTP 422 | `.app` extension not allowed as an asset | zip it |
| Release shows up as "Latest" | missing `--latest=false` | `gh release edit <tag> --prerelease --latest=false` |

## Later builds of the same line

A fix needed only by the BC `N` customer goes on `release/bc<N>` (cherry-pick from `main` when
the code exists there), through the same steps 3–5 with the next `-bc<N>` tag. A fix needed by
everyone goes to `main` first, through the normal PR flow.

## Related

- `skill-al-go-workflows`: branch model, workflows, settings, reading a failed run
- `skill-changelog`: release notes for the backport line, if the customer wants them
