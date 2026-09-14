# Manual Test Checklist — v1.0.0 snapshot + current launcher keys

This was the v1.0.0 runtime gate. Keep using it on a real Windows host
(about an hour on a fresh Win11 VM). Rows below for `[11]` `[12]` `[13]`
and the Apply trade-off gate match the live `launcher.ps1`, not the
original v1.0.0 menu (which stopped at `[10]`).

## Test environment

Use a clean Windows 11 24H2 Pro install — preferably a VM with a snapshot, so you can roll back between checklist sections.

- Hyper-V or VMware: take a snapshot named `pre-toolkit` before starting.
- Bare metal: be ready to use a System Restore point or `REVERT-EVERYTHING.ps1` between sections.
- 8 GB RAM, 60 GB disk, single virtual GPU is enough.
- No domain join. No BitLocker on the VM. No third-party AV.
- Recommended: open a non-admin PowerShell window first (for the non-admin refusal test), then an admin PowerShell window for the rest.

Mark each line `[PASS]` / `[FAIL]` / `[SKIP] reason`. If anything fails, capture the error and note the file/line involved.

---

## 1. Launcher render — main menu

Run as Administrator from the repo root:
```powershell
.\launcher.ps1
```

- [ ] **1.1** Header line 1 shows `Win11 Gaming Toolkit` left-aligned and `v1.0.0` right-aligned, both inside a Unicode box (`┌─┐ │ │ └─┘`).
- [ ] **1.2** Header line 2 reads `Admin: yes   Build: <number>   Manifest: <N> entries`. Build number is the current Windows build (`(Get-CimInstance Win32_OperatingSystem).BuildNumber`). Manifest count is `0` on a clean VM, or whatever `state.steps` count exists.
- [ ] **1.3** "Quick actions" label is yellow. `[A]` `[V]` `[R]` brackets are cyan. Action labels are white.
- [ ] **1.4** "Categories" section lists exactly these keys: `[0]` `[1]` `[2]` `[4]` `[5]` `[6]` `[7]` `[8]` `[9]` `[10]` `[11]` `[12]` `[13]`. No `[3]` (privacy/telemetry tweaks live in `[5]`).
- [ ] **1.5** Tier color: `Safe` rows render in green (categories 0, 1, 7, 10, 11, 12). `Advanced` rows render in yellow (categories 2, 4, 5, 6, 9, 13). `Trade-off` row renders in red (category 8). The display label `Trade-off` shows in the menu, not the canonical `Security Trade-off`.
- [ ] **1.6** "Tools" section lists `[M]` `[L]` `[B]` `[?]` `[Q]` on two lines, brackets cyan, labels in default text.
- [ ] **1.7** Box-drawing characters and section dividers render in dark gray, not glyph-corrupted (no `?` or replacement boxes).
- [ ] **1.8** No emoji anywhere on screen. No `[OK]` / `!` indicators show on a clean VM (manifest is empty → no status to display).
- [ ] **1.9** Prompt `PS>` appears at the bottom and accepts input.
- [ ] **1.10** Press `Q` → launcher exits cleanly with exit code 0 (`$LASTEXITCODE -eq 0`).

## 2. Launcher render — narrow terminal + ISE fallback

- [ ] **2.1** Resize the PowerShell window to 60 columns wide, run `.\launcher.ps1` again. Header still readable; section labels intact; no line wraps that scramble columns. Quit with `Q`.
- [ ] **2.2** Open Windows PowerShell ISE (`powershell_ise.exe`), run `.\launcher.ps1` from the editor's console. ASCII fallback engages: header uses `+--+ | +--+` instead of Unicode box-drawing chars. Other content readable. Quit with `Q`.

## 3. Non-admin refusal

In a **non-admin** PowerShell window, run:
```powershell
.\launcher.ps1
```

- [ ] **3.1** Output is exactly the one-line refusal: `Win11 Gaming Toolkit must be run as Administrator.` followed by the `Right-click PowerShell > Run as Administrator, then re-run launcher.ps1.` instruction.
- [ ] **3.2** Process exits immediately with exit code 1 (`$LASTEXITCODE -eq 1`). No menu was rendered.

## 4. Apply path

Take a VM snapshot named `pre-apply`. Then in the **admin** PowerShell window:
```powershell
.\APPLY-EVERYTHING.ps1
```

Default run skips Phase 9 (Windows Update suppression) and Phase 10
(VBS / HVCI / LSA / Spectre). Launcher `[A]` asks first; default is No.
Do **not** pass `-IncludeSecurityTradeoffs` for this section.

- [ ] **4.1** Script runs to completion without throwing. If it does throw, capture the line and the failing `Run-Step`.
- [ ] **4.2** Final summary reports `0 Failed`. (`Succeeded` and `Warned` counts can vary by VM — what matters is zero failures.) Phase 9 and 10 report skipped.
- [ ] **4.3** `C:\ProgramData\Win11GamingToolkit\state\manifest.json` exists and has `state.steps`, `state.registry`, `state.services`, `state.dns.interfaces`, `state.defender.added`, `state.packages.removed` populated. Open in Notepad or `Get-Content -Raw | ConvertFrom-Json` and spot-check that `lastUpdated` is recent and `state.context.windowsVersion` is sane.
- [ ] **4.4** Reboot the VM. After login: keyboard, mouse, network, audio, and display all work. Login prompt accepts the password. Desktop renders.

## 5. Verify path (post-apply)

```powershell
.\10` verify\verify-tweaks.ps1
```
*(Note the backtick — the folder has a space.)*

- [ ] **5.1** Tracked tweaks report `APPLIED` (or `OK` per the verify-tweaks helper). No `DRIFTED` rows.
- [ ] **5.2** Footer still prints `Security Trade-off items are intentional in Apply Everything.` (verify-tweaks wording). Those items were **not** applied on the default run in section 4.
- [ ] **5.3** Manifest path printed in the footer matches `C:\ProgramData\Win11GamingToolkit\state\manifest.json`.

## 6. Launcher render — post-apply manifest indicators

Re-run `.\launcher.ps1` after the apply.

- [ ] **6.1** Header shows `Manifest: <N>` where `<N>` is greater than zero and matches roughly the count of `state.steps` entries in the manifest.
- [ ] **6.2** Categories that ran apply steps now show `[OK] applied` in cyan (e.g. category 4 Services, category 5 Registry, category 7 Network, category 9 Cleanup). Category 8 stays blank after a default apply (trade-offs were skipped). `[11]` `[12]` `[13]` stay blank (no tracked prefixes).
- [ ] **6.3** No category shows `! drift` immediately after apply. (Drift would mean the OS already reverted a tracked value, which shouldn't happen on a clean apply.)
- [ ] **6.4** Quit with `Q`.

## 7. Tools — `[M]` View manifest

Re-launch and press `M`.

- [ ] **7.1** `manifest.json` opens in the default Windows JSON handler (Notepad on a clean VM). Content is the live manifest. Close the editor.
- [ ] **7.2** Launcher returns to the main menu when the editor closes.

## 8. Tools — `[L]` View recent log

In the launcher main menu, press `L`.

- [ ] **8.1** On a clean VM where no script has emitted a log to `%ProgramData%\Win11GamingToolkit\logs\`, the screen prints `(no logs yet)` followed by `Log directory: C:\ProgramData\Win11GamingToolkit\logs`. Press Enter to return.
- [ ] **8.2** *(Optional — only if any script writes to that log directory in v1.0.0; if not, skip.)* If a `*.log` file exists, the launcher prints the last 40 lines, the file path, and returns on Enter.

## 9. Tools — `[B]` Regenerate baseline

Press `B`.

- [ ] **9.1** Launcher prompts `Type YES to confirm`.
- [ ] **9.2** Type literally `no` (or anything other than uppercase `YES`) → operation cancels with `Cancelled.`
- [ ] **9.3** Press `B` again. This time type `YES` exactly. The manifest is regenerated. Confirm `state.steps` is now empty (`{}`) but `state.context` is still populated.

## 10. Tools — `[?]` Help screen

Press `?`.

- [ ] **10.1** Help screen lists every keybinding (`[A]` `[V]` `[R]` `[0]` `[1]` `[2]` `[4]`–`[13]` `[M]` `[L]` `[B]` `[?]` `[Q]`) with one-line descriptions. Status indicator legend at the bottom. No `[3]`, `D`, `G`, or `W`.
- [ ] **10.2** Enter returns to the main menu.

## 11. Category submenus

For each category, press the key, confirm:
- [ ] **11.1** `[0]` Prerequisites — submenu lists `0 prerequisites/install-runtimes.ps1`.
- [ ] **11.2** `[1]` Backup — submenu lists `create-backup.ps1` only.
- [ ] **11.3** `[2]` Power plan — submenu lists `configure-power.ps1` and `revert-power.ps1`.
- [ ] **11.4** `[4]` Services — submenu lists `disable-services.ps1`, `enable-services.ps1`, and the `mobsync-*.ps1` / wrapping `mobsync-*.bat` pair.
- [ ] **11.5** `[5]` Registry tweaks — submenu lists ~30 `.reg` and `.ps1` files including `apply-all.reg`, `revert-all.reg`, `privacy-telemetry.reg`, `disable-spectre-meltdown.ps1`. No `backup-current.bat`.
- [ ] **11.6** `[6]` GPU — submenu lists vendor-specific subfolders flattened, including `enable-msi-mode.ps1`, `nvidia/force-p0-state.ps1`, `configure-amd-ulps.ps1`, `install-gpu-driver.ps1`.
- [ ] **11.7** `[7]` Network — submenu lists `disable-adapter-power-savings.ps1`, `enable-adapter-power-savings.ps1`, `disable-ipv6-binding.ps1`, `enable-ipv6-binding.ps1`, `optimize-network.ps1`, `revert-network.bat`. No `optimize-network.bat`.
- [ ] **11.8** `[8]` Security vs performance — submenu lists `configure-vbs.ps1`, `disable-dep.ps1`, `enable-dep.ps1`. Tier label in the submenu header reads `Trade-off`.
- [ ] **11.9** `[9]` Cleanup — submenu lists `chris-titus-winutil.bat`, `cleanup-temp.ps1`, `debloat.ps1`.
- [ ] **11.10** `[10]` Verify — submenu lists `verify-tweaks.ps1`.
- [ ] **11.11** `[11]` Hardware checks — submenu lists `check-storage.ps1`, `check-uwp-apps.ps1`, `show-system-summary.ps1`. Tier `Safe`.
- [ ] **11.12** `[12]` Hardware — submenu lists the read-only checks (`check-rebar.ps1`, `check-msi-mode.ps1`, `check-ram.ps1`, `check-pagefile.ps1`, `check-input-polling.ps1`, `check-directstorage.ps1`, stress wrappers). Tier `Safe`.
- [ ] **11.13** `[13]` External tools — submenu lists `launch-autoruns.ps1`, `launch-shutup10.ps1`, `launch-device-cleanup.ps1`. Tier `Advanced`.
- [ ] **11.14** From any submenu, `Q` returns to the main menu cleanly.

## 12. Revert path

Take a snapshot named `post-apply` first. Then:
```powershell
.\REVERT-EVERYTHING.ps1
```

- [ ] **12.1** Script runs to completion without throwing. Final summary reports `0 Failed`.
- [ ] **12.2** Reboot. Login prompt works. Desktop renders. Network / audio / display / mouse / keyboard all functional.
- [ ] **12.3** Re-run `verify-tweaks.ps1`. Most tracked tweaks now report not-applied or default state.
- [ ] **12.4** Re-launch `.\launcher.ps1`. Categories no longer show `[OK] applied` for the reverted tweaks. (Some defender exclusions and `state.packages.removed` entries may persist — that's intentional, not a bug.)

## 13. Idempotency

- [ ] **13.1** Re-run `.\APPLY-EVERYTHING.ps1` (apply twice in a row). Final summary reports `0 Failed`. No errors about existing registry keys / services in `Pending` state.
- [ ] **13.2** Re-run `.\REVERT-EVERYTHING.ps1` (revert twice in a row). `0 Failed`.
- [ ] **13.3** apply → revert → apply: re-run apply once more. Manifest's `state.registry` `before` snapshots are unchanged from the first apply (Spot-check: pick one tracked entry, e.g. `gpu-msi:*`, confirm its `before.value` field matches what it was after the first apply).

## 14. Locale-stable ultimate-performance activation

```powershell
.\2` power plan\configure-power.ps1
```

- [ ] **14.1** Script duplicates the Ultimate Performance scheme from a fixed GUID (`e9a42b02-d5df-448d-aa00-03f14749eb61`), creates the active scheme, and reports success on a non-English Windows install. (Set OS display language to a non-English locale before running if you can — the A9 fix made this independent of `for /f` parsing.)

## 15. Spot checks for fixed bugs

Quick reads on the post-apply VM:

- [ ] **15.1** **A1**: `reg query "HKCU\Control Panel\Desktop" /v UserPreferencesMask` returns type `REG_BINARY`, not `REG_EXPAND_SZ` or `REG_SZ`.
- [ ] **15.2** **A2**: `Get-PnpDevice -Class Display` shows multiple display adapters in the OS, but `manifest.json`'s `state.registry` only has `gpu-msi:*` entries for ones whose vendor matches `VEN_10DE` (NVIDIA), `VEN_1002` (AMD), or `VEN_8086` (Intel). No virtual displays (Microsoft Basic, IDD, OBS Virtual Cam, Parsec) are tracked.
- [ ] **15.3** **A4**: If Windows Optional Features → IIS-WebServer is enabled, `C:\inetpub` is not deleted by APPLY-EVERYTHING.ps1's cleanup phase. (Run `Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServer-Role`. If `Enabled`, confirm directory still exists post-apply.)
- [ ] **15.4** **A6**: `DduManual.ps1` reports a downloaded SHA-256 hash that matches `versions.json`'s pinned value before extraction; throws if mismatched.
- [ ] **15.5** **A7**: `9 cleanup\chris-titus-winutil.bat` prints the expected SHA-256 from `WINUTIL_SHA256` constant, computes the actual hash, and refuses to run if they differ.

## 16. WinUtil + DDU integration spot checks

- [ ] **16.1** From the launcher, navigate `[9]` → `chris-titus-winutil.bat`. The script downloads, prints both SHA-256 values, compares them, and only continues on match.
- [ ] **16.2** `DduManual.ps1` (run directly) writes a `Settings.xml` next to the DDU executable. Open it in Notepad — the `<DisplayDriverUninstaller Version=...>` header is present (legacy schema pin; cosmetic).

---

## Pass / fail summary

After running through everything, fill in the row totals:

- Pass count: `___`
- Fail count: `___`
- Skipped: `___`

If `Fail count > 0`, do not tag v1.0.0. File a `fix:` commit per failure, re-run the affected sections, then re-tag once everything is `[PASS]`.

If everything passes, paste this block (with counts filled in) into `PRODUCTION-READY.md` under `## Phase 3 — Windows runtime validation` to mark the gate as green.
