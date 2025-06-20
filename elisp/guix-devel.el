;;; guix-devel.el --- Development tools  -*- lexical-binding: t -*-

;; Copyright © 2015-2018, 2020 Alex Kost <alezost@gmail.com>
;; Copyright © 2018 Oleg Pykhalov <go.wigust@gmail.com>
;; Copyright © 2020 Maxim Cournoyer

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

;; This file provides `guix-devel-mode' (minor mode for `scheme-mode'
;; buffers) that provides highlighting and indentation rules for Guix
;; Guile code, as well as some tools to work with Guix (or even an
;; arbitrary Guile code) with Geiser.

;;; Code:

(require 'lisp-mode)
(require 'bui-utils)
(require 'guix nil t)
(require 'guix-utils)
(require 'guix-guile)
(require 'guix-geiser)
(require 'guix-misc)
(require 'ffap)

(defgroup guix-devel nil
  "Settings for Guix development utils."
  :group 'guix)

(defgroup guix-devel-faces nil
  "Faces for `guix-devel-mode'."
  :group 'guix-devel
  :group 'guix-faces)

(defface guix-devel-modify-phases-keyword
  '((t :inherit font-lock-preprocessor-face))
  "Face for a `modify-phases' keyword (`delete', `replace', etc.)."
  :group 'guix-devel-faces)

(defface guix-devel-gexp-symbol
  '((t :inherit font-lock-keyword-face))
  "Face for gexp symbols ('#~', '#$', etc.).
See Info node `(guix) G-Expressions'."
  :group 'guix-devel-faces)

(defun guix-devel-use-modules (&rest modules)
  "Use guile MODULES."
  (apply #'guix-geiser-call "use-modules" modules))

(defun guix-devel-use-module (&optional module)
  "Use guile MODULE in the current Geiser REPL.
MODULE is a string with the module name - e.g., \"(ice-9 match)\".
Interactively, use the module defined by the current scheme file."
  (interactive (list (guix-guile-current-module)))
  (guix-devel-use-modules module)
  (message "Using %s module." module))

(defun guix-devel-copy-module-as-kill ()
  "Put the name of the current guile module into `kill-ring'."
  (interactive)
  (bui-copy-as-kill (guix-guile-current-module)))

(defun guix-devel-setup-repl (&optional repl)
  "Setup REPL for using `guix-devel-...' commands."
  (guix-devel-use-modules "(guix monad-repl)"
                          "(guix scripts)"
                          "(guix store)"
                          "(guix ui)")
  ;; Without this workaround, the warning/build output disappears.  See
  ;; <https://gitlab.com/jaor/geiser/issues/83> for details.
  (guix-geiser-eval-in-repl-synchronously
   "(begin
      (guix-warning-port (current-warning-port))
      (current-build-output-port (current-error-port)))"
   repl 'no-history 'no-display))

(defvar guix-devel-repl-processes nil
  "List of REPL processes configured by `guix-devel-setup-repl'.")

(defun guix-devel-setup-repl-maybe (&optional repl)
  "Setup (if needed) REPL for using `guix-devel-...' commands."
  (let ((process (get-buffer-process (or repl (guix-geiser-repl)))))
    (when (and process
               (not (memq process guix-devel-repl-processes)))
      (guix-devel-setup-repl repl)
      (push process guix-devel-repl-processes))))

(defmacro guix-devel-with-definition (def-var &rest body)
  "Run BODY with the current guile definition bound to DEF-VAR.
Bind DEF-VAR variable to the name of the current top-level
definition, setup the current REPL, use the current module, and
run BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,def-var (guix-guile-current-definition)))
     (guix-devel-setup-repl-maybe)
     (guix-devel-use-modules (guix-guile-current-module))
     ,@body))

(defun guix-devel-build-package-definition ()
  "Build a package defined by the current top-level variable definition."
  (interactive)
  (guix-devel-with-definition def
    (when (or (not guix-operation-confirm)
              (guix-operation-prompt (format "Build '%s'?" def)))
      (guix-geiser-eval-in-repl
       (concat ",run-in-store "
               (guix-guile-make-call-expression
                "build-package" def
                "#:use-substitutes?" (guix-guile-boolean
                                      guix-use-substitutes)
                "#:dry-run?" (guix-guile-boolean guix-dry-run)))))))

(defun guix-devel-build-package-source ()
  "Build the source of the current package definition."
  (interactive)
  (guix-devel-with-definition def
    (when (or (not guix-operation-confirm)
              (guix-operation-prompt
               (format "Build '%s' package source?" def)))
      (guix-geiser-eval-in-repl
       (concat ",run-in-store "
               (guix-guile-make-call-expression
                "build-package-source" def
                "#:use-substitutes?" (guix-guile-boolean
                                      guix-use-substitutes)
                "#:dry-run?" (guix-guile-boolean guix-dry-run)))))))

(defun guix-devel-download-package-source ()
  "Download the source of the current package.
Use this function to compute SHA256 hash of the package source."
  (interactive)
  (guix-devel-with-definition def
    (guix-devel-use-modules "(guix packages)"
                            "(guix scripts download)")
    (when (or (not guix-operation-confirm)
              (y-or-n-p (format "Download '%s' package source?" def)))
      (guix-geiser-eval-in-repl
       (format "(guix-download (origin-uri (package-source %s)))"
               def)))))

(defun guix-devel-lint-package ()
  "Check the current package.
See Info node `(guix) Invoking guix lint' for details."
  (interactive)
  (guix-devel-with-definition def
    (guix-devel-use-modules "(guix lint)"
			    "(guix scripts lint)")
    (when (or (not guix-operation-confirm)
              (y-or-n-p (format "Lint '%s' package?" def)))
      (guix-geiser-eval-in-repl
       (format "(run-checkers %s %%all-checkers)" def)))))


;;; Font-lock

(defvar guix-devel-modify-phases-keyword-regexp
  (rx (or "delete" "replace" "add-before" "add-after"))
  "Regexp for a `modify-phases' keyword.")

(defun guix-devel-modify-phases-font-lock-matcher (limit)
  "Find a `modify-phases' keyword.
This function is used as a MATCHER for `font-lock-keywords'."
  (ignore-errors
    (down-list)
    (or (re-search-forward guix-devel-modify-phases-keyword-regexp
                           limit t)
        (set-match-data nil))
    (up-list)
    t))

(defun guix-devel-modify-phases-font-lock-pre ()
  "Skip the next sexp, and return the end point of the current list.
This function is used as a PRE-MATCH-FORM for `font-lock-keywords'
to find `modify-phases' keywords."
  (let ((in-comment? (nth 4 (syntax-ppss))))
    ;; If 'modify-phases' is commented, do not try to search for its
    ;; keywords.
    (unless in-comment?
      (ignore-errors (forward-sexp))
      (save-excursion (up-list) (point)))))

(defconst guix-devel-keywords
  '(;; The `call-…' symbols are procedures, not macros, so they probably
    ;; should not be highlighted.
    ;;
    ;; "call-with-compressed-output-port"
    ;; "call-with-container"
    ;; "call-with-decompressed-port"
    ;; "call-with-derivation-narinfo"
    ;; "call-with-derivation-substitute"
    ;; "call-with-error-handling"
    ;; "call-with-gzip-input-port"
    ;; "call-with-gzip-output-port"
    ;; "call-with-lzip-intput-port"
    ;; "call-with-lzip-output-port"
    ;; "call-with-progress-reporter"
    ;; "call-with-prompt"
    ;; "call-with-temporary-directory"
    ;; "call-with-temporary-output-file"
    ;; "call-with-transaction"
    "define-enumerate-type"
    "define-gexp-compiler"
    "define-lift"
    "define-monad"
    "define-operation"
    "define-record-type*"
    "emacs-substitute-sexps"
    "emacs-substitute-variables"
    "mbegin"
    "mlambda"
    "mlambdaq"
    "mlet"
    "mlet*"
    "modify-services"
    "munless"
    "mwhen"
    "run-with-state"
    "run-with-store"
    "signature-case"
    "substitute*"
    "substitute-keyword-arguments"
    "test-assertm"
    "use-package-modules"
    "use-service-modules"
    "use-system-modules"
    "with-atomic-file-output"
    "with-atomic-file-replacement"
    "with-build-handler"
    "with-database"
    "with-derivation-narinfo"
    "with-derivation-substitute"
    "with-directory-excursion"
    "with-error-handling"
    "with-extensions"
    "with-external-store"
    "with-file-lock"
    "with-file-lock/no-wait"
    "with-imported-modules"
    "with-monad"
    "with-parameters"
    "with-profile-lock"
    "with-status-report"
    "with-status-verbosity"
    "with-temporary-git-repository"
    "with-mutex"
    "with-store"))

(defvar guix-devel-font-lock-keywords
  `((,(rx (or "#~" "#$" "#$@" "#+" "#+@")) .
     'guix-devel-gexp-symbol)
    (,(guix-guile-keyword-regexp (regexp-opt guix-devel-keywords))
     (1 'font-lock-keyword-face))
    (,(guix-guile-keyword-regexp "modify-phases")
     (1 'font-lock-keyword-face)
     (guix-devel-modify-phases-font-lock-matcher
      (guix-devel-modify-phases-font-lock-pre)
      nil
      (0 'guix-devel-modify-phases-keyword nil t))))
  "A list of `font-lock-keywords' for `guix-devel-mode'.")


;;; Indentation

(defmacro guix-devel-scheme-indent (&rest rules)
  "Set `scheme-indent-function' according to RULES.
Each rule should have a form (SYMBOL VALUE).  See `put' for details."
  (declare (indent 0))
  `(progn
     ,@(mapcar (lambda (rule)
                 `(put ',(car rule) 'scheme-indent-function ,(cadr rule)))
               rules)))

(defun guix-devel-indent-package (state indent-point normal-indent)
  "Indentation rule for `package' form."
  (let* ((package-eol (line-end-position))
         (count (if (and (ignore-errors (down-list) t)
                         (< (point) package-eol)
                         (looking-at "inherit\\>"))
                    1
                  0)))
    (lisp-indent-specform count state indent-point normal-indent)))

(defun guix-devel-indent-modify-phases-keyword (count)
  "Return indentation function for `modify-phases' keywords."
  (lambda (state indent-point normal-indent)
    (when (ignore-errors
            (goto-char (nth 1 state))   ; start of keyword sexp
            (backward-up-list)
            (looking-at "(modify-phases\\>"))
      (lisp-indent-specform count state indent-point normal-indent))))

(defalias 'guix-devel-indent-modify-phases-keyword-1
  (guix-devel-indent-modify-phases-keyword 1))
(defalias 'guix-devel-indent-modify-phases-keyword-2
  (guix-devel-indent-modify-phases-keyword 2))

(guix-devel-scheme-indent
  (bag 0)
  (build-system 0)
  (call-with-compressed-output-port 2)
  (call-with-container 1)
  (call-with-decompressed-port 2)
  (call-with-error-handling 0)
  (call-with-gzip-input-port 1)
  (call-with-gzip-output-port 1)
  (call-with-lzip-input-port 1)
  (call-with-lzip-output-port 1)
  (call-with-progress-reporter 1)
  (call-with-prompt 1)
  (call-with-transaction 1)
  (container-excursion 1)
  (emacs-batch-edit-file 1)
  (emacs-batch-eval 0)
  (emacs-substitute-sexps 1)
  (emacs-substitute-variables 1)
  (eventually 1)
  (file-system 0)
  (graft 0)
  (manifest-entry 0)
  (manifest-pattern 0)
  (mbegin 1)
  (mlambda 1)
  (mlambdaq 1)
  (mlet 2)
  (mlet* 2)
  (modify-phases 1)
  (modify-services 1)
  (munless 1)
  (mwhen 1)
  (operating-system 0)
  (origin 0)
  (package 'guix-devel-indent-package)
  (run-with-state 1)
  (run-with-store 1)
  (signature-case 1)
  (substitute* 1)
  (substitute-keyword-arguments 1)
  (syntax-parameterize 1)
  (test-assertm 1)
  (with-atomic-file-output 1)
  (with-build-handler 1)
  (with-database 2)
  (with-derivation-narinfo 1)
  (with-derivation-substitute 2)
  (with-directory-excursion 1)
  (with-error-handling 0)
  (with-extensions 1)
  (with-external-store 1)
  (with-file-lock 1)
  (with-file-lock/no-wait 1)
  (with-imported-modules 1)
  (with-monad 1)
  (with-mutex 1)
  (with-parameters 1)
  (with-profile-lock 1)
  (with-status-report 1)
  (with-status-verbosity 1)
  (with-store 1)
  (with-temporary-git-repository 1)
  (wrap-program 1)

  ;; 'modify-phases' keywords:
  (replace    'guix-devel-indent-modify-phases-keyword-1)
  (add-after  'guix-devel-indent-modify-phases-keyword-2)
  (add-before 'guix-devel-indent-modify-phases-keyword-2))


;;; Edit synopsis/description

(require 'edit-indirect nil t)

(defvar guix-devel-code-block-regexp
  (rx (syntax open-parenthesis)
      (or "description" "synopsis")
      not-wordchar)
  "Regexp used by \\[guix-devel-code-block-edit].")

(defun guix-devel-code-block-position ()
  "Return (beginning . end) positions of the string at point to edit."
  (save-excursion
    (narrow-to-defun)
    (unless (re-search-backward guix-devel-code-block-regexp nil t)
      (widen)
      (user-error "The point should be inside 'description' or 'synopsis'"))
    (widen)
    (cons (re-search-forward (rx (syntax string-quote)))
          (1- (progn (backward-char)
                     (forward-sexp)
                     (point))))))

;;;###autoload
(defun guix-devel-code-block-edit ()
  "Edit the current synopsis/description in `texinfo-mode'."
  (interactive)
  (let* ((pos (guix-devel-code-block-position))
         (begin (car pos))
         (end (cdr pos))
         (edit-indirect-guess-mode-function
          (lambda (&rest _) (texinfo-mode))))
    (edit-indirect-region begin end 'display-buffer)))


(defvar guix-devel-keys-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "b") 'guix-devel-build-package-definition)
    (define-key map (kbd "s") 'guix-devel-build-package-source)
    (define-key map (kbd "d") 'guix-devel-download-package-source)
    (define-key map (kbd "l") 'guix-devel-lint-package)
    (define-key map (kbd "k") 'guix-devel-copy-module-as-kill)
    (define-key map (kbd "u") 'guix-devel-use-module)
    (define-key map (kbd "'") 'guix-devel-code-block-edit)
    map)
  "Keymap with subkeys for `guix-devel-mode-map'.")

(defvar guix-devel-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c .") guix-devel-keys-map)
    map)
  "Keymap for `guix-devel-mode'.")

;;;###autoload
(define-minor-mode guix-devel-mode
  "Minor mode for `scheme-mode' buffers.

With a prefix argument ARG, enable the mode if ARG is positive,
and disable it otherwise.  If called from Lisp, enable the mode
if ARG is omitted or nil.

When Guix Devel mode is enabled, it highlights various Guix
keywords.  This mode can be enabled programmatically using hooks,
like this:

  (add-hook \\='scheme-mode-hook \\='guix-devel-mode)

\\{guix-devel-mode-map}"
  :init-value nil
  :lighter " Guix"
  :keymap guix-devel-mode-map
  (if guix-devel-mode
      (progn
        (setq-local font-lock-multiline t)
        (font-lock-add-keywords nil guix-devel-font-lock-keywords))
    (setq-local font-lock-multiline nil)
    (font-lock-remove-keywords nil guix-devel-font-lock-keywords))
  (guix-font-lock-flush))


;;; Find file at point

(defcustom guix-devel-ffap-patch-directories
  (list (getenv "GUIX_PACKAGE_PATH") "patches")
  "List of directories for `guix-devel-ffap-patch'.
Look at Info node `(emacs-guix) Development' to see how
\\[ffap] command can be configured to open Guix patch files."
  :group 'guix-devel
  :type '(repeat (directory :tag "Directory")))

(defun guix-devel-ffap-patch (patch)
  "Return Guix package patch from around point if it exists, or nil."
  (and guix-devel-mode
       (or (ffap-locate-file patch t guix-devel-ffap-patch-directories)
           (expand-file-name patch (car guix-devel-ffap-patch-directories)))))

(provide 'guix-devel)

;;; guix-devel.el ends here
