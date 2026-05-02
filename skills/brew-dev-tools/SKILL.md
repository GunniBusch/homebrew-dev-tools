---
name: brew-dev-tools
description: Use when working on Homebrew formula contributor workflows in a repo that has this tap available, especially to run brew wwdd, normalize formula commits with brew prsync, create or update PRs, add PR issue references, or inspect bottle metadata with brew bottles.
---

# Brew Dev Tools

Use this skill when the task is a Homebrew formula contribution workflow and the `brew-dev-tools` tap is available. It is for using the repo's contributor helpers correctly, not for generic Homebrew usage.

## When To Use

- Updating, fixing, or adding Homebrew formulae in `homebrew/core` or another formula tap.
- Preparing a PR with one commit per formula.
- Running contributor validation with `brew wwdd`.
- Creating or updating a PR with `brew prsync`, including AI disclosure and issue or PR footer references.
- Inspecting bottle metadata or bottle contents with `brew bottles`.

## Default Workflow

1. Resolve the target formulae.
If the user names formulae, use those names explicitly. If not, let `brew wwdd` or `brew prsync` infer changed formulae from `Formula/**/*.rb`.

2. Validate formula changes first.
Use `brew wwdd <formula>` as the default local validation pass.
Use `brew wwdd --install <formula>` when a source build is required.
Use `brew wwdd --online <formula>` when audit needs online checks.

3. Preview history normalization before rewriting.
Run `brew prsync <formula>` first.
Only use `--apply` after reviewing the plan.

4. Publish only when the branch is ready.
Typical publish flow:

```sh
brew prsync --apply --push --pr <formula>
```

5. Add PR footers only through `--pr`.
Issue and PR references must be passed with `--pr`:

```sh
brew prsync --apply --push --pr --closes=123 --fixes=#456 --ref=owner/repo#789 <formula>
```

## Command Guide

### Validation

```sh
brew wwdd foo
brew wwdd --install foo
brew wwdd --online foo
```

What it does:
- `style --fix`
- `test`
- `audit --new` or `audit --strict`
- optional `install --build-from-source`

### Commit And PR Workflow

```sh
brew prsync foo
brew prsync --apply foo
brew prsync --apply --push foo
brew prsync --apply --push --pr foo
```

Use `--style=homebrew` for `homebrew/core` if you need to override style detection.
Use `--style=conventional` for non-Homebrew repos if you need to force Conventional Commits formatting.

### AI Disclosure

If `brew wwdd` detected AI usage, `brew prsync --pr` carries that into the PR automatically.
Use `--ai` only to force disclosure when no detected `wwdd` AI report is available.

### Bottle Inspection

```sh
brew bottles foo
brew bottles --contents --tag arm64_sequoia foo
brew bottles --compare foo bar
brew bottles --compare --contents --tag arm64_tahoe --against-tag sonoma foo
```

Use this when reviewing bottle contents, tag differences, or whether two bottles of the same formula may be compatible with an `:all` candidate.

## Guardrails

- `brew prsync` only supports formula-owned changes under `Formula/**/*.rb`. Non-formula changes will hard-fail.
- `--closes`, `--fixes`, and `--ref` require `--pr`.
- `brew prsync --apply` rewrites branch history from the merge-base. Review preview output first.
- Prefer explicit formula args when the branch contains multiple unrelated formula changes.
- Generated commits are signed by default. Do not disable signing outside tests.
- In `homebrew/core`, prefer Homebrew-native commit and PR titles. In other repos, the default is Conventional Commits.
