;;; guix-locate.el --- Prettify Guix store file names  -*- lexical-binding: t -*-

;; Copyright © 2026 Sergio Pastor Pérez <sergio.pastorperez@gmail.com>

;; This file is part of Emacs-Guix.

;; Emacs-Guix is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; Emacs-Guix is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacs-Guix.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a 'consult.el' frontend for 'guix locate'.

;; Use it through 'M-x consult-guix-locate'. By default the prompt is in glob
;; mode, meaning that the input takes wildcards as 'guix locate -g ...'
;; does. That means that 'foo*bar' would match 'foobazbar'.

;;; Code:

(require 'seq)
(require 'consult)

(defcustom guix-locate-args
  '("guix" "locate")
  "Command line arguments for 'guix locate'.
Can be either a string, or a list of strings or expressions."
  :type '(choice string (repeat (choice string sexp))))

(defun guix-locate--consult-guix-locate (prompt builder initial)
  "Run 'guix locate'.

The function returns the selected file.
The filename at point is added to the future history.

BUILDER is the command line builder function.
PROMPT is the prompt.
INITIAL is initial input."
  (consult--read
   (consult--process-collection builder
     :transform (consult--async-map (lambda (x) (string-remove-prefix "./" x)))
     :highlight t :file-handler t) ;; allow tramp
   :prompt prompt
   :sort nil
   :require-match t
   :initial initial
   :add-history (thing-at-point 'filename)
   :category 'file
   :history '(:input consult--find-history)))

(defun guix-locate--globs-to-regex (globs)
  "Convert SQlite GLOBS into a list of regexps."
  (mapcar (lambda (glob)
            ;; `wildcard-to-regexp' expects POSIX globs.  SQLite globs us '^'
            ;; for group negation while POSIX ones use '!'.
            (let* ((posix (replace-regexp-in-string "\\[\\^" "[!" glob))
                   (regex (wildcard-to-regexp posix)))
              ;; `wildcard-to-regexp' anchors the regex by wrapping it in '\`' and
              ;; '\'', `consult--highlight-regexps' will not work with the ancors.
              (substring regex 2 -2)))
          (ensure-list globs)))

(defun guix-locate--consult-highlight-globs (globs ignore-case str)
  "Highlight list of GLOBS in STR.
Case insensitive if IGNORE-CASE is non-nil."
  (consult--highlight-regexps (guix-locate--globs-to-regex globs)
                              ignore-case str))

(defun guix-locate--make-consult-builder ()
  "Build 'guix locate' command line."
  (let ((cmd (consult--build-args guix-locate-args)))
    (lambda (input)
      (pcase-let* ((`(,arg . ,opts) (consult--command-split input))
                   (flags (append cmd opts))
                   (ignore-case nil))
        (when-let* ((args (consult--split-escaped arg))
                    (args* (list
                            "-g"
                            (concat
                             (seq-reduce (lambda (rest arg)
                                           (concat rest "*" arg))
                                         args
                                         '())
                             "*"))))
          (cons
           (append cmd opts args*)
           (apply-partially #'guix-locate--consult-highlight-globs
                            args ignore-case)))))))

;;;###autoload
(defun guix-locate (&optional initial)
  "Search for files with 'guix locate'.
The file names must match the input SQLite glob.  INITIAL is the initial
minibuffer input."
  (interactive "P")
  (let* ((prompt "Guix locate: ")
         (builder (guix-locate--make-consult-builder))
         (selection (consult--find prompt builder initial))
         (file (car (last (string-split selection)))))
    (find-file file)))

(provide 'guix-locate)

;;; guix-locate.el ends here
