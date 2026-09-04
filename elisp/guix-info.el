;;; guix-info.el --- Useful helpers for Guix Info manuals  -*- lexical-binding: t -*-

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

;; This package provides some helpers for Guix adjacent Info manuals.
;;
;; Since the package alters the state of the 'info.el' there are no autoload
;; defined.  In order to use it require it in your 'init.el':
;;
;; (require 'guix-info)
;;
;; Or interactively: 'M-x load-library RET guix-info RET'

;;; Code:

(require 'browse-url)
(require 'cl-macs)
(require 'info)
(require 'seq)

(setq Info-url-alist
      (seq-union
       Info-url-alist
       '((("guix") .
          "https://guix.gnu.org/manual/devel/en/html_node/%e")
         (("bash" "binutils" "cuirass" "emacs-guix" "fibers" "gash" "gcrypt"
           "gdb" "geiser" "grub" "guile" "guile-avahi" "guile-gcrypt"
           "guile-gnutls" "guile-lib" "guile-netlink" "guile-ssh" "haunt"
           "inetutils" "libc" "mes" "nyacc" "nyacc-c99-ug" "r5rs" "recutils"
           "shepherd")
          . "https://doc.guix.gnu.org/%m/latest/en/html_node/%e"))))

(defun guix-info-copy-node-web (node)
  "Copy URL to node into the clipboard.

This uses `Info-url-for-node' to determine the URL that corresponds to NODE."
  (interactive (list Info-current-node)
               Info-mode)
  ;; HACK: dynamically redefine `browse-url-button-open-url' to make
  ;; `Info-goto-node-web' past the URL into the kill-ring rather than navigating
  ;; to it.
  (cl-letf (((symbol-function #'browse-url-button-open-url)
             #'(lambda (url)
                 (kill-new url)
                 (message "%s" url))))
    (Info-goto-node-web node)))

(define-key Info-mode-map (kbd "C") #'guix-info-copy-node-web)
(define-key Info-mode-map (kbd "W") #'guix-info-copy-node-web)

(provide 'guix-info)

;;; guix-info.el ends here
