;;; guix-ui-store-item.el --- Interface for displaying store items  -*- lexical-binding: t -*-

;; Copyright © 2018 Alex Kost <alezost@gmail.com>

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

;; This file provides an interface to display store items in 'list' and
;; 'info' buffers.

;;; Code:

(require 'cl-lib)
(require 'ffap)
(require 'bui)
(require 'guix-package)
(require 'guix-guile)
(require 'guix-repl)
(require 'guix-misc)
(require 'guix-utils)
(require 'guix-auto-mode)  ; for regexps


;;; Misc functionality (move to "guix-store.el"?)

(defun guix-store-file-name-read ()
  "Read from minibuffer a store file name."
  (let* ((file (ffap-file-at-point))
         (file (and file
                    (string-match-p guix-store-directory file)
                    file)))
    ;; Read a string (not a file name), since using completions for
    ;; "/gnu/store" would probably be too much.
    (read-string "File from store: " file)))

(defvar guix-store-file-name-regexp
  (rx-to-string
   `(and ,guix-store-directory "/"
         (regexp ,guix-hash-regexp) "-"
         (group (* any)))
   t)
  "Regexp matching a string with store file name.
The first parenthesized group is the name itself (placed right
after the hash part).")

(defun guix-store-file-name< (a b)
  "Return non-nil if store file name A is less than B.
This is similar to `string<', except the '/gnu/store/...-' parts
of the file names are ignored."
  (cl-flet ((name (str)
              (and (string-match guix-store-file-name-regexp str)
                   (match-string 1 str))))
    (string-lessp (name a) (name b))))


;;; Common for both interfaces

(guix-define-groups store-item)

(bui-define-entry-type guix-store-item
  :message-function 'guix-store-item-message
  :titles '((id . "File name")
            (time . "Registration time")))

(defun guix-store-item-get-entries (search-type
                                    &optional search-values params)
  "Receive 'store-item' entries.
SEARCH-TYPE may be one of the following symbols: `id', `live',
`dead', `referrers', `references', `derivers', `requisites',
`failures'."
  (guix-eval-read
   (guix-make-guile-expression
    'store-item-sexps search-type search-values params)))

(defun guix-store-item-get-display (search-type &rest search-values)
  "Search for store items and show results."
  (apply #'bui-list-get-display-entries
         'guix-store-item search-type search-values))

(defun guix-store-item-message (entries search-type &rest search-values)
  "Display a message after showing store item ENTRIES."
  (let ((count (length entries))
        (val (car search-values)))
    (cl-case search-type
      ((id path)
       (cl-case count
         (0 (message "No info on the store item(s) found."))
         (1 (message "Store item '%s'." val))))
      (live (message "%d live store items." count))
      (dead (message "%d dead store items." count))
      (failures
       (cl-case count
         (0 (message "No failures found."))
         (1 (message "A single failure found."))
         (t (message "%d failures found." count))))
      (t
       (let ((type (symbol-name search-type)))
         (cl-case count
           (0 (message "No %s of '%s' found." type val))
           (1 (message "A single %s of '%s'."
                       ;; Remove the trailing "s" from the search type
                       ;; ("derivers" -> "deriver").
                       (substring type 0 (1- (length type)))
                       val))
           (t (message "%d %s of '%s'." count type val))))))))


;;; Store item 'info'

(bui-define-interface guix-store-item info
  :mode-name "Store-Item-Info"
  :buffer-name "*Guix Store Item Info*"
  :get-entries-function 'guix-store-item-info-get-entries
  :format '((id nil (format bui-file))
            nil
            guix-store-item-info-insert-buttons
            (size format guix-store-item-info-insert-size)
            (time format (time))
            (hash format (format))
            (derivers simple (guix-info-insert-store-items))
            (references simple (guix-info-insert-store-items))))

(defvar guix-store-item-info-required-params
  '(id)
  "List of the required 'store-item' parameters.
These parameters are received from the Scheme side
along with the displayed parameters.

Do not remove `id' from this info as it is required for
identifying an entry.")

(defvar guix-store-item-info-buttons
  '(requisites referrers references derivers)
  "List of search types for buttons displayed in info buffer.")

(defun guix-store-item-info-get-entries (search-type &rest search-values)
  "Return 'store-item' entries for displaying them in 'info' buffer."
  (guix-store-item-get-entries
   search-type search-values
   (cl-union guix-store-item-info-required-params
             (bui-info-displayed-params 'guix-store-item))))

(defun guix-store-item-info-insert-buttons (entry)
  "Insert various buttons for store item ENTRY at point."
  (let ((file-name (bui-entry-id entry)))
    (bui-mapinsert
     (lambda (type)
       (let ((type-str (symbol-name type)))
         (bui-insert-action-button
          (capitalize type-str)
          (lambda (btn)
            (guix-store-item-get-display (button-get btn 'search-type)
                                         (button-get btn 'file-name)))
          (format "Show %s of %s" type-str file-name)
          'search-type type
          'file-name file-name)))
     guix-store-item-info-buttons
     (bui-get-indent)
     :column (bui-fill-column)))
  (bui-newline))

(defun guix-store-item-info-insert-size (size entry)
  "Insert SIZE of the store item ENTRY at point."
  (insert (format "%s (%d bytes)"
                  (file-size-human-readable size)
                  size))
  (bui-insert-indent)
  (let ((file-name (bui-entry-id entry)))
    (bui-insert-action-button
     "Size"
     (lambda (btn)
       (guix-package-size (button-get btn 'file-name)
                          (guix-read-package-size-type)))
     (format "Show full size info on %s" file-name)
     'file-name file-name)))

(defun guix-info-insert-store-item (file-name)
  "Insert store FILE-NAME at point."
  (bui-insert-button file-name 'bui-file)
  (bui-insert-indent)
  (bui-insert-action-button
   "Store item"
   (lambda (btn)
     (guix-store-item (button-get btn 'file-name)))
   (format "Show more info on %s" file-name)
   'file-name file-name))

(defun guix-info-insert-store-items (file-names)
  "Insert store FILE-NAMES at point.
FILE-NAMES can be a list or a single string."
  (bui-insert-non-nil file-names
    (dolist (file-name (guix-list-maybe file-names))
      (bui-newline)
      (bui-insert-indent)
      (guix-info-insert-store-item file-name))))


;;; Store item 'list'

(bui-define-interface guix-store-item list
  :mode-name "Store-Item-List"
  :buffer-name "*Guix Store Items*"
  :get-entries-function 'guix-store-item-list-get-entries
  :describe-function 'guix-store-item-list-describe
  :format '((id nil 65 guix-store-item-list-sort-file-names-0)
            (size nil 20 bui-list-sort-numerically-1 :right-align t))
  :hint 'guix-store-item-list-hint
  :sort-key '(size . t)
  :marks '((delete . ?D)))

(defvar guix-store-item-list-required-params
  '(id)
  "List of the required 'store-item' parameters.
These parameters are received from the Scheme side
along with the displayed parameters.

Do not remove `id' from this list as it is required for
identifying an entry.")

(let ((map guix-store-item-list-mode-map))
  (define-key map (kbd "e") 'guix-store-item-list-edit)
  (define-key map (kbd "d") 'guix-store-item-list-mark-delete)
  (define-key map (kbd "x") 'guix-store-item-list-execute))

(defvar guix-store-item-list-default-hint
  '(("\\[guix-store-item-list-edit]") " go to the current store item;\n"
    ("\\[guix-store-item-list-mark-delete]") " mark for deletion; "
    ("\\[guix-store-item-list-execute]") " execute operation (deletions);\n"))

(defun guix-store-item-list-hint ()
  (bui-format-hints
   guix-store-item-list-default-hint
   (bui-default-hint)))

(defun guix-store-item-list-get-entries (search-type &rest search-values)
  "Return 'store-item' entries for displaying them in 'list' buffer."
  (guix-store-item-get-entries
   search-type search-values
   (cl-union guix-store-item-list-required-params
             (bui-list-displayed-params 'guix-store-item))))

(defun guix-store-item-list-sort-file-names-0 (a b)
  "Compare column 0 of tabulated entries A and B numerically.
This function is used for sort predicates for `tabulated-list-format'.
Return non-nil, if B is bigger than A."
  (cl-flet ((name (entry) (aref (cadr entry) 0)))
    (guix-store-file-name< (name a) (name b))))

(defun guix-store-item-list-describe (&rest ids)
  "Describe store-items with IDS (list of identifiers)."
  (bui-get-display-entries 'guix-store-item 'info (cons 'id ids)))

(defun guix-store-item-list-edit ()
  "Go to the current store item."
  (interactive)
  (guix-find-file (bui-list-current-id)))

(defun guix-store-item-list-mark-delete (&optional arg)
  "Mark the current store-item for deletion and move to the next line.
With ARG, mark all store-items for deletion."
  (interactive "P")
  (if arg
      (bui-list-mark-all 'delete)
    (bui-list--mark 'delete t)))

(defun guix-store-item-list-execute ()
  "Delete store items marked with '\\[guix-store-item-list-mark-delete]'."
  (interactive)
  (let ((marked (bui-list-get-marked-id-list 'delete)))
    (or marked
        (user-error "No store items marked for deletion"))
    (when (or (not guix-operation-confirm)
              (y-or-n-p
               (let ((count (length marked)))
                 (if (> count 1)
                     (format "Try to delete these %d store items? " count)
                   (format "Try to delete store item '%s'? "
                           (car marked))))))
      (guix-eval-in-repl
       (apply #'guix-make-guile-expression
              'guix-command "gc" "--delete" marked)
       (current-buffer)))))


;;; Interactive commands

;;;###autoload
(defun guix-store-item (&rest file-names)
  "Display store items with FILE-NAMES.
Interactively, prompt for a single file name."
  (interactive (list (guix-store-file-name-read)))
  (apply #'guix-store-item-get-display 'id file-names))

;;;###autoload
(defun guix-store-item-referrers (file-name)
  "Display referrers of the FILE-NAME store item.
This is analogous to 'guix gc --referrers FILE-NAME' shell
command.  See Info node `(guix) Invoking guix gc'."
  (interactive (list (guix-store-file-name-read)))
  (guix-store-item-get-display 'referrers file-name))

;;;###autoload
(defun guix-store-item-references (file-name)
  "Display references of the FILE-NAME store item.
This is analogous to 'guix gc --references FILE-NAME' shell
command.  See Info node `(guix) Invoking guix gc'."
  (interactive (list (guix-store-file-name-read)))
  (guix-store-item-get-display 'references file-name))

;;;###autoload
(defun guix-store-item-requisites (file-name)
  "Display requisites of the FILE-NAME store item.
This is analogous to 'guix gc --requisites FILE-NAME' shell
command.  See Info node `(guix) Invoking guix gc'."
  (interactive (list (guix-store-file-name-read)))
  (guix-store-item-get-display 'requisites file-name))

;;;###autoload
(defun guix-store-item-derivers (file-name)
  "Display derivers of the FILE-NAME store item.
This is analogous to 'guix gc --derivers FILE-NAME' shell
command.  See Info node `(guix) Invoking guix gc'."
  (interactive (list (guix-store-file-name-read)))
  (guix-store-item-get-display 'derivers file-name))

;;;###autoload
(defun guix-store-failures ()
  "Display store items corresponding to cached build failures.
This is analogous to 'guix gc --list-failures' shell command.
See Info node `(guix) Invoking guix gc'."
  (interactive)
  (guix-store-item-get-display 'failures))

;;;###autoload
(defun guix-store-live-items ()
  "Display live store items.
This is analogous to 'guix gc --list-live' shell command.
See Info node `(guix) Invoking guix gc'."
  (interactive)
  (guix-store-item-get-display 'live))

;;;###autoload
(defun guix-store-dead-items ()
  "Display dead store items.
This is analogous to 'guix gc --list-dead' shell command.
See Info node `(guix) Invoking guix gc'."
  (interactive)
  (guix-store-item-get-display 'dead))

(provide 'guix-ui-store-item)

;;; guix-ui-store-item.el ends here
