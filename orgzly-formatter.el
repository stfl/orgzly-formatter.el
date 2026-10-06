;;; orgzly-formatter.el --- Orgzly-compatible blank-line formatter for org-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026 Stefan Lendl

;; Author: Stefan Lendl <git@stfl.dev>
;; Version: 0.3.3
;; Package-Requires: ((emacs "27.1") (org "9.7"))
;; Keywords: outlines, convenience, files
;; Homepage: https://github.com/stfl/orgzly-formatter
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Enforces blank-line and whitespace conventions that keep org files
;; byte-for-byte identical between Emacs and Orgzly (the Android org client),
;; eliminating the spurious git diffs that Orgzly's auto-formatter produces.
;;
;; ─── Rules ────────────────────────────────────────────────────────────────────
;;
;;   R1.  Exactly one blank line BEFORE each heading (except at buffer start).
;;        A heading immediately preceded by another heading (empty subtree) has
;;        surplus blank lines stripped rather than added.
;;
;;   R2.  One blank line between a drawer :END: and following body text.
;;        When an :END: line is immediately followed by non-blank body text
;;        (not a heading, not another drawer), one blank line is inserted.
;;        A drawer that ends a section (no body follows) is left unchanged,
;;        and so is a drawer before the first heading: Orgzly keeps that
;;        text as written.
;;        After the :PROPERTIES: drawer of an entry's head, R5 then sets
;;        the gap: exactly one blank line, or none before a line Orgzly
;;        writes directly under the head.
;;
;;   R3.  Exactly one blank line at the END of every entry that has content.
;;        "Content" = any non-blank line that follows the heading: planning
;;        lines, property drawers, and/or body text.  A heading-only entry
;;        (nothing between the heading and the next * or EOF) gets NO trailing
;;        blank line.
;;
;;   R4.  Planning keywords normalized to Orgzly's canonical layout.
;;        Any CLOSED / DEADLINE / SCHEDULED tokens on the line(s) directly
;;        following a heading are rewritten as a single line in the order
;;        `CLOSED DEADLINE SCHEDULED', separated by single spaces.  Org-mode
;;        itself preserves whatever order the user typed; Orgzly's writer
;;        (org-java's `OrgParserWriter.whiteSpacedHead') always emits this
;;        canonical order, causing spurious diffs.  Indentation of the first
;;        planning line is preserved.
;;
;;   R5.  Exactly one blank line between an entry's head and its body text.
;;        The head is the heading line, the planning line directly under
;;        it and a :PROPERTIES: drawer directly under those, each if
;;        present; a planning line needs a timestamp after its keyword,
;;        as Orgzly reads it.  When body text follows the head, the
;;        blank lines in between become exactly one: Orgzly's parser
;;        drops them and its writer puts one back under the "Separate
;;        header and content" setting.  Not body text, and so left
;;        alone: a heading and a second planning line directly under the
;;        head.  Not body text either: a drawer, a CLOCK line and a log
;;        note such as "- State ...".  Orgzly writes those directly under
;;        the head, so the blank lines before one are removed; a
;;        :PROPERTIES: drawer that ends up there joins the head.  A
;;        planning line after a blank line is body text.  Case matters,
;;        as in org-java: "Deadline:" and "- state" are body text.
;;        Source, in github.com/orgzly-revived/org-java at e15645ee
;;        (the fork Orgzly Revived builds on), under
;;        src/main/java/com/orgzly/org/:
;;          - parser/OrgSaxyParser.java, `parse': binds planning lines
;;            and the :PROPERTIES: drawer under a heading to the head;
;;          - parser/OrgSaxyParser.java, `trimContent' (through
;;            OrgStringUtils.java, `trimLines'): drops the content's
;;            leading blank lines;
;;          - parser/OrgParserWriter.java, `whiteSpacedHead': writes one
;;            blank line before the content unless it starts with
;;            ":LOGBOOK:" or "CLOCK: ", `isLogNoteHeading' matches it, or
;;            `lineStartswithDrawer' matches its first line.
;;
;;   WS.  Trailing whitespace removed from every line, a carriage return
;;        before the newline included: Orgzly reads lines with Java's
;;        readLine, so mixed line endings come back from it as \n only.
;;        Exception: a heading whose only payload is a TODO keyword plus a
;;        single trailing space ("* NEXT ") keeps that space — org-mode needs
;;        it to distinguish a keyword-only heading from one whose title begins
;;        with the keyword string.
;;
;;   EOF. Buffer ends with exactly one blank line (two consecutive newlines).
;;        Orgzly trims extra trailing newlines; we do the same.
;;
;; ─── Usage ────────────────────────────────────────────────────────────────────
;;
;; Enable globally (recommended):
;;   (orgzly-formatter-global-setup)
;;
;; Enable only in the current buffer:
;;   M-x orgzly-formatter-mode
;;
;; Run once without the mode:
;;   M-x orgzly-formatter-buffer
;;
;;; Code:

(require 'org)
(require 'org-element)

(defgroup orgzly-formatter nil
  "Orgzly-compatible blank-line and whitespace enforcement for org-mode."
  :group 'org
  :prefix "orgzly-formatter-")

;;;; ── Internal helpers ────────────────────────────────────────────────────────

(defconst orgzly-formatter--no-separator-re
  (concat "[ \t]*"
          "\\(?:"
          ;; `lineStartswithDrawer': the trimmed line starts and ends
          ;; with a colon.
          ":\\(?:.*:\\)?[ \t]*$"
          ;; Prefix tests on the trimmed content.
          "\\|:LOGBOOK:"
          "\\|CLOCK: "
          ;; org-java's ORG_LOG_NOTE_HEADINGS: the English prefixes of
          ;; the default `org-log-note-headings'.  Orgzly never reads
          ;; the user's setting, so neither does this.
          "\\|- "
          (regexp-opt '("CLOSING NOTE " "State " "Note taken on "
                        "Rescheduled from " "Not scheduled, was "
                        "New deadline from " "Removed deadline, was "
                        "Refiled on "))
          "\\)")
  "Matches a first body line that Orgzly writes directly under the head.
org-java's `OrgParserWriter.whiteSpacedHead' leaves out the blank line
between head and content when the content starts with a drawer, a
CLOCK line or a log note.  R5 removes the blank lines before one.")

(defconst orgzly-formatter--planning-re
  (concat "[ \t]*\\(?:CLOSED\\|DEADLINE\\|SCHEDULED\\): *"
          ;; org-java's DT: an active or inactive timestamp.
          "[[<][0-9]\\{4,\\}-[0-9]\\{2\\}-[0-9]\\{2\\} ?[^]\r\n>]*?[]>]")
  "Matches a planning line as Orgzly reads one: a keyword, then a timestamp.
org-java's PLANNING_TIMES_P needs the timestamp, so \"SCHEDULED: tbd\"
is body text to Orgzly although Org's `org-planning-line-re' matches it.
Unlike PLANNING_TIMES_P, the keyword must start the line, as in Org.")

(defsubst orgzly-formatter--state-only-heading-p ()
  "Non-nil when the current line is a keyword-only org heading.
Example: \"* NEXT \" — the single trailing space is load-bearing for
org-mode; it distinguishes a heading that carries only a TODO keyword
from one whose title starts with that keyword string.  We must not strip it."
  (save-excursion
    (beginning-of-line)
    (looking-at (concat "^\\*+ " org-todo-regexp " $"))))

(defun orgzly-formatter--entry-has-content-p ()
  "Non-nil when the org entry at point has content beyond its heading line.
Leading blank lines between the heading and the first real content line are
not counted; they are skipped first.

Content includes: planning lines (SCHEDULED/DEADLINE/CLOSED), property
drawers (:PROPERTIES: … :END:), and any body text."
  (save-excursion
    (let ((end (org-entry-end-position)))
      (forward-line 1)
      ;; Skip leading blank lines — they don't constitute content.
      (while (and (< (point) end) (looking-at-p "^[ \t\r]*$"))
        (forward-line 1))
      ;; Still inside the entry? Then there is real content.
      (< (point) end))))

(defun orgzly-formatter--prev-non-blank-is-heading-p ()
  "Non-nil when the closest non-blank line BEFORE point is an org heading.
Returns nil at start of buffer.  Detects an empty (heading-only) preceding
entry — i.e., between the previous heading and point there is nothing but
whitespace.  Used by R1 Case A and the EOF pass.

Uses `org-at-heading-p' rather than matching `^\\*+ ' by hand so the
detection follows org-mode's own grammar instead of an ad-hoc regex."
  (save-excursion
    (skip-chars-backward " \t\n")
    (and (not (bobp))
         (progn (beginning-of-line) (org-at-heading-p)))))

;;;; ── Formatting passes ───────────────────────────────────────────────────────

(defun orgzly-formatter--strip-trailing-whitespace ()
  "Remove trailing whitespace from every line in the current buffer.
A carriage return before the newline goes first: Orgzly reads lines with
Java's `BufferedReader.readLine', which ends a line at \\r\\n too, so a
file with mixed line endings comes back from Orgzly with \\n only.
Exception: lines matching `orgzly-formatter--state-only-heading-p' keep
their single trailing space (see that function's docstring)."
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (end-of-line)
      (delete-region (point) (progn (skip-chars-backward "\r") (point)))
      (unless (orgzly-formatter--state-only-heading-p)
        (end-of-line)
        (delete-horizontal-space))
      (forward-line 1))))

(defun orgzly-formatter--fix-entry ()
  "Apply blank-line rules R1 and R3 to the org entry at point.
Called once per heading by `org-map-entries'."
  (let* ((has-content (orgzly-formatter--entry-has-content-p))
         ;; Use a marker so the position tracks insertions made while widened.
         (entry-end (copy-marker (org-entry-end-position))))
    (unwind-protect
        ;; Both R1 (needs to see newlines before narrowing boundary) and R3
        ;; (may insert at entry-end near the narrowing boundary) require a
        ;; widened view.
        (org-with-wide-buffer

         ;; ── R1: exactly one blank line BEFORE this heading ──────────────
         (cond

          ;; Case A — immediately preceded by a heading line (empty subtree).
          ;; Strip any surplus blanks; do NOT insert one.
          ((orgzly-formatter--prev-non-blank-is-heading-p)
           (while (looking-back "\n\n" nil)
             (backward-char 1)
             (delete-char 1)))

          ;; Case B — more than one blank line: trim to exactly one.
          ((looking-back "\n\n\n+" nil)
           (while (looking-back "\n\n\n" nil)
             (backward-char 1)
             (delete-char 1)))

          ;; Case C — no blank line and not at buffer start: insert one.
          ((and (not (looking-back "\n\n" nil))
                (not (bobp)))
           (insert "\n")))

         ;; ── R3: exactly one blank line at END of entry content ──────────
         ;; Skipped entirely for heading-only entries (has-content = nil).
         (when has-content
           (goto-char entry-end)
           (unless (looking-back "\n\n" nil)
             (insert "\n"))))

      (set-marker entry-end nil))))

(defun orgzly-formatter--fix-blank-lines ()
  "Apply R1 and R3 to every heading in the current buffer."
  ;; scope nil → whole buffer; never 'tree (which only covers the subtree
  ;; under point, leaving the last entry and others outside it unfixed).
  (org-map-entries #'orgzly-formatter--fix-entry t nil))

(defun orgzly-formatter--fix-planning-order ()
  "Apply R4: normalize planning info to Orgzly's canonical single-line layout.
For each heading with planning info on the immediately-following line,
rewrite it as one line in the canonical order
`CLOSED DEADLINE SCHEDULED' with single-space separators, matching
Orgzly's `OrgParserWriter.whiteSpacedHead'.  Indentation of the
existing planning line is preserved.

Detection uses the built-in `org-planning-line-re'; planning data is
read from the headline element returned by `org-element-at-point',
using each timestamp's `:raw-value' to avoid locale-dependent
reformatting (e.g. `Su' → `So')."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (let* ((el (org-element-at-point))
             (clsd  (org-element-property :closed    el))
             (deadl (org-element-property :deadline  el))
             (sched (org-element-property :scheduled el)))
        (when (or clsd deadl sched)
          (forward-line 1)
          (let ((planning-start (point))
                (indent nil))
            ;; Scan over the (single) planning line org-mode recognizes,
            ;; capturing its indentation.  Org's grammar permits only one
            ;; planning line; we follow that and leave any stray
            ;; subsequent `KEYWORD:' lines as body text.
            (when (looking-at org-planning-line-re)
              (setq indent (buffer-substring-no-properties
                            (line-beginning-position)
                            (match-beginning 1)))
              (forward-line 1))
            (let* ((parts (delq nil
                                (list (and clsd  (concat "CLOSED: "
                                                         (org-element-property :raw-value clsd)))
                                      (and deadl (concat "DEADLINE: "
                                                         (org-element-property :raw-value deadl)))
                                      (and sched (concat "SCHEDULED: "
                                                         (org-element-property :raw-value sched))))))
                   (canonical (concat (or indent "")
                                      (mapconcat #'identity parts " ")
                                      "\n"))
                   (current (buffer-substring-no-properties planning-start (point))))
              (unless (string= current canonical)
                (delete-region planning-start (point))
                (insert canonical)))))))))

(defun orgzly-formatter--fix-drawer-separation ()
  "Apply R2: insert a blank line between a drawer's :END: and following body.

Walks `drawer' and `property-drawer' elements via `org-element-map' on the
parsed buffer.  The parser's `:post-blank' tells us whether a separator
already exists (idempotency); `:end' gives the position of the line
immediately after `:END:'.  At that position we use `org-at-heading-p'
and `org-drawer-regexp' to skip drawers followed by a heading, another
drawer, or EOF — those are covered by R3 and the EOF pass.

Going through the parser (rather than matching `^:END:' by hand) means
indented drawers are handled correctly and a literal `:END:' inside a
code block is not mistaken for a drawer terminator.

Drawers before the first heading are left alone.  Orgzly keeps that
text as written, trimming only blank lines at its ends (org-java's
`OrgSaxyParser.setTrimmedPreface' and
`OrgParserWriter.whiteSpacedFilePreface')."
  (let ((ends (org-element-map (org-element-parse-buffer)
                  '(drawer property-drawer)
                (lambda (el)
                  (when (and (org-element-lineage el '(headline))
                             (zerop (or (org-element-property :post-blank el) 0)))
                    (copy-marker (org-element-property :end el)))))))
    (dolist (m ends)
      (save-excursion
        (goto-char m)
        (when (and (not (eobp))
                   (not (org-at-heading-p))
                   (not (looking-at-p org-drawer-regexp)))
          (insert "\n")))
      (set-marker m nil))))

(defun orgzly-formatter--skip-property-drawer ()
  "Move past a property drawer that starts on the line at point.
Return non-nil when there is one.  As in org-java, the drawer is a
\":PROPERTIES:\" line through the next \":END:\" line, matched exactly;
one with no :END: before the next heading is not a drawer here."
  (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
    (let ((start (point)))
      (forward-line 1)
      (while (not (or (eobp)
                      (org-at-heading-p)
                      (looking-at-p "[ \t]*:END:[ \t]*$")))
        (forward-line 1))
      (if (looking-at-p "[ \t]*:END:[ \t]*$")
          (progn (forward-line 1) t)
        (goto-char start)
        nil))))

(defun orgzly-formatter--separate-head-from-body ()
  "Set the blank lines after the head that ends at point (R5).
Point is at the start of the line after the head."
  (let ((head-end (point)))
    (while (and (not (eobp)) (looking-at-p "[ \t\r]*$"))
      (forward-line 1))
    (cond
     ((or (eobp)
          (org-at-heading-p)
          (and (= (point) head-end)
               (looking-at-p orgzly-formatter--planning-re))))
     ((looking-at-p orgzly-formatter--no-separator-re)
      (delete-region head-end (point))
      ;; A property drawer now directly under the head is part of it on
      ;; Orgzly's next read, so the gap after its :END: follows R5 too.
      (when (orgzly-formatter--skip-property-drawer)
        (orgzly-formatter--separate-head-from-body)))
     ((/= (- (point) head-end) 1)
      (delete-region head-end (point))
      (insert "\n")))))

(defun orgzly-formatter--fix-head-separation ()
  "Apply R5: exactly one blank line between an entry's head and its body.
The head is the heading line, the planning line directly under it, if
any (`orgzly-formatter--planning-re' says what counts as one), and a
property drawer directly under those, if any.  That is the part of an
entry org-java's `OrgSaxyParser.parse' binds to the heading.  Orgzly's
parser trims the blank lines in front of the rest, the content, and its
writer puts one back (org-java's `OrgParserWriter.whiteSpacedHead',
under the \"Separate header and content\" setting), so:

- body text after the head gets exactly one blank line before it;
- a line `orgzly-formatter--no-separator-re' matches (a drawer, a CLOCK
  line, a log note) gets none, as Orgzly writes it directly under the
  head;
- a heading (R1), a second planning line directly under the head and
  the end of the buffer are left alone.

A planning line after a blank line is body text, to Org and to Orgzly.
Matching is case-sensitive, as org-java's is: \"Deadline:\" or
\"- state\" is body text."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (while (re-search-forward org-outline-regexp-bol nil t)
        (forward-line 1)
        (when (looking-at-p orgzly-formatter--planning-re)
          (forward-line 1))
        (orgzly-formatter--skip-property-drawer)
        (orgzly-formatter--separate-head-from-body)))))

(defun orgzly-formatter--fix-eof ()
  "Ensure the buffer ends with exactly one blank line (two consecutive \\n)."
  (save-excursion
    (goto-char (point-max))
    (cond
     ;; Empty heading at EOF: strip trailing blanks.
     ((orgzly-formatter--prev-non-blank-is-heading-p)
      (while (looking-back "\n\n" nil)
        (backward-char 1)
        (delete-char 1)))
     ;; Too many trailing blank lines: trim to one.
     ((looking-back "\n\n\n+" nil)
      (while (looking-back "\n\n\n" nil)
        (backward-char 1)
        (delete-char 1)))
     ;; No trailing blank: insert one.
     ((not (looking-back "\n\n" nil))
      (insert "\n")))))

;;;; ── Public API ──────────────────────────────────────────────────────────────

;;;###autoload
(defun orgzly-formatter-buffer ()
  "Format the entire org buffer for Orgzly compatibility.

Applies, in order:
  1. `orgzly-formatter--strip-trailing-whitespace'  (WS rule)
  2. `orgzly-formatter--fix-planning-order'         (R4 per heading)
  3. `orgzly-formatter--fix-blank-lines'            (R1 + R3 per heading)
  4. `orgzly-formatter--fix-drawer-separation'      (R2 per drawer)
  5. `orgzly-formatter--fix-head-separation'        (R5 per heading)
  6. `orgzly-formatter--fix-eof'                    (EOF rule)

The function is idempotent: running it on an already-correct buffer
produces no changes.  Safe to call from `before-save-hook'."
  (interactive)
  (orgzly-formatter--strip-trailing-whitespace)
  (orgzly-formatter--fix-planning-order)
  (orgzly-formatter--fix-blank-lines)
  (orgzly-formatter--fix-drawer-separation)
  (orgzly-formatter--fix-head-separation)
  (orgzly-formatter--fix-eof)
  (when (called-interactively-p 'interactive)
    (message "orgzly-formatter: buffer formatted")))

;;;###autoload
(define-minor-mode orgzly-formatter-mode
  "Automatically format org buffers on save for Orgzly compatibility.
Adds `orgzly-formatter-buffer' to `before-save-hook' buffer-locally."
  :lighter " orgzly-fmt"
  (if orgzly-formatter-mode
      (add-hook 'before-save-hook #'orgzly-formatter-buffer nil t)
    (remove-hook 'before-save-hook #'orgzly-formatter-buffer t)))

;;;###autoload
(defun orgzly-formatter-global-setup ()
  "Enable `orgzly-formatter-mode' in every org-mode buffer.
Call once in your init file:
  (orgzly-formatter-global-setup)"
  (add-hook 'org-mode-hook #'orgzly-formatter-mode))

(provide 'orgzly-formatter)
;;; orgzly-formatter.el ends here
