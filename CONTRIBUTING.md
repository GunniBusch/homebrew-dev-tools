# Contributing

## Commit And PR Title Policy

This repository requires [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
for both:

- commit messages
- pull request titles

Use a standard type prefix such as:

- `feat:`
- `fix:`
- `docs:`
- `chore:`
- `ci:`
- `refactor:`
- `test:`

Scoped forms are preferred when they make the change clearer, for example:

- `feat(prsync): support standardized title styles`
- `fix(prsync): sign generated commits explicitly`
- `docs(readme): document title styles and signing`

## Homebrew-specific behavior

This repository's own history uses Conventional Commits.

The `brew prsync` command is different: when you run it against
`homebrew/core`, it intentionally generates Homebrew-style commit subjects
because that repository requires them. For generic taps, `prsync` defaults back
to Conventional Commits.

The generated templates are:

- `homebrew/core`
  - version bump: `<formula> <version>`
  - new formula: `<formula> <version> (new formula)`
  - formula fix: `<formula>: update formula`
- other taps
  - version bump: `chore(<formula>): update to <version>`
  - new formula: `feat(<formula>): add new formula <version>`
  - formula fix: `fix(<formula>): update formula`
