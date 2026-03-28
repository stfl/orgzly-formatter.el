# CLAUDE.md

This file provides guidance to Coding agents like Claude Code when working with code in this repository.

## Commands

All commands must be run inside the Nix dev shell via `nix develop -- <cmd>`,
which provides `eask`, `just`, and `emacs` on PATH. This is also required for
`git commit` since the pre-commit hooks invoke `eask`.

```sh
# Byte-compile the package
nix develop -- just compile

# Run the full ERT test suite
nix develop -- just test

# Run both (default)
nix develop -- just

# Run a subset of tests by name prefix
nix develop -- emacs -batch -Q -L . \
  -l orgzly-formatter.el \
  -l orgzly-formatter-test.el \
  --eval '(ert-run-tests-batch "ozfmt/regression")'

# Lint with package-lint
nix develop -- just lint

# Clean byte-compiled output
nix develop -- just clean

# Commit (pre-commit hooks require eask)
nix develop -- git commit
```

## Architecture

This is a single-file Emacs Lisp package (`orgzly-formatter.el`) with a companion test file (`orgzly-formatter-test.el`).

### Formatting rules enforced

- **R1** — Exactly one blank line before each heading (except buffer start). Adjacent empty headings get zero blank lines.
- **R3** — Exactly one blank line at the end of every entry that has content (planning/drawer/body). Heading-only entries get none.
- **WS** — Trailing whitespace stripped from all lines. Exception: keyword-only headings like `* NEXT ` keep their single trailing space (org-mode requires it to distinguish a keyword-only heading from a title starting with the keyword).
- **EOF** — Buffer ends with exactly one blank line.

### Execution order in `orgzly-formatter-buffer`

1. `orgzly-formatter--strip-trailing-whitespace` (WS rule)
2. `orgzly-formatter--fix-blank-lines` → calls `orgzly-formatter--fix-entry` per heading via `org-map-entries` (R1 + R3)
3. `orgzly-formatter--fix-eof` (EOF rule)

The formatter is idempotent: running it on an already-correct buffer produces no changes.

### Test conventions

Tests use the `ozfmt-deftest` macro which spins up a temp org-mode buffer with `delay-mode-hooks` (preventing the save-hook from firing inside tests), inserts input, runs `orgzly-formatter-buffer`, and asserts the result string. Test names follow the pattern `ozfmt/<category>/<description>`.
