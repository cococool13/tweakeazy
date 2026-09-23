# Manual verifier — REVERT-EVERYTHING.ps1

Pester (tests/REVERT-EVERYTHING.Tests.ps1) covers the surface
(phase headings, Restore-Toolkit* call presence, manifest-prefer-then-
fallback pattern). Below is what must run on Windows.

## Pre-conditions

- Same Windows 11 24H2 VM as APPLY-EVERYTHING.md.
- APPLY-EVERYTHING.ps1 has been run (so a manifest exists).
  Ideally with **and** without `-IncludeSecurityTradeoffs` covered
  in separate VM snapshots.

## Manifest-driven restore

| # | Action | Expected |
|---|--------|----------|
| 1 | `pwsh -File ...\REVERT-EVERYTHING.ps1` | Header, pre-confirm. Press Enter. |
| 2 | Phases 1–7+ run | Each Restoring line ends `Done` or documented skip. |
| 3 | `Get-ToolkitManifest` after | `state.registry` entries unchanged (manifest is the audit trail, revert reads it but doesn't clear it). |
| 4 | Spot-check a key that was set by APPLY: `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name PowerThrottlingOff -ErrorAction SilentlyContinue` | Value matches the captured `before` from the manifest (typically null/absent for these toolkit-only keys). |

## Nagle revert (CURSOR-AUDIT #5)

Manifest-prefer-then-blind-fallback pattern. Critical to test both
sides — pure-manifest works, AND the fallback works when the user
ran a legacy non-tracked apply path.

| # | Action | Expected |
|---|--------|----------|
| 1 | After APPLY ran: `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\<guid>' -Name TcpAckFrequency -ErrorAction SilentlyContinue` | Value = 1 on every active DHCP interface. |
| 2 | Run REVERT-EVERYTHING.ps1 | Phase 7 "Removing Nagle overrides" → Done. |
| 3 | Same `Get-ItemProperty` | Value should be null/absent (or the captured before value, if non-default). |
| 4 | Manually pollute an interface: `Set-ItemProperty <interface> TcpAckFrequency 1 -Type DWord -Force` (simulates legacy apply). | Set. |
| 5 | Re-run REVERT-EVERYTHING.ps1. | Blind-remove fallback should clear the value even without manifest. |

## Service revert

| # | Action | Expected |
|---|--------|----------|
| 1 | After APPLY (with `-IncludeSecurityTradeoffs`): `(Get-Service wuauserv).StartType` | `Disabled` |
| 2 | Run REVERT-EVERYTHING.ps1 | Phase 3 restores tracked services. |
| 3 | `(Get-Service wuauserv).StartType` | Back to captured before-state (typically `Manual` or `Automatic` on a fresh Win11). |

## DNS revert

| # | Action | Expected |
|---|--------|----------|
| 1 | After APPLY: `Get-DnsClientServerAddress -InterfaceIndex <up-adapter>` | Cloudflare 1.1.1.1/1.0.0.1/2606:4700:4700::1111/1001 |
| 2 | Run REVERT-EVERYTHING.ps1 | Phase 7 "Restoring DNS" → Done. |
| 3 | Same `Get-DnsClientServerAddress` | Back to original (DHCP-provided or user-set). |

## Empty-manifest case

Tests the defaults fallback when a user runs REVERT without ever
having APPLY'd.

| # | Action | Expected |
|---|--------|----------|
| 1 | Wipe manifest: `Remove-Item "$env:ProgramData\Win11GamingToolkit\state\manifest.json"` | Gone. |
| 2 | Run REVERT-EVERYTHING.ps1 | Should NOT throw. Logs many `Skipped (no manifest entry)` and applies the defaults-fallback path. |
| 3 | System state | Unchanged from pre-REVERT (defaults fallback shouldn't push values for keys that weren't toolkit-set). |

## Visual effects and sound scheme (checklist 12.5)

Apply writes `UserPreferencesMask`, `FontSmoothing`, `AutoGameModeEnabled`, and empty per-event `.Current` values. Revert writes the stock defaults for the first three and copies each Windows Default scheme sibling back onto `.Current`.

Code-complete, runtime-pending. On a Windows 11 VM after Apply, then Revert:

| # | Action | Expected |
|---|--------|----------|
| 1 | `reg query "HKCU\Control Panel\Desktop" /v UserPreferencesMask` | `REG_BINARY` `9E1E078012000000`. Not `9012038012000000`. |
| 2 | `reg query "HKCU\Control Panel\Desktop" /v FontSmoothing` | `REG_SZ` `2`. |
| 3 | `reg query "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled` | `REG_DWORD` `0x1`. |
| 4 | `reg query "HKCU\AppEvents\Schemes\Apps\.Default\DeviceConnect\.Current"` | Default value equals `DeviceConnect\.Default` (typically a wav path), not `""`. Repeat for `.Default`, `DeviceDisconnect`, `DeviceFail`, `MailBeep`, `Notification.Default`, `SystemAsterisk`, `SystemExclamation`, `SystemNotification`, `WindowsUAC`. |

These four are stock-default writes, same contract as the other untracked Phase 4 `reg add` fallbacks. They do not read a manifest `before` value.

## Failure modes to flag

- If `Restore-ToolkitRegistryValue` writes a wrong value → check the manifest `before` capture in `lib/toolkit-state.ps1` `Get-ToolkitRegistryState`.
- If service revert leaves services at the toolkit-disabled state → `Set-ToolkitServiceStartMode` captured wrong `before` or `Restore-ToolkitServiceStartMode` is missing the actual `sc.exe config` call.
- If DNS revert restores only one address family (v4 OR v6, not both) → CODEX audit regression. Both families must round-trip.
