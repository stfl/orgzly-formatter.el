emacs := env_var_or_default("EMACS", "emacs")
package := "orgzly-formatter"
el := package + ".el"

default: compile test

# Byte-compile
compile:
    eask recompile

# ERT tests.  Clean first so a stale .elc from a previous `just compile'
# can't shadow uncommitted edits to the .el source.  install-deps pulls
# pinned org from GNU ELPA so older Emacs (29.x ships org 9.6.x) gets a
# satisfying version per the Eask `(depends-on "org" "9.7")' clause.
test: clean
    eask install-deps
    eask run script test

# package-lint
lint:
    eask lint package {{el}}

# Remove compiled files
clean:
    rm -f {{package}}.elc

# Verify Eask version matches the .el ;; Version: header
check-version:
    #!/usr/bin/env bash
    set -eu
    eask_ver=$(grep -oP '^\s*"\K[0-9][^"]*' Eask | head -n1)
    el_ver=$(grep -oP '^;;\s*Version:\s*\K\S+' {{el}})
    if [ -z "$eask_ver" ] || [ -z "$el_ver" ]; then
        echo "✗ Could not extract versions (Eask='$eask_ver', {{el}}='$el_ver')" >&2
        exit 1
    fi
    if [ "$eask_ver" != "$el_ver" ]; then
        echo "✗ Version mismatch: Eask=$eask_ver vs {{el}}=$el_ver" >&2
        exit 1
    fi

# Verify the given tag (passed as arg, e.g. v0.2.0) matches the package version.
# Used by the release CI workflow on tag push. Enforces the GitHub convention:
# tag must be prefixed with `v` (semver itself stays unprefixed, per SemVer FAQ).
check-tag-version TAG:
    #!/usr/bin/env bash
    set -eu
    el_ver=$(grep -oP '^;;\s*Version:\s*\K\S+' {{el}})
    tag='{{TAG}}'
    case "$tag" in
        v*) ;;
        *)
            echo "✗ Tag $tag must start with 'v' (GitHub convention, e.g. v$el_ver)" >&2
            exit 1
            ;;
    esac
    stripped="${tag#v}"
    if [ "$stripped" != "$el_ver" ]; then
        echo "✗ Tag $tag does not match {{el}} version $el_ver (expected v$el_ver)" >&2
        exit 1
    fi
