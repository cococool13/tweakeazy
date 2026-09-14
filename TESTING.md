# Manual Testing Plan

This integration / audit pass was developed on macOS without a Windows 11 VM. The author **did not run the toolkit end-to-end** before merging. This file is the recipe a tester (or a maintainer with VM access) should follow to validate the changes before treating them as proven.

## Test environment

- Windows 11 24H2 Pro, English locale, AC power, single discrete GPU.
- Snapshot the VM before every numbered step. Each step assumes you start from the snapshot of the previous step.
- Run an elevated PowerShell ("Run as Administrator") for every script invocation.

If you have a 25H2 build, an ARM64 build, or a hybrid-graphics laptop, repeat the relevant steps on those targets too — the manifest profile (`isLaptop`, `isHybridGraphics`, `partOfDomain`) influences which warnings the launcher surfaces.

## 1. Baseline verify (no manifest)

Goal: confirm `verify-tweaks.ps1` runs cleanly on a clean OS and reports almost everything as `FAIL`.

```powershell
cd <repo>
.\10 verify\verify-tweaks.ps1
```

Expectation:
- `Manifest` section says "No manifest found."
- Most checks report `FAIL`.
- Some checks report `PREEXISTING` (e.g., HAGS may already be on if Windows enabled it; transparency may already match a custom theme).
- No `ERROR` lines. Any `ERROR` is a bug — open an issue with the line that errored.

## 2. Apply Everything (clean run)

Goal: confirm the full apply flow lands without errors and writes a manifest.

```powershell
.\APPLY-EVERYTHING.ps1
```

Default run is Safe + Advanced only. Phases 9–10 (Windows Update
suppression, VBS / HVCI / LSA / Spectre) stay skipped unless you pass
`-IncludeSecurityTradeoffs`.

Expectation:
- Profile section prints accurately (manufacturer / model / power state / GPU count / domain).
- Confirm prompts as expected. Press Enter through them.
- Each step prints `Done` / `Skipped` / `Failed`.
- Final summary: `Failed: 0`. `Skipped` may be non-zero on hardware that doesn't support a step (no AMD GPU → skip, etc.). Phase 9 and 10 should report skipped on a default run.
- Manifest exists at `$env:ProgramData\Win11GamingToolkit\state\manifest.json`.

Spot checks against bug fixes A1–A10:

| Check | Expectation |
|---|---|
| Manifest is preserved on re-run | Run apply again; the per-id `before` blocks should NOT change. Use `(Get-Content manifest.json \| ConvertFrom-Json).registry.'reg:EnableTransparency'.before` and confirm it's still the original captured baseline. (A3) |
| GPU MSI mode targets only real GPUs | `(Get-Content manifest.json \| ConvertFrom-Json).registry \| Get-Member -Type NoteProperty \| Where Name -like 'gpu-msi:*'` returns only NVIDIA / AMD / Intel adapter IDs, not Microsoft Basic / IDD. (A2) |
| inetpub guard | If IIS-WebServer is enabled on the test VM, the apply step prints "Skipping inetpub removal: IIS appears installed." (A4) |
| `visual-effects-performance.reg` | If you also import this file directly, registry inspect of `HKCU\Control Panel\Desktop\UserPreferencesMask` should be REG_BINARY type. (A1) |
| Spectre / Meltdown **not** applied on default run | `FeatureSettingsOverride*` unchanged. Both keys = 3 only after `.\APPLY-EVERYTHING.ps1 -IncludeSecurityTradeoffs`. |
| MPO disabled | `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name OverlayTestMode` returns 5. |

## 3. Verify post-apply

```powershell
.\10 verify\verify-tweaks.ps1
```

Expectation:
- `APPLIED BY TOOLKIT` count matches roughly the number of tracked items applied.
- `DRIFTED` is 0.
- `Apply Everything coverage` is 95% or higher.

## 4. Re-apply (idempotency)

```powershell
.\APPLY-EVERYTHING.ps1
```

Expectation:
- `Failed: 0`.
- The manifest's `before` blocks are unchanged from step 2 (compare with `git diff` on a copy of the file before and after).

## 5. Revert Everything

```powershell
.\REVERT-EVERYTHING.ps1
```

Expectation:
- `Failed: 0`. `Skipped` may include items that were preexisting and have no captured baseline.
- After reboot, `verify-tweaks.ps1` reports each previously-`APPLIED` item as `PREEXISTING` (defaults match) or `FAIL` if the user had a custom value before apply.
- Spot check the bug fixes A2 / A6 / A10:
  - A2: GPU MSI mode is removed only from real GPUs. Use `Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\<gpu>\..."` and confirm `MSISupported` is gone.
  - A10: an entry where `before.pathExists = false` should have its toolkit value removed. Pick a registry id whose original key didn't exist (e.g., `reg:Tcpip6DisabledComponents` if you ran the IPv6 disable opt-in), confirm `Get-ItemProperty` returns nothing.
  - A6: `DduManual.ps1` Settings.xml schema header should match the manifest version.

## 6. Re-revert (no error storm)

```powershell
.\REVERT-EVERYTHING.ps1
```

Expectation: every step succeeds (no-op) or reports `Skipped`. No `Failed`.

## 7. Launcher exercise

```powershell
.\launcher.ps1
```

For each menu key, click it once on a fresh VM snapshot and confirm:
- The advertised script launches.
- It prints UI helpers correctly (no missing `UI-Step` errors).
- It exits cleanly back to the launcher.

Menu keys to exercise (live `launcher.ps1`):

- Categories: `0`, `1`, `2`, `4`–`13` (no `3`; privacy/telemetry is under `5`)
- Quick actions: `A`, `V`, `R`
- Tools: `M`, `L`, `B`, `?`, `Q`

`[A]` prompts for Security Trade-offs before calling `APPLY-EVERYTHING.ps1`; default is No. There are no `D`, `G`, or `W` keys.

## 8. New script exercise (Phase B)

Each new opt-in script ships with a paired revert. Apply, verify, revert, verify:

| Disable | Revert | Verify |
|---|---|---|
| `5 registry tweaks/individual/disable-mpo.ps1` | `enable-mpo.ps1` | `verify-tweaks.ps1` line "Multiplane Overlay (MPO) disabled" |
| `5 registry tweaks/individual/configure-mmagent.ps1` | `revert-mmagent.ps1` | `Get-MMAgent` after each, compare against sidecar `mmagent-before.json` |
| `5 registry tweaks/individual/disable-spectre-meltdown.ps1` | `enable-spectre-meltdown.ps1` | `verify-tweaks.ps1` line "Spectre / Meltdown mitigations override applied" |
| `5 registry tweaks/individual/disable-write-cache-flush.ps1` | `enable-write-cache-flush.ps1` | manual `Get-ItemProperty` of `HKLM:\...\Enum\<disk>\Device Parameters\Disk\UserWriteCacheSetting` |
| `7 network/disable-adapter-power-savings.ps1` | `enable-adapter-power-savings.ps1` | `Get-NetAdapterPowerManagement` |
| `7 network/disable-ipv6-binding.ps1` | `enable-ipv6-binding.ps1` | `Get-NetAdapterBinding -ComponentID ms_tcpip6` |
| `8 security vs performance/disable-dep.ps1` | `enable-dep.ps1` | `bcdedit /enum {current} \| findstr /i nx` |
| `6 gpu/nvidia/force-p0-state.ps1` | `REVERT-EVERYTHING.ps1` | manifest entry `reg:NvPerfLevelSrc:*` plus `reg:NvDisableDynamicPstate:*` |
| `6 gpu/configure-amd-ulps.ps1` | `REVERT-EVERYTHING.ps1` | manifest entry `reg:AmdEnableUlps:*` |
| `4 services/individual/mobsync-disable.bat` | `mobsync-enable.bat` | `Get-Service CscService \| Select StartType` |

## 9. DNS address-family restore

Goal: confirm DNS capture, verification, and revert preserve both IPv4 and IPv6 baselines.

1. Record the current DNS baseline:
   ```powershell
   Get-DnsClientServerAddress | Select InterfaceAlias, InterfaceIndex, AddressFamily, ServerAddresses
   ```
2. Run `.\7 network\optimize-network.ps1`, choose Cloudflare or Google, and confirm the manifest records DNS under `dns.interfaces`.
3. Run `.\APPLY-EVERYTHING.ps1`; the mixed Cloudflare IPv4 + IPv6 DNS step should record `dns:<InterfaceIndex>` as `applied`, not `skipped`.
4. Run `.\10 verify\verify-tweaks.ps1`; DNS should not report immediate drift.
5. Run `.\REVERT-EVERYTHING.ps1`, then compare `Get-DnsClientServerAddress` output with the baseline from step 1. IPv4 and IPv6 entries for each adapter should both restore.

## 10. Edge cases

### Domain-joined PC
Set the VM domain-joined (or set `partOfDomain = $true` synthetically by joining a test domain). Re-run apply. The launcher should surface the domain warning. Defender exclusions still apply. Update suppression runs only with `-IncludeSecurityTradeoffs`. Document the per-step behavior so this can be turned into "soft skip" later if the user wants.

### Battery laptop
On a Surface / laptop test VM, the launcher should surface the laptop warning. The Ultimate Performance plan still activates if the user proceeds. Confirm thermal / battery throttling stops as expected. Switch back to Balanced manually for normal use.

### Stripped image
On a Server Core or Windows IoT image without `csc.exe`:
- Run `5 registry tweaks/individual/install-timer-resolution-service.ps1`.
- Confirm the new error printout appears with the DISM recovery command.
- Run the DISM command, reboot, re-run the script.
- Confirm STR service installs successfully on the second attempt.

## 11. What to file as a bug

If any of the following happen, open an issue:
- A `Failed` count > 0 in apply or revert with a fresh manifest.
- A `DRIFTED` count > 0 in verify *immediately after a clean apply* (drift only after time / OS updates is expected).
- Manifest JSON cannot be parsed (`Get-Content manifest.json | ConvertFrom-Json` errors).
- Any `ERROR` line in verify (the `Check` function caught a thrown exception — that should be a bug, not an expected case).
- The launcher menu offers a key that points to a missing file.

## What this plan does NOT cover

- Performance benchmarks. The toolkit's purpose is latency-reduction; measuring it requires reproducible workloads (3DMark, CapFrameX, in-game benchmarks). Out of scope here.
- Long-term stability. Some changes only show their costs / benefits over hours of gameplay (timer resolution wakeups, Spectre mitigations under sustained load). Treat the steps above as smoke-tests; real validation is days, not minutes.
- ARM64 verification. The `Get-GpuVendor` filter handles non-PCI graphics correctly (skips them), but I have not exercised the rest of the flow on Snapdragon X.
