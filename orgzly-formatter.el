;;; orgzly-formatter.el --- Orgzly-compatible blank-line formatter for org-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026 Stefan Lendl

;; Author: Stefan Lendl <s@stfl.dev>
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1"))
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
;;        A drawer that ends a section (no body follows) is left unchanged.
;;
;;   R3.  Exactly one blank line at the END of every entry that has content.
;;        "Content" = any non-blank line that follows the heading: planning
;;        lines, property drawers, and/or body text.  A heading-only entry
;;        (nothing between the heading and the next * or EOF) gets NO trailing
;;        blank line.
;;
;;   WS.  Trailing whitespace removed from every line.
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

(defgroup orgzly-formatter nil
  "Orgzly-compatible blank-line and whitespace enforcement for org-mode."
  :group 'org
  :prefix "orgzly-formatter-")

;;;; ── Internal helpers ────────────────────────────────────────────────────────

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
      (while (and (< (point) end) (looking-at-p "^[ \t]*$"))
        (forward-line 1))
      ;; Still inside the entry? Then there is real content.
      (< (point) end))))

;;;; ── Formatting passes ───────────────────────────────────────────────────────

(defun orgzly-formatter--strip-trailing-whitespace ()
  "Remove trailing whitespace from every line in the current buffer.
Exception: lines matching `orgzly-formatter--state-only-heading-p' keep
their single trailing space (see that function's docstring)."
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
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
          ((looking-back "^\\*+ [^\n]*\n+" nil)
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

(defun orgzly-formatter--fix-drawer-separation ()
  "Apply R2: insert a blank line after drawer :END: when followed by body text.
Body text means any non-blank line that is neither a heading nor a drawer line."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^:END:\n" nil t)
      ;; Point is now at the start of the line immediately after :END:.
      (when (and (not (eobp))
                 (not (looking-at-p "^[ \t]*$"))  ; already has blank
                 (not (looking-at-p "^\\*"))        ; not a heading
                 (not (looking-at-p "^:")))         ; not another drawer line
        (insert "\n")))))

(defun orgzly-formatter--fix-eof ()
  "Ensure the buffer ends with exactly one blank line (two consecutive \\n)."
  (save-excursion
    (goto-char (point-max))
    (cond
     ;; Empty heading at EOF: strip trailing blanks.
     ((looking-back "^\\*+ [^\n]*\n+" nil)
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
  2. `orgzly-formatter--fix-blank-lines'            (R1 + R3 per heading)
  3. `orgzly-formatter--fix-drawer-separation'      (R2 per drawer)
  4. `orgzly-formatter--fix-eof'                    (EOF rule)

The function is idempotent: running it on an already-correct buffer
produces no changes.  Safe to call from `before-save-hook'."
  (interactive)
  (orgzly-formatter--strip-trailing-whitespace)
  (orgzly-formatter--fix-blank-lines)
  (orgzly-formatter--fix-drawer-separation)
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
