# homebrew-dev-tools

Tap-distributed Homebrew contributor helpers focused on formula PR workflow.

## Repository Policy

This repository itself uses Conventional Commits 1.0.0 for both commit messages
and pull request titles. Treat that as mandatory project policy.

- Commits in this repo must use a Conventional Commits type such as `feat:`,
  `fix:`, `docs:`, `chore:`, or `ci:`
- Pull request titles for this repo must follow the same format
- `prsync` still generates Homebrew-native titles when you run it inside
  `homebrew/core`, because that repository has a different upstream policy

The repo ships three external commands:

- `brew prsync`: normalize commit history, generate commit/PR titles, push, and
  optionally create or update a PR
- `brew wwdd`: run the formula checks you usually want before sending a PR
- `brew bottles`: inspect or compare bottle metadata without installing formulae

## Commands

### `brew prsync`

Analyzes the current tap branch and plans a rewrite so there is exactly one
commit per changed formula. In apply mode it rewrites the branch from its
merge-base, recommits one formula file at a time, optionally force-pushes the
current branch, and can create or update the PR through `gh`.

Highlights:

- Blocks ambiguous non-formula changes by default.
- Detects mixed commits, same-formula squashes, and dirty amendments.
- Uses `auto` title style by default:
  - `homebrew/core`: Homebrew commit style (`foo 1.2.3`, `foo: ...`)
  - other taps: Conventional Commits style (`feat(...)`, `fix(...)`, `chore(...)`)
- Supports explicit style overrides with `--style=auto|homebrew|conventional`.
- Signs generated commits with `git commit -S` by default. Only the test
  harness disables signing inside temporary repositories.
- `brew wwdd` stores detected AI-shell metadata in its validation report.
- If `brew wwdd` detects AI usage, `brew prsync` always carries that forward
  into Homebrew AI/LLM disclosure text and checkbox state.
- `brew prsync --ai` force-enables AI disclosure when no detected `brew wwdd`
  report is available.
- Uses preview-first mode unless `--apply` is passed.
- When rewriting an existing single-formula commit, `prsync` preserves that
  commit title by default unless you pass `--message`.
- `--pr` looks up the PR by the current branch's head ref, using
  `OWNER:branch` when the branch tracks a GitHub fork remote.
- `--pr` is branch-based: if GitHub already has an open PR for the current
  branch, `prsync` updates it; otherwise it creates a new PR for that branch.
- In fork workflows, computes the merge-base against the upstream/non-fork
  remote by default. `--base` is only needed when you want to opt out of that.

Example:

```sh
brew prsync
brew prsync --apply
brew prsync --apply --push
brew prsync --apply --push --pr
brew prsync --apply --push --pr --ai
brew prsync --style=homebrew
brew prsync --style=conventional
brew prsync --message="fix(foo): adjust test dependency" foo
```

Standards used:

- Homebrew Formula Cookbook commit guidance for `homebrew/core`
- Conventional Commits 1.0.0 for generic taps and repositories

Default generated subjects:

- `homebrew/core`
  - new formula: `foo 1.2.3 (new formula)`
  - version bump: `foo 1.2.3`
  - fix/change: `foo: update formula`
- other taps
  - new formula: `feat(foo): add new formula 1.2.3`
  - version bump: `chore(foo): update to 1.2.3`
  - fix/change: `fix(foo): update formula`

PR titles follow the same rule set. For multi-formula non-Homebrew repos,
`prsync` generates a Conventional Commits-style rollup title.

Naming templates:

- `homebrew/core`
  - version bump commit or single-formula PR title: `<formula> <version>`
  - new formula commit or single-formula PR title: `<formula> <version> (new formula)`
  - formula fix commit or single-formula PR title: `<formula>: update formula`
- other taps
  - version bump commit or single-formula PR title: `chore(<formula>): update to <version>`
  - new formula commit or single-formula PR title: `feat(<formula>): add new formula <version>`
  - formula fix commit or single-formula PR title: `fix(<formula>): update formula`

For multi-formula PR titles:

- `homebrew/core`: `<first-formula> and N more formula updates`
- other taps: `chore: update N formulae` unless every formula is a new formula
  or every formula is a fix-only change, in which case the prefix becomes
  `feat:` or `fix:`

### `brew wwdd`

Runs formula contributor checks that complement the built-in `brew lgtm` dev
command:

1. `brew style --fix --formula <formula>`
2. `brew test <formula>`
3. `brew audit --new <formula>` for new formulae, otherwise
   `brew audit --strict <formula>`

Pass `--install` when you also want:

`HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source <formula>`

The latest validation report is stored in `.git/brew-dev-tools/wwdd-last.json`
so `brew prsync --pr` can include it in the PR body. That report also stores
detected AI-shell metadata. If AI was detected by `brew wwdd`, `brew prsync`
will always use that information for Homebrew AI/LLM disclosure, even without
`--ai`. Use `brew prsync --ai` to force disclosure when no detected AI report
is available.

Example:

```sh
brew wwdd
brew wwdd foo
brew wwdd --install foo
brew wwdd --online foo
```

### `brew bottles`

Browses stable bottle metadata directly from `brew info --json=v2`, and can
also inspect the contents of a specific bottle archive without installing it.

Use it to:

- list available stable bottle tags, cellar values, rebuild number, and root
  URL for one or more formulae
- inspect the file list inside a selected bottle archive with `--contents`
- compare either bottle metadata or the archive contents for two formulae
- compare two tags of the same formula to judge whether it is a plausible
  `:all` bottle candidate
- include a `diffoscope` report when comparing two tags of the same formula with
  `--contents`
- optionally include the full bottle blob URLs

Examples:

```sh
brew bottles zstd
brew bottles --urls zstd
brew bottles --contents --tag arm64_sequoia zstd
brew bottles --compare zstd xz
brew bottles --compare --contents --tag arm64_sequoia zstd xz
brew bottles --compare --tag arm64_tahoe --against-tag sonoma envio
brew bottles --compare --contents --tag arm64_tahoe --against-tag sonoma envio
```

## Install

1. Use a standard tap repository name such as `your-user/homebrew-dev-tools`.
2. Tap it:

```sh
brew tap GunniBusch/dev-tools
brew tap your-user/dev-tools /absolute/path/to/this/repo
```

3. Use:

```sh
brew prsync --help
brew wwdd --help
brew bottles --help
```

4. Link shell completions:

```sh
brew completions link
```

Homebrew does not link external tap completions by default. The tap ships
completion files under `completions/bash`, `completions/zsh`, and
`completions/fish`, which `brew completions link` links into Homebrew's normal
completion directories. Your shell still needs Homebrew completion support
enabled first; see Homebrew's shell completion documentation for the shell
startup configuration.

If you want GitHub automation from `brew prsync --pr`, make sure `gh auth status`
works in the target checkout.

## Safety model

- `brew prsync` only operates inside git-backed tap repositories.
- Formula file changes under `Formula/**/*.rb`, including nested paths such as
  `Formula/r/ripgrep.rb`, are considered owned by a formula in v1.
- Any changed file outside `Formula/**/*.rb` causes a hard failure.
- `--push` always uses `git push --force-with-lease`.
- `--pr` requires a working `gh auth status`.
- Protected branches still behave like protected branches. If `main` requires
  pull requests and status checks, push a feature branch and open a PR instead
  of expecting `prsync` to bypass repository rules.
- Commit signing is not disabled by the tool. If your repo requires signed
  commits, `prsync` signs commits explicitly and uses your configured key.

## Typical Flow

For `homebrew/core`:

```sh
cd "$(brew --repository homebrew/core)"
brew wwdd foo
brew prsync foo
brew prsync --apply --push --pr foo
```

For a personal tap using Conventional Commits:

```sh
cd "$(brew --repository your-user/your-tap)"
brew wwdd foo
brew prsync --style=conventional foo
brew prsync --apply --push --pr --style=conventional foo
```

## Development

Run the tests with:

```sh
brew ruby -- -Ilib:test -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```
