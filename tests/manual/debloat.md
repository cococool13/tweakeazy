# Manual verifier — 9 cleanup/debloat.ps1

Pester (tests/9-cleanup/debloat.Tests.ps1) covers the AST surface
including the f71d130 regression check that `$neverRemove` is
enforced. Below is what must run on Windows.

## Pre-conditions

- Fresh Windows 11 24H2 VM with a snapshot you can revert to.
- All bloatware apps from `$appsToRemove` still installed
  (i.e. user hasn't manually purged them already).
- Microsoft.WindowsStore, Microsoft.DesktopAppInstaller, Photos,
  Calculator, Terminal all present.

## $neverRemove safety enforcement

The bug in f71d130 was that the safety list was declared but the
foreach loop didn't actually check it. This test confirms the fix
still holds.

| # | Action | Expected |
|---|--------|----------|
| 1 | Temporarily edit `$appsToRemove` to include `Microsoft.WindowsStore` (DO NOT COMMIT THIS) | Save the file. |
| 2 | `pwsh -File ...\9 cleanup\debloat.ps1` | Scan output shows `[SAFETY] Skipping Microsoft.WindowsStore (in NEVER-REMOVE list)` in red. |
| 3 | `Get-AppxPackage Microsoft.WindowsStore` | Still present (NOT removed). |
| 4 | `Get-ToolkitManifest` → `state.packages.removed` | Does NOT contain Microsoft.WindowsStore. |
| 5 | **Revert the file edit.** | Restored. |

## Standard run

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File ...\9 cleanup\debloat.ps1` | Scan, preview list, pre-confirm. Press Enter. |
| 2 | Each `[N/total] <appname>...` line | Ends `Removed` for present apps, `Already gone` for ones the user purged. |
| 3 | After completion: `Get-AppxPackage Microsoft.BingNews` | Empty (removed). |
| 4 | `Get-ToolkitManifest` → `state.packages.removed` | Lists every successfully removed package. |
| 5 | `Get-ToolkitManifest` → `state.packages.provisionedRemoved` | Lists provisioned removals (per-image, prevents reinstall on new users). |

## Restore via pair script

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File ...\9 cleanup\restore-debloat.ps1` | Reads manifest, lists candidates, pre-confirm. |
| 2 | Per app: winget install with `--exact --id` set to the mapped id and `--source` set to msstore or winget | Cortana uses `9NFFX4SZZ23L`. Personal Teams uses `Microsoft.Teams.Free`. The Appx names are not passed to `--id`. |
| 3 | `Get-AppxPackage Microsoft.BingNews` | Reappears for the per-user install path. |
| 4 | `Get-ToolkitManifest` → `state.steps['debloat-restore']` | Records installed-count vs failed-count. |

## Idempotency

| # | Action | Expected |
|---|--------|----------|
| 1 | After a successful run, re-run debloat.ps1 | Scan shows all apps as `[GONE]`. Script exits with `All bloatware already removed. Nothing to do.` |

## Verify note (runtime-pending)

Code-complete, runtime-pending. Pester covers the catalog, the map, and
the "record only after success" helper. This checklist is the Windows gate.
Do not mark the change tested until the rows below have been run.

| # | Action | Expected |
|---|--------|----------|
| 1 | Compare `Get-ToolkitDebloatCatalog` with Apply All phase 13 and `debloat.ps1` | Both call that function. The list includes `Microsoft.OutlookForWindows` and `Microsoft.GamingApp`. Neither script has its own package array. |
| 2 | Remove a provisioned package, then force `Remove-AppxProvisionedPackage` to fail (for example, a package that refuses removal) and re-run | `state.packages.provisionedRemoved` gains a name only when removal succeeded. A failed remove is not recorded. |
| 3 | `restore-debloat.ps1` after Cortana and personal Teams were recorded | The winget line is `--id 9NFFX4SZZ23L --source msstore` for Cortana and `--id Microsoft.Teams.Free --source winget` for Teams. The Appx names are not passed to `--id`. |

## Failure modes to flag

- If any critically-protected app (Store, AppInstaller, Photos,
  Calculator, Terminal) is removed → **`$neverRemove` enforcement
  regression** (f71d130). Open issue immediately, revert the
  package via System Restore / image reimage, link the SHA.
- If `Record-ToolkitPackageRemoval` doesn't fire → restore-debloat.ps1
  has nothing to read; the user is stuck. Manifest is the audit
  trail; if it's empty after a Remove-AppxPackage call, the lib
  helper is broken.
