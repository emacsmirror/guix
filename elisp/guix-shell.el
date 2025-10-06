;;; guix-shell.el ---  Guix shell support within Emacs-Guix  -*- lexical-binding: t -*-

;; Copyright © 2025-2026 Tushar <tusharhero@sdf.org>

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

;;; Code:

(require 'guix-read)
(require 'eshell)

(declare-function eshell-set-path "esh-util.el")

(defvar guix-shell-directory-alist '() "Keeps track of the guix shell profiles.")
(defvar guix-shell-environment-alist '()
  "Keeps track of the guix shell profile's environment variables.")

(defun guix-set-buffer-environment (profile)
  "Set buffer's `process-environment' to match PROFILE.
PROFILE can be a named profile (like '~/.guix-profile',
~/.config/guix/work') or a direct link to profile from the
store, like GUIX_ENVIRONMENT variable (see Info node `(guix)
Invoking guix environment' for details).

If PROFILE is nil, use variable `guix-current-profile'."
  (interactive (list (guix-read-profile)))
  (let* ((profile-path (guix-file-name profile))
         (info-path
          (file-name-concat profile-path "share" "info"))
         (environment-variables
          (cdr (or (assoc-string profile-path guix-shell-environment-alist)
                   (push (cons profile-path
                               (guix-eval-read
                                (guix-make-guile-expression
                                 'search-paths-specifications
                                 profile-path)))
                         guix-shell-environment-alist)))))
    (setq-local Info-directory-list
                (cons info-path Info-directory-list))
    (dolist (variable environment-variables)
      (seq-let (name _ value) variable
        ;; The first value of the variable always takes
        ;; precedence.  So, we merge them.
        (setq-local process-environment
                    (cons
                     (concat name "="
                             (string-join
                              (list value (getenv name)) ":"))
                     process-environment))
        (pcase name ; Need some special handling.
          ("PATH"
           (setq-local exec-path
                       (append (split-string value ":")
                               exec-path))
           (eshell-set-path value)))))))

(defun guix-unset-buffer-environment ()
  "Unset buffer's `process-environment'."
  (interactive)
  (kill-local-variable 'process-environment)
  (kill-local-variable 'exec-path)
  (kill-local-variable 'Info-directory-list)
  (kill-local-variable 'eshell-path-env-list))

(defun guix--shell-get-directory ()
  "Get the current guix shell directory."
  (if (project-current)
      (project-root (project-current))
    default-directory))

(defun guix-update-buffer-dir-environment (&rest args)
  "Set the buffer environment according to the directory it is in.

ARGS are ignored."
  (ignore args)
  (when-let* ((profile (guix-get-directory-environment)))
    (guix-set-buffer-environment profile)))

(define-minor-mode guix-shell-mode
  "Set all the needed hooks and advice for Guix Shell to work."
  :group 'guix
  (cond (guix-shell-mode (guix-update-buffer-dir-environment)
                         (add-hook 'eshell-mode-hook 'guix-update-buffer-dir-environment)
                         (advice-add 'start-process :before 'guix-update-buffer-dir-environment)
                         (advice-add 'call-process :before 'guix-update-buffer-dir-environment))
        (t
         (guix-unset-buffer-environment)
         (remove-hook 'eshell-mode-hook 'guix-update-buffer-dir-environment)
         (advice-remove 'start-process #'guix-update-buffer-dir-environment)
         (advice-remove 'call-process #'guix-update-buffer-dir-environment))))

(define-globalized-minor-mode global-guix-shell-mode guix-shell-mode
  (lambda ()
    (when (guix-get-directory-environment)
      (guix-shell-mode)))
  :lighter (:eval (format " Guix-Shell[%s]" (if guix-shell-mode
                                                "on" "off"))))

(defun guix-shell-update-all-buffers ()
  "Update all buffers guix shell environments."
  (interactive)
  (mapcar (lambda (buff)
            (with-current-buffer buff
              (when (guix-get-directory-environment)
                (guix-unset-buffer-environment)
                (if guix-shell-mode
                    (guix-update-buffer-dir-environment)
                  (guix-shell-mode 1)))))
          (buffer-list)))

(defun guix-set-directory-environment (directory profile)
  "Set the DIRECTORY environment to PROFILE."
  (setq guix-shell-directory-alist (assoc-delete-all directory guix-shell-directory-alist))
  (push (cons (expand-file-name directory) profile)
        guix-shell-directory-alist)
  (guix-update-buffer-dir-environment))

(defun guix-get-directory-environment (&optional directory)
  "Get the DIRECTORY profile environment."
  (and-let* ((directory (or directory (guix--shell-get-directory)))
             (profiles (mapcar #'cdr
                               (seq-filter (lambda (item)
                                             (file-in-directory-p
                                              directory
                                              (expand-file-name (car item))))
                                           guix-shell-directory-alist)))
             (profile (car profiles)))))

(defun guix--shell-authorized-p (directory)
  "Check if DIRECTORY is already authorized."
  (let* ((directory (string-remove-suffix "/" (expand-file-name directory)))
         (authorized-directories-buff (find-file-noselect "~/.config/guix/shell-authorized-directories"))
         (directories (string-split (with-current-buffer authorized-directories-buff
                                      (buffer-substring-no-properties (point-min) (point-max)))
                                    "\n")))
    (member directory directories)))

;;;###autoload
(defun guix-shell (&optional packages)
  "Switch to a guix shell with PACKAGES for current project.

If a manifest.scm file exists in the project root, packages are ignored.

If not in a project, `default-directory' is considered the project root.
This can also be specified by supplying a prefix-argument."
  (interactive)
  (let* ((invoked-buffer (current-buffer))
         (directory (guix--shell-get-directory))
         (directory (if current-prefix-arg
                        (read-directory-name "Specify directory: " directory)
                      directory))
         (packages (or packages (if (not (file-exists-p (file-name-concat directory "manifest.scm")))
                                    (completing-read-multiple
                                     "Packages to add to the guix shell: "
                                     (guix-package-names))
                                  (when (and (not (guix--shell-authorized-p directory))
                                             (yes-or-no-p "Authorize this directory?"))
                                    (guix-shell-authorize directory)))))
         (guix-shell-command (if packages (format "guix shell %s -- printenv GUIX_ENVIRONMENT"
                                                  (string-join packages " "))
                               (when (guix--shell-authorized-p directory)
                                 (format "guix shell -m %s -- printenv GUIX_ENVIRONMENT"
                                         (file-name-concat directory "manifest.scm")))))
         (output-buffer (format "*guix-shell:%s*" directory))
         (error-buffer (format "*guix-shell-stderr:%s*" directory)))
    (when guix-shell-command
      (make-process :name "guix shell"
                    :buffer output-buffer
                    :sentinel (lambda (process status)
                                (if (string= status "finished\n")
                                    (with-current-buffer invoked-buffer
                                      (guix-set-directory-environment
                                       directory
                                       (with-current-buffer (process-buffer process)
                                         (goto-char (1- (point-max)))
                                         (thing-at-point 'filename t)))
                                      (guix-shell-update-all-buffers)
                                      (message "Guix shell prepared." ))
                                  (message "Guix shell failed.")))
                    :stderr error-buffer
                    :command (list "sh" "-c" guix-shell-command))
      (when (not global-guix-shell-mode) (global-guix-shell-mode)))))

;;;###autoload
(defun guix-shell-authorize (directory)
  "Authorize DIRECTORY so that Guix automatically loads the manifest.scm."
  (interactive (list (guix--shell-get-directory)))
  (when-let* ((directory (string-remove-suffix "/" (expand-file-name directory)))
              (shell-authorized-directories (find-file-noselect "~/.config/guix/shell-authorized-directories")))
    (with-current-buffer shell-authorized-directories
      (goto-char (point-max))
      (insert directory)
      (insert "\n")
      (save-buffer))))

;;;###autoload
(defun guix-shell-export-manifest (packages)
  "Export a manifest.scm file with PACKAGES in the current project."
  (interactive (list (completing-read-multiple
                      "Packages to add to the guix shell: "
                      (guix-package-names))))
  (let* ((directory (guix--shell-get-directory))
         (directory (string-remove-suffix "/" (expand-file-name directory)))
         (manifest (file-name-concat directory "manifest.scm"))
         (manifest-generator (format "guix shell --export-manifest %s > %s" (string-join packages " ") manifest)))
    (shell-command manifest-generator)
    (when (and (not (guix--shell-authorized-p directory))
               (yes-or-no-p "Authorize this directory?"))
      (guix-shell-authorize directory))))

(provide 'guix-shell)

;;; guix-shell.el ends here
