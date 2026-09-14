============================================================
4 services/individual/ — Offline Files / Sync Center only
============================================================

Raw per-service *-disable.bat / *-enable.bat toggles are gone.
They bypassed the toolkit manifest at
%ProgramData%\Win11GamingToolkit\state\manifest.json.

TRACKED PATHS:
  - Disable: 4 services\disable-services.ps1   (smart preview + apply)
  - Revert:  4 services\enable-services.ps1    (manifest-driven restore)
  - Full:    REVERT-EVERYTHING.ps1

This folder keeps only the Offline Files / Sync Center pair:
  - mobsync-disable.ps1 / mobsync-enable.ps1   (tracked)
  - mobsync-disable.bat / mobsync-enable.bat   (wrappers that call the .ps1)

Use disable-services.ps1 unless you only want CscService.
