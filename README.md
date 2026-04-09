# brew-dev-tools

Tap-distributed Homebrew contributor helpers focused on formula PR workflow.

## Commands

### `brew prsync`

Analyzes the current tap branch and plans a rewrite so there is exactly one
commit per changed formula. In apply mode it rewrites the branch from its
merge-base, recommits one formula file at a time, optionally force-pushes the
current branch, and can create or update the PR through `gh`.

Highlights:

- Blocks ambiguous non-formula changes by default.
- Detects mixed commits, same-formula squashes, and dirty amendments.
- Generates Homebrew-style commit subjects for new formulae and version bumps.
- Uses preview-first mode unless `--apply` is passed.

Example:

```sh
brew prsync
brew prsync --apply
brew prsync --apply --push
brew prsync --apply --push --pr
```

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

## Safety model

- `brew prsync` only operates inside git-backed tap repositories.
- Only direct formula file changes under `Formula/*.rb` are considered owned by a
  formula in v1.
- Any changed file outside `Formula/*.rb` causes a hard failure.
- `--push` always uses `git push --force-with-lease`.
- `--pr` requires a working `gh auth status`.

## Development

Run the tests with:

```sh
ruby -Ilib:test -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```
