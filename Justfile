emacs := env_var_or_default("EMACS", "emacs")
package := "orgzly-formatter"
el := package + ".el"

default: compile test

# Byte-compile
compile:
    eask recompile

# ERT tests
test:
    eask run script test

# package-lint
lint:
    eask lint package {{el}}

# Remove compiled files
clean:
    rm -f {{package}}.elc
