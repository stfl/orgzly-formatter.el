EMACS ?= emacs
BATCH  = $(EMACS) -batch -Q

PACKAGE = orgzly-formatter
EL      = $(PACKAGE).el
TEST    = $(PACKAGE)-test.el

.PHONY: all test compile lint clean

all: compile test

## ── Byte-compile ─────────────────────────────────────────────────────────────
compile:
	$(BATCH) -L . -f batch-byte-compile $(EL)

## ── ERT tests ────────────────────────────────────────────────────────────────
test:
	$(BATCH) -L . -l $(EL) -l $(TEST) -f ert-run-tests-batch-and-exit

## ── package-lint (optional, requires package-lint to be installed) ────────────
lint:
	$(BATCH) -L . \
	  --eval "(require 'package)" \
	  --eval "(package-initialize)" \
	  --eval "(require 'package-lint)" \
	  -f package-lint-batch-and-exit $(EL)

## ── Cleanup ──────────────────────────────────────────────────────────────────
clean:
	rm -f $(PACKAGE).elc
