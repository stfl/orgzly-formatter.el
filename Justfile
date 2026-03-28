emacs := env_var_or_default("EMACS", "emacs")
batch := emacs + " -batch -Q"
package := "orgzly-formatter"
el := package + ".el"
test_el := package + "-test.el"

default: compile test

# Byte-compile
compile:
    {{batch}} -L . -f batch-byte-compile {{el}}

# ERT tests
test:
    {{batch}} -L . -l {{el}} -l {{test_el}} -f ert-run-tests-batch-and-exit

# package-lint (requires package-lint to be installed)
lint:
    {{batch}} -L . \
      --eval "(require 'package)" \
      --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
      --eval "(package-initialize)" \
      --eval "(unless (package-installed-p 'package-lint) (package-refresh-contents) (package-install 'package-lint))" \
      --eval "(require 'package-lint)" \
      -f package-lint-batch-and-exit {{el}}

# Remove compiled files
clean:
    rm -f {{package}}.elc
