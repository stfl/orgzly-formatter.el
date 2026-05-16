# CLAUDE.md

This file provides guidance to Coding agents like Claude Code when working with code in this repository.

## Commands

All commands must be run inside the Nix dev shell via `nix develop --command <cmd>`,
which provides `eask`, `just`, and `emacs` on PATH. This is also required for
`git commit` since the pre-commit hooks invoke `eask`.

```sh
# Byte-compile the package
nix develop --command just compile

# Run the full ERT test suite.  The `test' recipe runs `clean' first so
# a stale `.elc' from a previous `just compile' can never shadow your
# uncommitted edits to the `.el' source — `eask' picks `.elc' over `.el'
# when both exist, which silently runs tests against old bytecode.
nix develop --command just test

# Run both (default)
nix develop --command just

# Run a subset of tests by name prefix
nix develop --command emacs -batch -Q -L . \
  -l orgzly-formatter.el \
  -l orgzly-formatter-test.el \
  --eval '(ert-run-tests-batch "ozfmt/regression")'

# Lint with package-lint
nix develop --command just lint

# Clean byte-compiled output
nix develop --command just clean

# Commit (pre-commit hooks require eask)
nix develop --command git commit
```

## Architecture

This is a single-file Emacs Lisp package (`orgzly-formatter.el`) with a companion test file (`orgzly-formatter-test.el`).

### Formatting rules enforced

- **R1** — Exactly one blank line before each heading (except buffer start). Adjacent empty headings get zero blank lines.
- **R2** — One blank line between a drawer `:END:` and following body text.
- **R3** — Exactly one blank line at the end of every entry that has content (planning/drawer/body). Heading-only entries get none.
- **R4** — Planning keywords (`CLOSED` / `DEADLINE` / `SCHEDULED`) on the line right after a heading are rewritten in Orgzly's canonical order — `CLOSED DEADLINE SCHEDULED`, single-space separated. Indentation of the existing planning line is preserved. Detection uses `org-planning-line-re`; parsing uses `org-element-at-point` on the heading and each timestamp's `:raw-value` (locale-safe). Multi-line planning info is not merged because org-mode's grammar permits only a single planning line.
- **WS** — Trailing whitespace stripped from all lines. Exception: keyword-only headings like `* NEXT ` keep their single trailing space (org-mode requires it to distinguish a keyword-only heading from a title starting with the keyword).
- **EOF** — Buffer ends with exactly one blank line.

### Execution order in `orgzly-formatter-buffer`

1. `orgzly-formatter--strip-trailing-whitespace` (WS rule)
2. `orgzly-formatter--fix-planning-order` (R4 per heading)
3. `orgzly-formatter--fix-blank-lines` → calls `orgzly-formatter--fix-entry` per heading via `org-map-entries` (R1 + R3)
4. `orgzly-formatter--fix-drawer-separation` (R2 per drawer)
5. `orgzly-formatter--fix-eof` (EOF rule)

### Prefer org APIs over manual parsing

This package is a thin formatter on top of `org-mode`. Before adding hand-rolled regex/state machines, check whether org already exposes a parser or detector — e.g. `org-planning-line-re`, `org-element-at-point` (heading element exposes `:scheduled`/`:deadline`/`:closed` timestamps with `:raw-value`), `org-end-of-meta-data`, `org-entry-end-position`, `org-map-entries`. R4 in particular relies on org-element so it stays correct under timestamp ranges, repeaters, and warning periods without bespoke regex maintenance.

The formatter is idempotent: running it on an already-correct buffer produces no changes.

### Test conventions

Tests use the `ozfmt-deftest` macro which spins up a temp org-mode buffer with `delay-mode-hooks` (preventing the save-hook from firing inside tests), inserts input, runs `orgzly-formatter-buffer`, and asserts the result string. Test names follow the pattern `ozfmt/<category>/<description>`.
