emacs := env_var_or_default("EMACS", "emacs")
package := "orgzly-formatter"
el := package + ".el"

default: compile test

# Byte-compile
compile:
    eask recompile

# ERT tests.  Clean first so a stale .elc from a previous `just compile'
# can't shadow uncommitted edits to the .el source.
test: clean
    eask run script test

# package-lint
lint:
    eask lint package {{el}}

# Remove compiled files
clean:
    rm -f {{package}}.elc
