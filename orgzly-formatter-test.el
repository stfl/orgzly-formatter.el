;;; orgzly-formatter-test.el --- ERT tests for orgzly-formatter -*- lexical-binding: t -*-

;; Copyright (C) 2026 Stefan Lendl
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Run from the command line:
;;   emacs -batch -l orgzly-formatter.el -l orgzly-formatter-test.el \
;;           -f ert-run-tests-batch-and-exit
;;
;; Or via the Makefile:
;;   make test

;;; Code:

(require 'ert)
(require 'org)
(require 'orgzly-formatter)

;;;; ── Test helper ─────────────────────────────────────────────────────────────

(defmacro ozfmt-deftest (name doc input expected)
  "Define an ERT test NAME (doc-string DOC) that runs the full formatter.
Inserts INPUT into a fresh org-mode buffer, calls `orgzly-formatter-buffer',
and asserts the result equals EXPECTED.

TODO/NEXT/DONE keywords are always configured so state-only heading tests
work regardless of the caller's `org-todo-keywords'."
  (declare (indent 3) (doc-string 2))
  `(ert-deftest ,name ()
     ,doc
     (let ((result
            (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
              (with-temp-buffer
                ;; delay-mode-hooks prevents our own save-hook from firing
                ;; inside the test and interfering with assertions.
                (delay-mode-hooks (org-mode))
                (insert ,input)
                (orgzly-formatter-buffer)
                (buffer-string)))))
       (should (equal result ,expected)))))

;;;; ── WS: trailing whitespace ─────────────────────────────────────────────────
;; These tests use \n-escaped strings intentionally: Emacs strips trailing
;; spaces on save, which would silently corrupt the test inputs/expectations.

(ozfmt-deftest ozfmt/ws/strips-body-line
               "Trailing spaces on a body line are removed."
               "* H\nbody text   \n"
               "* H\nbody text\n\n")

(ozfmt-deftest ozfmt/ws/strips-heading-trailing-spaces
               "Trailing spaces on a plain heading (no keyword) are removed."
               "* Heading   \n"
               "* Heading\n")

(ozfmt-deftest ozfmt/ws/strips-titled-todo-heading
               "A TODO heading with a title loses trailing spaces — only keyword-only gets the exemption."
               "* TODO My task   \n"
               "* TODO My task\n")

(ozfmt-deftest ozfmt/ws/preserves-todo-state-only-space
               "* TODO  (single trailing space) is preserved — load-bearing for org parser."
               "* TODO \n"
               "* TODO \n")

(ozfmt-deftest ozfmt/ws/preserves-next-state-only-space
               "* NEXT  (single trailing space) is preserved."
               "* NEXT \n"
               "* NEXT \n")

(ozfmt-deftest ozfmt/ws/strips-multiple-trailing-spaces-on-state-heading
               "Three trailing spaces on a state-only heading are all stripped (pattern requires exactly one)."
               "* NEXT   \n"
               "* NEXT\n")

;;;; ── Empty entries (heading only, no content) ───────────────────────────────

(ozfmt-deftest ozfmt/empty/single-heading
               "A file with a single empty heading produces no trailing blank line."
               "* Heading
"
               "* Heading
")

(ozfmt-deftest ozfmt/empty/two-adjacent-headings
               "Two adjacent empty headings: no blank line injected."
               "* A
* B
"
               "* A
* B
")

(ozfmt-deftest ozfmt/empty/blank-between-empty-headings-stripped
               "A stray blank line between two empty headings is removed by R1 case A."
               "* A

* B
"
               "* A
* B
")

(ozfmt-deftest ozfmt/empty/multiple-blanks-between-empty-headings-stripped
               "Multiple blank lines between two empty headings collapse to zero."
               "* A



* B
"
               "* A
* B
")

(ozfmt-deftest ozfmt/empty/heading-only-last-entry-no-eof-blank
               "The last heading-only entry in the file gets no trailing blank line."
               "* First
some content

* Last
"
               "* First
some content

* Last
")

;;;; ── Content entries: R3 trailing blank ─────────────────────────────────────

(ozfmt-deftest ozfmt/content/body-gets-trailing-blank
               "An entry with plain body text gets exactly one trailing blank (diff 1 regression)."
               "* H
body text
* Next
"
               "* H
body text

* Next
")

(ozfmt-deftest ozfmt/content/drawer-only-gets-trailing-blank
               "An entry with only a properties drawer gets a trailing blank (diff 2 regression)."
               "* H
:PROPERTIES:
:ID: abc123
:END:
* Next
"
               "* H
:PROPERTIES:
:ID: abc123
:END:

* Next
")

(ozfmt-deftest ozfmt/content/planning-only-gets-trailing-blank
               "An entry with only a SCHEDULED line gets a trailing blank."
               "* H
SCHEDULED: <2026-03-16 Mo>
* Next
"
               "* H
SCHEDULED: <2026-03-16 Mo>

* Next
")

(ozfmt-deftest ozfmt/content/planning-plus-drawer-gets-trailing-blank
               "Planning + properties, no body — still gets a trailing blank."
               "* H
SCHEDULED: <2026-03-16 Mo>
:PROPERTIES:
:ID: x
:END:
* Next
"
               "* H
SCHEDULED: <2026-03-16 Mo>
:PROPERTIES:
:ID: x
:END:

* Next
")

(ozfmt-deftest ozfmt/content/body-trailing-blank-already-present
               "When the trailing blank already exists the buffer is unchanged (idempotent)."
               "* H
body text

* Next
"
               "* H
body text

* Next
")

(ozfmt-deftest ozfmt/content/last-entry-with-body-gets-trailing-blank
               "The last entry in the file gets a trailing blank even with no next heading."
               "* A
body
"
               "* A
body

")

(ozfmt-deftest ozfmt/content/multiline-body-gets-single-trailing-blank
               "Multiple body lines get exactly one trailing blank, not one per line."
               "* H
line one
line two
line three
* Next
"
               "* H
line one
line two
line three

* Next
")

;;;; ── R1: blank before headings ──────────────────────────────────────────────

(ozfmt-deftest ozfmt/r1/no-blank-before-first-heading
               "The very first heading must not gain a leading blank line (bobp guard)."
               "* First
body
"
               "* First
body

")

(ozfmt-deftest ozfmt/r1/one-blank-already-correct
               "Exactly one blank before a heading: nothing changes."
               "* A
body

* B
"
               "* A
body

* B
")

(ozfmt-deftest ozfmt/r1/two-blanks-trimmed-to-one
               "Two blank lines between content headings are trimmed to one."
               "* A
body


* B
"
               "* A
body

* B
")

(ozfmt-deftest ozfmt/r1/three-blanks-trimmed-to-one
               "Three blank lines between content headings are trimmed to one."
               "* A
body



* B
"
               "* A
body

* B
")

(ozfmt-deftest ozfmt/r1/blank-inserted-when-missing-between-content-headings
               "When content A is followed immediately by B (no blank), R3 for A fires and
satisfies R1 for B in the same pass."
               "* A
body
* B
body
"
               "* A
body

* B
body

")

;;;; ── EOF rule ────────────────────────────────────────────────────────────────

(ozfmt-deftest ozfmt/eof/one-trailing-blank-unchanged
               "A file already ending with exactly one blank line is not modified."
               "* H
body

"
               "* H
body

")

(ozfmt-deftest ozfmt/eof/two-trailing-blanks-trimmed
               "Two trailing blank lines (diff 3 regression) are trimmed to one."
               "* H
body


"
               "* H
body

")

(ozfmt-deftest ozfmt/eof/three-trailing-blanks-trimmed
               "Three trailing blank lines are trimmed to one."
               "* H
body



"
               "* H
body

")

(ozfmt-deftest ozfmt/eof/empty-heading-at-eof-no-trailing-blank
               "An empty heading at EOF does not get a trailing blank."
               "* Content
body

* EmptyAtEnd
"
               "* Content
body

* EmptyAtEnd
")

;;;; ── Idempotency ─────────────────────────────────────────────────────────────

(ert-deftest ozfmt/idempotent/already-formatted-buffer ()
  "Running the formatter on a correctly-formatted buffer produces no changes."
  (let ((input "* First
SCHEDULED: <2026-03-16 Mo>
:PROPERTIES:
:ID: abc-123
:END:

* Empty
* Last
body text

"))
    (let ((result
           (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
             (with-temp-buffer
               (delay-mode-hooks (org-mode))
               (insert input)
               (orgzly-formatter-buffer)
               (buffer-string)))))
      (should (equal result input)))))

(ert-deftest ozfmt/idempotent/two-runs-produce-same-output ()
  "Two successive formatter runs yield identical output."
  (let ((input "* A
content A
* B empty
* C
:PROPERTIES:
:ID: xyz
:END:
body C


"))
    (let* ((first-pass
            (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
              (with-temp-buffer
                (delay-mode-hooks (org-mode))
                (insert input)
                (orgzly-formatter-buffer)
                (buffer-string))))
           (second-pass
            (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
              (with-temp-buffer
                (delay-mode-hooks (org-mode))
                (insert first-pass)
                (orgzly-formatter-buffer)
                (buffer-string)))))
      (should (equal second-pass first-pass)))))

;;;; ── Regression: exact diffs from the bug report ────────────────────────────

(ozfmt-deftest ozfmt/regression/diff1-blank-after-content-section
               "Diff 1 regression: Orgzly added \\n after a body content entry."
               "* DONE Write skill doc
CLOSED: [2026-03-02 Mo 09:48] SCHEDULED: <2026-02-26 Do>

continue and finish writing down the skill with

claude --resume be0987e1-c562-4aad-a373-a06cb0628d7f
* Next heading
"
               "* DONE Write skill doc
CLOSED: [2026-03-02 Mo 09:48] SCHEDULED: <2026-02-26 Do>

continue and finish writing down the skill with

claude --resume be0987e1-c562-4aad-a373-a06cb0628d7f

* Next heading
")

(ozfmt-deftest ozfmt/regression/diff2-blank-after-properties-only
               "Diff 2 regression: Orgzly added \\n after :END: in a properties-only entry."
               "* TODO Some task
SCHEDULED: <2026-03-16 Mo>
:CREATED:  [2026-03-16 Mo 08:30]
:ID:       a335e133-26c3-4b3d-a6b5-05dc52790b50
:END:
* Next heading
"
               "* TODO Some task
SCHEDULED: <2026-03-16 Mo>
:CREATED:  [2026-03-16 Mo 08:30]
:ID:       a335e133-26c3-4b3d-a6b5-05dc52790b50
:END:

* Next heading
")

(ozfmt-deftest ozfmt/regression/diff3-extra-trailing-newlines-removed
               "Diff 3 regression: Orgzly removed extra trailing newlines."
               "* Last heading
Speaker 2
body text here



"
               "* Last heading
Speaker 2
body text here

")

;;;; ── Conflicting mode warnings ──────────────────────────────────────────────

;; Declare as special so the `let' binding in the test below is dynamic and
;; visible to `boundp' / `symbol-value' (lexical-binding: t would otherwise
;; make un-defvar'd let-bindings invisible to those functions).
(defvar ws-butler-mode nil)

(defmacro ozfmt--with-warnings (&rest body)
  "Evaluate BODY and return a list of (TYPE MESSAGE) pairs from `display-warning'."
  (declare (indent 0))
  `(let (warnings)
     (cl-letf (((symbol-function 'display-warning)
                (lambda (type msg &rest _)
                  (push (list type msg) warnings))))
       ,@body)
     (nreverse warnings)))

(ert-deftest ozfmt/warn/no-warning-without-conflicting-modes ()
  "No warning when no whitespace-mangling modes are active."
  (with-temp-buffer
    (let ((warnings (ozfmt--with-warnings
                      (orgzly-formatter--check-conflicting-modes))))
      (should (null warnings)))))

(ert-deftest ozfmt/warn/ws-butler-mode ()
  "Warns when ws-butler-mode is active."
  (with-temp-buffer
    (let ((ws-butler-mode t))
      (let ((warnings (ozfmt--with-warnings
                        (orgzly-formatter--check-conflicting-modes))))
        (should (= 1 (length warnings)))
        (should (eq 'orgzly-formatter (caar warnings)))
        (should (string-match-p "ws-butler-mode" (cadar warnings)))))))


;;; orgzly-formatter-test.el ends here
