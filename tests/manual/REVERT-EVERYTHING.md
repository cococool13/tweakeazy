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

## Captured HKLM ids (manifest before hardcoded default)

These five values are written with `Set-ToolkitRegistryValue` and must
come back from `state.registry[<id>].before`. The hardcoded default
runs only when that id is absent. `HiberbootEnabled` and
`PowerThrottlingOff` use one id (`reg:`). `configure-power.ps1` writes
that same id. A legacy `pwr:` entry is read only when the `reg:` id
was never captured.

Code-complete, runtime-pending: confirm on a Windows 11 VM.

| Id | Live value to read after revert | No-manifest fallback |
| --- | --- | --- |
| `reg:DriverSearchOrderConfig` | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching` `SearchOrderConfig` | DWORD 1 |
| `reg:HiberbootEnabled` | `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power` `HiberbootEnabled` | DWORD 1 |
| `reg:PowerThrottlingOff` | `HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling` `PowerThrottlingOff` | value removed |
| `reg:Win32PrioritySeparation` | `HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl` `Win32PrioritySeparation` | DWORD 2 |
| `reg:AllowTelemetry` | `HKLM:\Software\Policies\Microsoft\Windows\DataCollection` `AllowTelemetry` | DWORD 1 |

| # | Action | Expected |
| --- | --- | --- |
| 1 | After APPLY, note each id's `before.value` / `before.valueExists` in the manifest. | Five `reg:` entries exist. No new `pwr:HiberbootEnabled` or `pwr:PowerThrottlingOff` from this run. |
| 2 | Run `REVERT-EVERYTHING.ps1`. | Each live value matches that `before` (removed when `valueExists` is false). |
| 3 | Wipe the manifest and run revert again on a snapshot that still has the tweaked values. | Fallbacks in the table above. |
| 4 | On a snapshot where only `configure-power.ps1` ran (legacy `pwr:` ids, no `reg:` ids), run `2 power plan\revert-power.ps1`. | Live Hiberboot and PowerThrottling match the `pwr:` `before`, not a forced 1 / delete. |

Manifests created before this change can contain both ids. Revert uses
the `reg:` before. If power-plan ran first, that `reg:` before may
already be the tweaked value; re-apply does not refresh an existing
before. HKCU `Reg-Add` writes stay on the v1.1 list.

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

## TCP timestamps

Apply and a stock Windows 11 install both leave RFC 1323 timestamps
disabled (`netsh int tcp set global timestamps=disabled`). The netsh
global value is not in the manifest, so revert must not turn timestamps
on. A machine that had timestamps enabled before the toolkit ran cannot
get that prior value back; revert returns the inbox default.

Code-complete, runtime-pending.

| # | Action | Expected |
|---|--------|----------|
| 1 | On a fresh VM: `netsh int tcp show global` | `RFC 1323 Timestamps : disabled` |
| 2 | Run `APPLY-EVERYTHING.ps1` or `7 network/optimize-network.ps1` | Still `disabled` |
| 3 | Run `REVERT-EVERYTHING.ps1` | Phase 7 step reads `TCP timestamps disabled (Windows default)` and ends Done. `netsh int tcp show global` still shows `disabled` |
| 4 | Run `7 network/revert-network.bat` | Step `[4/8]` says timestamps were left disabled. `netsh int tcp show global` still shows `disabled` |
| 5 | `10 verify/verify-tweaks.ps1` | `TCP timestamps disabled` reports PREEXISTING (no manifest step key) |

## Empty-manifest case

Tests the defaults fallback when a user runs REVERT without ever
having APPLY'd.

| # | Action | Expected |
|---|--------|----------|
| 1 | Wipe manifest: `Remove-Item "$env:ProgramData\Win11GamingToolkit\state\manifest.json"` | Gone. |
| 2 | Run REVERT-EVERYTHING.ps1 | Should NOT throw. Logs many `Skipped (no manifest entry)` and applies the defaults-fallback path. |
| 3 | System state | Unchanged from pre-REVERT (defaults fallback shouldn't push values for keys that weren't toolkit-set). |

## Failure modes to flag

- If `Restore-ToolkitRegistryValue` writes a wrong value → check the manifest `before` capture in `lib/toolkit-state.ps1` `Get-ToolkitRegistryState`.
- If service revert leaves services at the toolkit-disabled state → `Set-ToolkitServiceStartMode` captured wrong `before` or `Restore-ToolkitServiceStartMode` is missing the actual `sc.exe config` call.
- If DNS revert restores only one address family (v4 OR v6, not both) → CODEX audit regression. Both families must round-trip.
