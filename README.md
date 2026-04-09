# brew-dev-tools

Tap-distributed Homebrew contributor helpers focused on formula PR workflow.

The repo ships two external commands:

- `brew prsync`: normalize commit history, generate commit/PR titles, push, and
  optionally create or update a PR
- `brew wwdd`: run the formula checks you usually want before sending a PR

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
- Uses your normal git signing configuration for real commits. Only the test
  harness disables signing inside temporary repositories.
- Uses preview-first mode unless `--apply` is passed.

Example:

```sh
brew prsync
brew prsync --apply
brew prsync --apply --push
brew prsync --apply --push --pr
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

### `brew wwdd`

Runs formula contributor checks that complement the built-in `brew lgtm` dev
command:

1. `brew style --fix --formula <formula>`
2. `HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source <formula>`
3. `brew test <formula>`
4. `brew audit --new <formula>` for new formulae, otherwise
   `brew audit --strict <formula>`

The latest validation report is stored in `.git/brew-dev-tools/wwdd-last.json`
so `brew prsync --pr` can include it in the PR body.

Example:

```sh
brew wwdd
brew wwdd foo
brew wwdd --online foo
```

## Install

1. Turn this repository into a tap, for example `your-user/homebrew-dev-tools`.
2. Tap it:

```sh
brew tap your-user/dev-tools /absolute/path/to/this/repo
```

3. Use:

```sh
brew prsync --help
brew wwdd --help
```

If you want GitHub automation from `brew prsync --pr`, make sure `gh auth status`
works in the target checkout.

## Safety model

- `brew prsync` only operates inside git-backed tap repositories.
- Only direct formula file changes under `Formula/*.rb` are considered owned by a
  formula in v1.
- Any changed file outside `Formula/*.rb` causes a hard failure.
- `--push` always uses `git push --force-with-lease`.
- `--pr` requires a working `gh auth status`.
- Protected branches still behave like protected branches. If `main` requires
  pull requests and status checks, push a feature branch and open a PR instead
  of expecting `prsync` to bypass repository rules.
- Commit signing is not disabled by the tool. If your repo requires signed
  commits, configure git signing normally and `prsync` will use it.

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
