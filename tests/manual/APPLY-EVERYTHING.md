# Manual verifier — APPLY-EVERYTHING.ps1

Pester (tests/APPLY-EVERYTHING.Tests.ps1) covers the AST surface:
param shape, `-IncludeSecurityTradeoffs` gate plumbing, anti-cheat
warning text, phase headings. Below is what must run on Windows.

## Pre-conditions

- Fresh Windows 11 24H2 install, ideally in a VM with a snapshot.
- Local Administrator account.
- Repo cloned to `C:\Repo\Win11GamingToolkit` (or adjust paths).
- `PowerShell 7.4+` installed (`winget install Microsoft.PowerShell`).

## Default run (no Security Trade-offs)

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File C:\Repo\...\APPLY-EVERYTHING.ps1` | Header prints, UI-Confirm pre-prompt. Press Enter. |
| 2 | Phases 1–8 run | Each `Run-Step` line ends with `Done` or a documented `Skipped` reason. |
| 3 | Phase 9 heading appears | Body output: `Skipped — pass -IncludeSecurityTradeoffs to include`. **NO registry/service writes for WU.** |
| 4 | Phase 10 heading appears | Same skip pattern. **NO HVCI/VBS/LSA writes.** |
| 5 | Phases 11–14 run | Customization, Defender exclusions, debloat, temp cleanup all proceed. Phase 13 uses `Get-ToolkitDebloatCatalog` (same list as `debloat.ps1`, including Outlook for Windows and the Xbox App). |
| 6 | `Get-ToolkitManifest` | `state.steps['phase9-windows-update'].status` = `skipped`. Same for `phase10-security-tradeoffs`. |
| 7 | `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue` | `Enabled` value unchanged (HVCI is NOT disabled by default run). |
| 8 | Summary | Does **not** print that Windows Update suppression / security trade-offs ran. |
| 9 | After Phase 14, before reboot: `Get-Service wuauserv` | `Status` is `Running`. `StartType` is unchanged (not `Disabled`). Cache cleanup stops `wuauserv` only long enough to delete `SoftwareDistribution\Download`, then starts it again. |

## Run with -IncludeSecurityTradeoffs

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File ...\APPLY-EVERYTHING.ps1 -IncludeSecurityTradeoffs` | Standard pre-confirm, then **second** UI-Confirm explicitly listing BattlEye/EAC + Windows-Update warnings. Press Enter. |
| 2 | Phase 9 runs | wuauserv / UsoSvc / DoSvc disabled. WaaSMedicSvc warning may appear on 24H2+ (expected — DACL block). |
| 2b | After Phase 14 | `wuauserv` stays `Stopped` and `StartType` stays `Disabled`. Phase 14 prints `Leaving wuauserv stopped: Phase 9 disabled Windows Update.` It does not call `Start-Service` for that service. |
| 3 | Phase 10 runs | Red `[!] ANTI-CHEAT` lines appear before any Run-Step. Then HVCI, VBS, LSA, Spectre keys written. |
| 4 | Summary | Prints that Windows Update suppression and security trade-off tweaks ran. |
| 5 | `Get-ToolkitManifest` | `state.registry['reg:HVCIEnabled'].before.value` captured. |
| 6 | Reboot. Try to launch R6 Siege or any BattlEye-protected title. | Title launches OR fails — both are valid; the warning told you it might. |
| 7 | `pwsh -File ...\REVERT-EVERYTHING.ps1` | All tradeoff writes restored to captured before-state. |
| 8 | Reboot. Verify HVCI/VBS back on via `msinfo32` → Virtualization-based security = Running. | Yes. |

## Verify note — Phase 13 debloat (runtime-pending)

Code-complete, runtime-pending. On a Windows 11 VM:

- Phase 13 does not keep a private package list. It removes every row from `lib/debloat-catalog.ps1`.
- If `Remove-AppxProvisionedPackage` fails, that Appx name is absent from `state.packages.provisionedRemoved`.
- `restore-debloat.ps1` reinstalls with the catalog winget id (`9NFFX4SZZ23L` for Cortana, `Microsoft.Teams.Free` for personal Teams), not the Appx name.

## Idempotency

| # | Action | Expected |
|---|--------|----------|
| 1 | Run APPLY-EVERYTHING twice in a row (no reboot between) | Second run logs many `reg-skip-idempotent` lines via Write-ToolkitLog. **No new manifest entries** — re-run is a no-op for state already at target. |
| 2 | `Get-ToolkitLog -Tail 100` | Should show the skip-idempotent lines from the second run. |

## -WhatIf propagation

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File ...\APPLY-EVERYTHING.ps1 -WhatIf` | Every Set-TrackedRegistry / Set-TrackedService prints `What if: Performing the operation "Set value..." on target "HKLM:\..."`. **No actual writes.** |
| 2 | `Get-ToolkitManifest` after | Manifest is unchanged from pre-run. |
| 3 | `Get-ToolkitLog -Tail 50` | Many `reg-skip-whatif` / `svc-skip-whatif` lines logged. |

## Failure modes to flag

- If Phase 9 or 10 runs without `-IncludeSecurityTradeoffs` → **regression of CURSOR-AUDIT #1**. Open issue, link the commit since `f8b1fc3`.
- If `-WhatIf` proceeds with actual writes → ShouldProcess gate broken in `Set-ToolkitRegistryValue`/`Set-ToolkitServiceStartMode`. Check `lib/toolkit-state.ps1` against `eacd601`.
- If anti-cheat warning text is missing the words "BattlEye" or "EAC" → **regression of CURSOR-AUDIT #2 / CLAUDE.md anti-cheat convention**.
- If a default run (no `-IncludeSecurityTradeoffs`) leaves `(Get-Service wuauserv).Status` as `Stopped` while `StartType` is not `Disabled` → Phase 14 cache cleanup stopped Windows Update and did not start it again.
- If a `-IncludeSecurityTradeoffs` run starts `wuauserv` after Phase 9 set `StartType` to `Disabled` → Phase 14 ignored the Phase 9 disable. Verify prints `Phase 9 disabled wuauserv. Phase 14 leaves that service stopped after cache cleanup.` when the manifest records `service:wuauserv` as applied.
