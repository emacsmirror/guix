;;; guix-popup.el --- Popup interface for Emacs-Guix commands  -*- lexical-binding: t -*-

;; Copyright © 2018-2019, 2021 Alex Kost <alezost@gmail.com>

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

;; This file provides popup interface (using `transient' library) for
;; Emacs-Guix commands.

;;; Code:

(require 'transient)
(require 'guix-profiles)

(defgroup guix-popup nil
  "Popup interface for Emacs-Guix commands."
  :group 'guix)

;;;###autoload (autoload 'guix-popup "guix-popup" nil t)
(transient-define-prefix guix-popup ()
  "Show popup buffer for Emacs-Guix commands."
  ["Sub-popups"
   ("p" "packages"              guix-package-popup)
   ("P" "profiles"              guix-profile-popup)
   ("s" "services"              guix-service-popup)
   ("y" "system commands"       guix-system-popup)
   ("l" "package licenses"      guix-license-popup)
   ("S" "store"                 guix-store-popup)
   ("m" "major/minor modes"     guix-mode-popup)
   ("c" "guix shell commands"   guix-command)]
  ["Miscellaneous commands"
   ("H" "calculate file hash"   guix-hash)
   ("E" "set Emacs environment" guix-set-emacs-environment)]
  ["Auxiliary commands"
   [("a" "about"                guix-about)
    ("i" "info manual"          guix-info)
    ("b" "switch to buffer"     guix-switch-to-buffer)]
   [("h" "help (\"refcard\")"   guix-help)
    ("v" "version"              guix-version)
    ("B" "report guix bug"      guix-report-bug)]])

;;;###autoload
(defalias 'guix #'guix-popup
  "Popup interface for Emacs-Guix commands.")


;;; Sub-popups

(transient-define-infix guix-set-current-profile-from-popup ()
  "Set `guix-current-profile' from a popup buffer."
  :class 'transient-lisp-variable
  :variable 'guix-current-profile
  :reader (lambda (_prompt default _history)
	    (guix-read-package-profile default)))

(transient-define-prefix guix-package-popup ()
  "Show popup buffer for package commands."
  ["Variables"
   ("p" guix-set-current-profile-from-popup)]
  ["Show packages"
   [("a" "all"        guix-all-packages)
    ("o" "obsolete"   guix-obsolete-packages)
    ("h" "hidden"     guix-hidden-packages)]
   [("i" "installed"  guix-installed-packages)
    ("s" "superseded" guix-superseded-packages)]]
  ["Search for packages"
   ("n" "by name" guix-packages-by-name)
   ("N" "by regexp (in name only)" guix-packages-by-name-regexp)
   ("r" "by regexp (in name, synopsis, description)" guix-packages-by-regexp)
   ("L" "by location" guix-packages-by-location)
   ("c" "by license" guix-packages-by-license)
   ("d" "depending on other package(s)" guix-dependent-packages)
   ("f" "packages from file" guix-package-from-file)
   ("y" "packages from system config file"
    guix-packages-from-system-config-file)]
  ["Package locations"
   ("l" "show package locations" guix-package-locations)
   ("e" "\"edit\" package (find package definition)"
    guix-find-package-definition)
   ("F" "find location file" guix-find-package-location-file)]
  ["Other commands"
   [("g" "package graph" guix-package-graph)
    ("t" "package lint"  guix-package-lint)
    ("T" "total number of packages" guix-number-of-packages)]
   [("z" "package size"  guix-package-size)
    ("C" "lint checkers" guix-lint-checkers)]])

(transient-define-prefix guix-profile-popup ()
  "Show popup buffer for profiles and generations commands."
  ["Variables"
   ("p" guix-set-current-profile-from-popup)]
  ["Show profiles"
   ("a" "all"     guix-profiles)
   ("s" "system"  guix-system-profile)
   ("h" "home"    guix-home-profile)
   ("c" "current" guix-current-profile)]
  ["Show generations (of the current profile)"
   ("g" "all"     guix-generations)
   ("t" "by time" guix-generations-by-time)
   ("l" "last"    guix-last-generations)]
  ["Other commands"
   ("M" "apply manifest to the current profile" guix-apply-manifest)])

(transient-define-prefix guix-service-popup ()
  "Show popup buffer for service commands."
  ["Show services"
   ("s" "all system services" guix-all-services)
   ("h" "all home services"   guix-all-home-services)
   ("d" "default"             guix-default-services)
   ("n" "by name"             guix-services-by-name)
   ("r" "by regexp"           guix-services-by-regexp)
   ("L" "by location"         guix-services-by-location)
   ("y" "services from system config file"
    guix-services-from-system-config-file)]
  ["Service locations"
   ("l" "show service locations" guix-service-locations)
   ("e" "\"edit\" service (find service definition)"
    guix-find-service-definition)
   ("F" "find location file" guix-find-service-location-file)])

(transient-define-prefix guix-system-popup ()
  "Show popup buffer for system commands."
  ["From system profile"
   ("p" "packages"            guix-installed-system-packages)
   ("P" "profile"             guix-system-profile)
   ("g" "all generations"     guix-system-generations)
   ("t" "generations by time" guix-system-generations-by-time)
   ("l" "last generations"    guix-last-system-generations)]
  ["From system configuration file"
   ("y" "system"              guix-system-from-file)
   ("k" "packages"            guix-packages-from-system-config-file)
   ("s" "services"            guix-services-from-system-config-file)])

(transient-define-prefix guix-license-popup ()
  "Show popup buffer for license commands."
  [("a" "show all package licenses" guix-licenses)
   ("u" "browse license URL" guix-browse-license-url)
   ("e" "\"edit\" license (find license definition)"
    guix-find-license-definition)
   ("F" "find license location file" guix-find-license-location-file)])

(transient-define-prefix guix-store-popup ()
  "Show popup buffer for store commands."
  ["Show store items"
   [("l" "live items"  guix-store-live-items)
    ("e" "failures"    guix-store-failures)
    ("D" "derivers"    guix-store-item-derivers)
    ("f" "referrers"   guix-store-item-referrers)]
   [("d" "dead items"  guix-store-dead-items)
    ("i" "single item" guix-store-item)
    ("R" "requisites"  guix-store-item-requisites)
    ("F" "references"  guix-store-item-references)]])

(transient-define-prefix guix-mode-popup ()
  "Show popup buffer for Emacs-Guix major/minor modes."
  ["Modes"
   ("p" "guix-prettify-mode"        guix-prettify-mode)
   ("P" "global-guix-prettify-mode" global-guix-prettify-mode)
   ("b" "guix-build-log-minor-mode" guix-build-log-minor-mode)
   ("B" "guix-build-log-mode"       guix-build-log-mode)
   ("d" "guix-devel-mode"           guix-devel-mode)
   ("D" "guix-derivation-mode"      guix-derivation-mode)
   ("e" "guix-env-var-mode"         guix-env-var-mode)])

(provide 'guix-popup)

;;; guix-popup.el ends here
