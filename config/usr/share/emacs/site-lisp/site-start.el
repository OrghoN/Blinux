;;; site-start.el --- Blinux site-wide Emacs startup  -*- lexical-binding: t; -*-

;;; Commentary:
;; Loads every file in site-start.d/ in name order.  Blinux packages drop
;; their startup snippets there (Emacspeak: 50-emacspeak.el, AsTeR:
;; 60-aster.el).  Set BLINUX_NO_SITE_START=1 to skip all of them.

;;; Code:

(unless (getenv "BLINUX_NO_SITE_START")
  (let ((dir (expand-file-name "site-start.d"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name)))))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.el\\'"))
        (condition-case err
            (load file nil t)
          (error (message "Blinux: error loading %s: %S" file err)))))))

;;; site-start.el ends here
