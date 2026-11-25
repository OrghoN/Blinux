;;; 50-emacspeak.el --- Load Emacspeak at startup (Blinux)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded by Blinux's site-start.el.  Starts Emacspeak for every user, unless:
;; - BLINUX_NO_EMACSPEAK is set, or
;; - the user's own init file loads emacspeak-setup.el itself (the author's
;;   dotfiles do), so it isn't loaded twice.

;;; Code:

(defun blinux--user-init-loads-emacspeak-p ()
  "Non-nil if the user's init file already loads emacspeak-setup."
  (seq-some
   (lambda (file)
     (and (file-readable-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (re-search-forward "emacspeak-setup" nil t))))
   (list (expand-file-name "~/.emacs")
         (expand-file-name "~/.emacs.el")
         (expand-file-name "init.el" (or (getenv "XDG_CONFIG_HOME") "~/.config/emacs"))
         (expand-file-name "~/.emacs.d/init.el"))))

(unless (or (getenv "BLINUX_NO_EMACSPEAK")
            noninteractive
            (featurep 'emacspeak)
            (blinux--user-init-loads-emacspeak-p))
  (unless (getenv "DTK_PROGRAM") (setenv "DTK_PROGRAM" "espeak"))
  (load-file "/opt/emacspeak/lisp/emacspeak-setup.el"))

;;; 50-emacspeak.el ends here
