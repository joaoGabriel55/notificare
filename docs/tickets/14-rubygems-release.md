# 14 — Versioning & RubyGems release

## Goal
Cut the first public release of `notificare` to [rubygems.org](https://rubygems.org) as a prerelease (`alpha`) and put the supporting automation in place so subsequent releases are a one-tag operation. Source: [RubyGems guides](https://guides.rubygems.org/) — *Make Your Own Gem*, *Publishing*, *Patterns* (prerelease versions), and *Trusted Publishing*.

## Why prerelease first
The public API is feature-complete (tickets 01–13) but has not been exercised by external users. A `0.1.0.alpha.1` release on rubygems lets early adopters install via `gem "notificare", "~> 0.1.0.alpha"` (or `gem install notificare --pre`) without committing the gem to a stable SemVer line. Stable `0.1.0` ships once feedback from the alpha cycle settles.

## Scope

### Versioning
- Bump `lib/active_job/notificare/version.rb` to `"0.1.0.alpha.1"`.
  - Per the RubyGems *Patterns* guide, any version string with at least one letter is treated as a prerelease and is not installed by default — `1.5.0.beta.3`, `2.0.0.rc1`, `1.0.0.pre` are all valid; we follow the `<x.y.z>.alpha.<n>` shape.
- Document the version policy in a new `## Releases` section at the bottom of `README.md`:
  - `0.1.0.alpha.N` — public preview, breaking changes allowed, feedback wanted.
  - `0.1.0` — first stable cut; breaking changes thereafter follow SemVer.
- Update the `Gem Version` badge in `README.md` to point at `https://img.shields.io/gem/v/notificare` (live shield) instead of the hardcoded `v0.1.0` placeholder.

### Gemspec polish (publish-readiness)
The current `notificare.gemspec` is missing a few fields that rubygems.org surfaces on the gem page and that `bundler` warns about on `gem build`:
- `spec.metadata` with the conventional keys: `"homepage_uri"`, `"source_code_uri"`, `"changelog_uri"`, `"bug_tracker_uri"`, `"rubygems_mfa_required" => "true"` (the latter opts the gem into MFA-on-publish, which rubygems.org now recommends for new gems).
- `spec.required_rubygems_version = ">= 3.5"` (matches Ruby 3.3+ baseline).
- Verify `spec.files` excludes `test/`, `coverage/`, `docs/`, and other non-runtime paths — current glob already does this implicitly by allow-listing `lib/`, `app/`, `config/`, `LICENSE`, `README.md`, but add an explicit assertion in the build test (below) so a future change can't silently inflate the gem.
- Add a `LICENSE` file at the repo root if not present (MIT, matching `spec.license`); `gem build` warns if `LICENSE` is referenced but missing.

### CHANGELOG
- Create `CHANGELOG.md` at repo root following [Keep a Changelog](https://keepachangelog.com/) format. Seed entries:
  - `## [Unreleased]` — empty section for next iteration.
  - `## [0.1.0.alpha.1] - 2026-05-03` — bullet list of the 13 shipped tickets, grouped under `Added`.
- Add `changelog_uri` in `gemspec.metadata` pointing at the file on GitHub at the released tag (e.g. `https://github.com/joaoGabriel55/notificare/blob/v0.1.0.alpha.1/CHANGELOG.md`).

### Trusted publishing (GitHub Actions → rubygems.org)
Use rubygems' *Trusted Publishing* (OIDC) flow rather than long-lived API keys, per the guide. Configuration lives in two places:

1. **rubygems.org side** — the maintainer (Gabriel) registers a *pending trusted publisher* on their rubygems profile **before** the first push, with:
   - Repository: `joaoGabriel55/notificare`
   - Workflow filename: `release.yml`
   - Environment: `release`
   - Gem name: `notificare`

2. **Repo side** — new workflow `.github/workflows/release.yml`:
   ```yaml
   name: Release gem

   on:
     push:
       tags:
         - "v*"

   jobs:
     push:
       runs-on: ubuntu-latest
       environment: release
       permissions:
         contents: write
         id-token: write
       steps:
         - uses: actions/checkout@v5
           with:
             persist-credentials: false
         - uses: ruby/setup-ruby@v1
           with:
             bundler-cache: true
             ruby-version: "3.3"
         - uses: rubygems/release-gem@v1
   ```
   The `id-token: write` permission is **mandatory** at the job level — without it the OIDC handshake fails and the push is rejected. `release-gem@v1` runs `gem build`, exchanges the GitHub OIDC token for a short-lived rubygems API token scoped to `notificare`, and runs `gem push`.

### Branch protection (`main`)
Lock `main` so only the repo owner (`joaoGabriel55`) can merge PRs — this prevents an accidental direct push or a stray collaborator merge from triggering the release workflow with bad code. Use a GitHub **ruleset** (newer system, available on free public repos) rather than the classic branch-protection UI:

- Target: `Branch` → `Include default branch` (`main`).
- Rules:
  - **Restrict deletions** — on.
  - **Block force pushes** — on.
  - **Require a pull request before merging** — on; required approvals: `0` (a solo owner can't approve their own PR, so we gate on merge identity instead).
  - **Require status checks to pass** — on; select the existing `test` and `adapter-tests` jobs from `.github/workflows/ci.yml`.
  - **Restrict who can push to matching refs** (in the ruleset's *Bypass list* / *Restrict pushes* section): allow only `joaoGabriel55` (the *Repository owner* role on a personal repo). All other roles (Collaborator, Maintain, Write) are excluded from merge.
- Enforcement: `Active` (not `Evaluate`).

Equivalent via `gh api` (run once after `gh auth login` with a token that has `repo` + `admin:repo` scopes):
```bash
gh api -X POST repos/joaoGabriel55/notificare/rulesets \
  -f name="Protect main" \
  -f target="branch" \
  -f enforcement="active" \
  -f 'conditions[ref_name][include][]=~DEFAULT_BRANCH' \
  -f 'rules[][type]=deletion' \
  -f 'rules[][type]=non_fast_forward' \
  -f 'rules[][type]=pull_request' \
  -f 'rules[][type]=required_status_checks' \
  -F 'rules[][parameters][required_status_checks][]={"context":"test"}' \
  -F 'rules[][parameters][required_status_checks][]={"context":"adapter-tests"}' \
  -f 'bypass_actors[][actor_id]=5' \
  -f 'bypass_actors[][actor_type]=RepositoryRole' \
  -f 'bypass_actors[][bypass_mode]=always'
```
(`actor_id=5` is the built-in *Repository admin* role; on a personal repo that resolves to the owner only.)

Verification:
- A PR opened from a fork or a non-owner collaborator branch shows a **"Merge pull request"** button only when reviewed by the owner; the owner's own PRs can still be merged because they hold the admin bypass.
- `git push origin main` (direct, no PR) from any account is rejected.

### Release procedure (documented in `CONTRIBUTING.md` or the README's Releases section)
The end-to-end flow once the workflow is in place:
```bash
# 1. Bump version + changelog on a release branch
$EDITOR lib/active_job/notificare/version.rb CHANGELOG.md
git commit -am "Release 0.1.0.alpha.1"

# 2. Tag and push
git tag v0.1.0.alpha.1
git push origin main --tags

# 3. The release workflow takes over: gem build + trusted-publisher push
```

For the **very first** release (or as a fallback if trusted publishing isn't yet wired), the manual flow per the *Publishing* and *Make Your Own Gem* guides is:
```bash
gem signin                       # interactive; OTP if MFA enabled
gem build notificare.gemspec     # produces notificare-0.1.0.alpha.1.gem
gem push notificare-0.1.0.alpha.1.gem
```

## Out of scope
- Full SemVer 1.0 release — explicitly deferred until alpha feedback is folded in.
- Automated changelog generation (e.g. `release-please`) — reconsider after we cut a couple of releases manually.
- Signed gems / `gem cert` — rubygems' *Security Practices* guide notes this is optional and brittle; trusted publishing already gives us a strong provenance signal.

## Acceptance criteria
- `gem build notificare.gemspec` produces a `.gem` file with no warnings.
- `gem unpack notificare-0.1.0.alpha.1.gem` shows only `lib/`, `app/`, `config/`, `LICENSE`, `README.md` — no `test/`, `coverage/`, `docs/`, `.github/`, or dotfiles.
- A pending trusted publisher is registered on rubygems.org for repo `joaoGabriel55/notificare`, workflow `release.yml`, environment `release`.
- A branch-protection ruleset is active on `main`: deletions blocked, force-push blocked, PR required, CI required, and only the owner role can bypass / merge.
- Pushing a `v0.1.0.alpha.1` tag triggers the workflow, which publishes the gem to rubygems.org.
- `gem install notificare --pre` from a clean machine fetches `0.1.0.alpha.1` and the dummy app's `bundle install` resolves against the published version.
- The rubygems gem page (`https://rubygems.org/gems/notificare`) shows the `homepage_uri`, `source_code_uri`, `changelog_uri`, and `bug_tracker_uri` links from `gemspec.metadata`.

## Tests (mandatory)
- **Gemspec sanity test** (`test/notificare_gemspec_test.rb`): loads `notificare.gemspec`, asserts presence and shape of `metadata` keys (`source_code_uri`, `changelog_uri`, `bug_tracker_uri`, `rubygems_mfa_required == "true"`), `license == "MIT"`, `required_ruby_version` covers `>= 3.3`. Asserts `spec.files` does **not** include any path under `test/`, `coverage/`, `docs/`, `.github/`.
- **Build smoke test** (CI step, not minitest): runs `gem build notificare.gemspec` and `gem unpack` in a tmpdir; fails the build if any unexpected files land in the unpacked tree or if `gem build` emits a warning.
- **Version format test** (extend `test/active_job/notificare/version_test.rb`): asserts `VERSION` matches the rubygems prerelease shape `\A\d+\.\d+\.\d+(\.[a-z]+(\.\d+)?)?\z` so a typo like `0.1.0-alpha` (Cargo-style, invalid in rubygems) trips CI.
- **Changelog parity test**: reads `CHANGELOG.md`, asserts the topmost released heading matches `VERSION`. Prevents a tag-without-changelog release.

## Rollback / yank
If a bad release ships, follow the *Publishing* guide's `gem yank` flow:
```bash
gem yank notificare -v 0.1.0.alpha.1
```
Yanking removes the version from the index but does not delete it — re-pushing the same version is not allowed, so the next attempt must bump to `0.1.0.alpha.2`.
