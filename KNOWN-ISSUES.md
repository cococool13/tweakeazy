# Known Issues and Tracking

This file is now a tracking document, not a "won't ship" list. Per the toolkit's
design philosophy (see [CLAUDE.md](CLAUDE.md) → `## Scope`), nothing is
permanently out of scope. The only hard constraints are: **(a) the PC still
boots after Apply + reboot** and **(b) games still run**. Everything else can
ship as an opt-in script under the right tier.

Sections:

1. [FR33THY/Ultimate — items not currently shipped (port on request)](#fr33thyultimate--items-not-currently-shipped-port-on-request)
2. [From updated FR33THY/Ultimate (HEAD ~2026-04-22) — items to evaluate](#from-updated-fr33thyultimate-head-2026-04-22--items-to-evaluate)
3. [Items shipped as opt-in only (NOT in `APPLY-EVERYTHING.ps1`)](#items-shipped-as-opt-in-only-not-in-apply-everythingps1)
4. [Existing toolkit limitations carried forward](#existing-toolkit-limitations-carried-forward)
5. [Logged for next release](#logged-for-next-release)

---

## FR33THY/Ultimate — items not currently shipped (port on request)

These items were considered during the original FR33THY port pass and not yet
shipped. They are **available to port on request** — each just needs the
standard treatment: pick a tier, route writes through `Set-TrackedRegistry` /
`Set-TrackedService`, ship a paired `enable-*` / `revert-*` script, document
risk in the header, and add to the right numbered folder. Not added to
`APPLY-EVERYTHING.ps1` unless the user explicitly asks.

### `2 Refresh/*` — bare-metal install flow

FR33THY ships factory-reset and reinstall scripts. Out of typical scope (this
toolkit operates on existing systems), but `2 Refresh/4 Autounattend.ps1`
(generates a custom `autounattend.xml` with TPM/RAM/SecureBoot bypass + OOBE
skip) is a small lift and genuinely useful for clean installs. Worth porting
as a standalone helper under `0 prerequisites/` if requested.

### `3 Setup/1 BitLocker.ps1` — BitLocker disable

Requires re-encryption decisions and TPM behavior that should be a manual user
choice. Tier: `Security Trade-off`. Port on request with a hard `UI-Confirm`
gate explaining the recovery-key implication.

### `3 Setup/3` (Convert Home→Pro), `6` (locale), `10` (Edge), `11` (Store)

Low-risk QoL settings. Tier: `Safe` to `Advanced`. Cheap to port; each is one
to three lines of `Set-TrackedRegistry` plus a header comment.

### `4 Installers/*` — third-party tool installers

MSI Afterburner, NVIDIA Profile Inspector, MoreClockTool, CRU. The "no bundled
binaries" rule (charter constraint #4) still holds — but **download-and-verify**
with SHA-256 against `versions.json` is consistent with how we already handle
DDU and WinUtil. Ship as `0 prerequisites/install-<tool>.ps1`, one script per
tool, with hash enforcement (FR33THY's upstream scripts skip the verify step;
we add it).

### `5 Graphics/3 Driver Install Debloat & Settings.ps1`

Overlaps `DduManual.ps1` + `6 gpu/install-gpu-driver.ps1`, but the **debloat
phase** strips telemetry components that DDU leaves alone. Worth porting just
that phase as `6 gpu/debloat-driver-telemetry.ps1`. Tier: `Advanced`.

### `5 Graphics/7 Hdcp.ps1` — HDCP disable

Matters for capture-card workflows. Small toggle. Tier: `Advanced`. Ship on
request.

### `5 Graphics/12 Resolution Refresh Rate.ps1`

Walks through Settings UI clicks — no scriptable equivalent. Leave it in
`BIOS-CHECKLIST.md`. HAGS windowed (`5 Graphics/13`) is shipped; see
[opt-in items](#items-shipped-as-opt-in-only-not-in-apply-everythingps1).

### `6 Windows/22 Control Panel Settings.ps1` (108 KB)

108 KB registry blob touching hundreds of keys, many preference-driven. Do
**not** port wholesale — too broad for one tier classification. Cherry-pick
the 10–20 genuinely additive performance keys on request, each as its own
named `.reg` under `5 registry tweaks/individual/` so the user can opt into
specific ones.

### `6 Windows/31 UAC.ps1` — UAC lowering

Tier: `Security Trade-off`. Ship on request with a `UI-Confirm` block that
says "this lowers the elevation prompt; malware that gets user-level execution
will be able to elevate without prompting."

### `8 Advanced/2 Firewall.ps1` — firewall disable

Tier: `Security Trade-off`. Ship on request with a "do not run this if you
ever use public Wi-Fi" warning in the header.

### `8 Advanced/5 File Download Security Warning.ps1` — SmartScreen / MOTW

Tier: `Security Trade-off`. Ship on request. Annoyance reducer; well-understood
trade-off.

### `8 Advanced/15 Driver WHQL Secure Boot Bypass.ps1`

Required for some unsigned-driver workflows — including any future expansion
of our own timer-resolution service if signing breaks. Tier: `Security
Trade-off`. Ship on request, with `bcdedit /set testsigning on` + reboot
documented.

### `8 Advanced/19 NVME Faster Driver.ps1` — force inbox `stornvme.sys`

Vendor drivers carry firmware-specific quirks. FR33THY's own script warns
"breaks Microsoft DirectStorage." Tier: `Advanced`. Ship with that warning
verbatim in the header if requested.

### Moved out of this list (now shipped)

Wholesale Defender disable, SMT / Hyper-Threading disable, and single-core
Explorer affinity are opt-in pairs. Each header carries the cargo-cult
warning. See
[opt-in items](#items-shipped-as-opt-in-only-not-in-apply-everythingps1).

---

## From updated FR33THY/Ultimate (HEAD ~2026-04-22) — items to evaluate

The upstream repo is active (~weekly commits; latest Apr 22 2026) and has
grown since our original port pass. Research summary follows; the
recommendation column is for triage, not a binding queue.

### Automation patterns worth borrowing (not whole scripts)

| Pattern | Where it lives upstream | Why we'd want it | Effort |
|---|---|---|---|
| Per-category interactive numbered menus (e.g. `4 Installers/1 Installers.ps1`, `6 Windows/13 Bloatware.ps1`) | Most category scripts | Lighter than one mega-launcher; each folder gets its own opt-in submenu | Low — already partly modeled by our `launcher.ps1` per-folder submenus |
| `autounattend.xml` generator with TPM/RAM/SecureBoot bypass + OOBE skip | `2 Refresh/4 Autounattend.ps1` | Useful clean-install helper; pair with USB-staging script | Medium |
| "Audit/check" scripts that enumerate state before suggesting removal (legacy apps, legacy features, Task Manager startup) | `6 Windows/14–18` | UWP inventory is shipped as `11 hardware checks/check-uwp-apps.ps1`. The other 14–18 checks are still not a matching set. | Low–Medium |

### Hardware check folders (shipped)

`11 hardware checks/` and `12 hardware/` are in the tree and on the launcher
(`[11]` Hardware checks, `[12]` Hardware). Tier: `Safe`. Default behavior is
read-only. `check-storage.ps1 -Fix` can enable TRIM. `-RunStress` on the CPU,
GPU, and RAM checks prints that tool download is not wired yet. It does not
launch Prime95, FurMark, or Memory Diagnostic.

`11 hardware checks/` (3):

- `check-storage.ps1` — TRIM / fixed-disk report (`-Fix` can enable TRIM)
- `check-uwp-apps.ps1` — Appx inventory vs the debloat lists
- `show-system-summary.ps1` — CIM + registry baseline

`12 hardware/` (9):

- `check-cpu-stress.ps1`
- `check-directstorage.ps1`
- `check-gpu-stress.ps1`
- `check-input-polling.ps1`
- `check-msi-mode.ps1`
- `check-pagefile.ps1`
- `check-ram.ps1`
- `check-rebar.ps1`
- `show-mouse-info.ps1`

Still not in the tree from those upstream folders: an HWiNFO launcher,
controller overclock, monitor optimization, a bufferbloat wrapper, and a PC
build guide. A SHA-256 download path for Prime95, MemTest, or FurMark is
still unshipped.

### Still not scripted

| Upstream script | Status |
|---|---|
| `6 Windows/24 Loudness EQ` | Still not scripted. Manual Settings UI. Sound scheme None is shipped (`sound-scheme-none.reg` and the Apply step). |
| `6 Windows/20 Edge & WebView` (WebView half) | No WebView2 removal script. Edge background and prefetch policies are shipped. |

### What upstream does worse than us (don't borrow)

- **No state-tracking / no transactional revert.** Each script offers a "Default"
  option but it's fire-and-forget. Our manifest at
  `%ProgramData%\Win11GamingToolkit\state\manifest.json` is the correct design;
  keep it.
- **No SHA-256 verification of downloaded installers.** `4 Installers/1 Installers.ps1`
  trusts vendor URLs without hash check, even though the README lists SHAs. Any
  port must add the verification step we already apply to DDU and WinUtil.
- **`IWR.ps1` sets `ExecutionPolicy = Unrestricted` machine-wide and unblocks
  all downloaded files.** Do not replicate. If we ship an `iwr | iex`
  bootstrapper, scope to `-Scope Process`.
- **Commit hygiene.** Upstream commit messages are literally "Upload." No
  CHANGELOG, no semantic versioning. We have both; keep them.

### Licensing / attribution

MIT licensed. Porting any script requires preserving a "Copyright FR33THY"
notice in the per-file header (we already use the `# Source: FR33THYFR33THY/Ultimate — <path>`
convention; add `# Copyright FR33THY (MIT)` alongside it for any new ports).

---

## Items shipped as opt-in only (NOT in `APPLY-EVERYTHING.ps1`)

These run only when the user launches the script or `.reg`. Default Apply
does not call them.

### `5 registry tweaks/individual/disable-write-cache-flush.ps1`

Per-disk write cache buffer flushing disabled. Material data-loss risk on power loss. Provided as a standalone script for users on UPS-backed desktops who explicitly want the small write-throughput gain. Reverted via paired `enable-write-cache-flush.ps1`.

### `8 security vs performance/disable-defender-wholesale.ps1`

Wholesale Defender disable. Tier: `Security Trade-off`. On Win11 24H2, Tamper Protection can revert the writes. The header points users at game-library exclusions instead. Pair: `enable-defender-wholesale.ps1`.

### `8 security vs performance/disable-smt-ht.ps1`

Limits boot processors to the physical core count (`bcdedit /set numproc`). Tier: `Security Trade-off`. The header states this hurts multi-thread performance on current Ryzen and Intel CPUs. Pair: `enable-smt-ht.ps1`. Reboot required.

### `5 registry tweaks/individual/disable-explorer-affinity.ps1`

Pins `explorer.exe` to CPU 0. Tier: `Advanced`. The header states there is no measurable benefit. Pair: `enable-explorer-affinity.ps1`.

### `6 gpu/force-rebar.ps1`

Writes `HwUMAEnable` to force Resizable BAR exposure. Tier: `Advanced`. Pair: `disable-rebar.ps1`. Read-only state is `12 hardware/check-rebar.ps1`. BIOS Above-4G / CSM requirements stay in the script header.

### `5 registry tweaks/individual/pause-windows-update.ps1`

Pauses Windows Update for 1–35 days. Tier: `Advanced`. Pair: `resume-windows-update.ps1`. This is the soft pause. Phase 9 of Apply (service suppression) is a different path and stays behind `-IncludeSecurityTradeoffs`.

### `5 registry tweaks/individual/disable-edge-prefetch.ps1`

Disables Edge predictive prefetch (`NetworkPredictionOptions`). Pair: `enable-edge-prefetch.ps1`. Edge startup boost and background mode are separate and also run in default Apply (`disable-edge-background.ps1`).

### `5 registry tweaks/individual/disable-hags-windowed.reg`

Disables HAGS for windowed presentation (`DirectFlipDisabled`). Tier: `Advanced`. Pair: `revert-hags-windowed.reg`.

### `5 registry tweaks/individual/dwm-flip-model.reg`

Hardware legacy flip and hardware-composed independent flip. Tier: `Advanced`. Pair: `revert-dwm-flip-model.reg`.

### Shipped on the default Apply path

These are in the tree. Default `APPLY-EVERYTHING.ps1` runs the same change
without `-IncludeSecurityTradeoffs`.

- Widgets — `disable-widgets.reg` / `revert-widgets.reg`. Apply step "Disable Widgets".
- Copilot — `disable-copilot.reg` / `revert-copilot.reg`. Apply step "Disable Copilot".
- Game Bar / DVR — `disable-game-bar-dvr.reg` / `revert-game-bar-dvr.reg`. Apply step "Game Bar / DVR disabled".
- Sound scheme None — `sound-scheme-none.reg` / `revert-sound-scheme-none.reg`. Apply step "Sound scheme set to None".
- Edge background / startup boost — `disable-edge-background.ps1` / `enable-edge-background.ps1`, also an Apply step. No separate WebView2 removal script.
- Game scheduling priority — `game-priority.reg` / `revert-game-priority.reg`. Apply step "Game CPU/GPU priority increased".
- MSI mode — `6 gpu/enable-msi-mode.ps1` / `disable-msi-mode.ps1` (Apply phase 7). Read-only audit: `12 hardware/check-msi-mode.ps1`.
- Offline Files / mobsync — `4 services/individual/mobsync-disable.ps1` / `mobsync-enable.ps1`. Apply disables `CscService`.
- Full HAGS — windows-settings phase sets `HwSchMode = 2`. Standalone pair `enable-hags.ps1` / `disable-hags.ps1` refuses to run without `-Experimental`. Windowed-only HAGS stays opt-in (`disable-hags-windowed.reg`).

### Shipped Security Trade-off (off unless `-IncludeSecurityTradeoffs`)

Core Isolation / HVCI / VBS is `8 security vs performance/configure-vbs.ps1`
(`-Disable` / `-Enable`). Apply Phase 10 runs only with
`-IncludeSecurityTradeoffs`. Phase 9 (Windows Update suppression) uses the
same switch.

---

## Existing toolkit limitations carried forward

### Domain-joined PCs

`partOfDomain = true` is captured in the manifest profile and surfaced as a launcher hint. The toolkit does not auto-skip phases because the PC is domain-joined. Default `APPLY-EVERYTHING.ps1` skips Phase 9 (Windows Update suppression) and Phase 10 (VBS / HVCI / LSA / Spectre) unless `-IncludeSecurityTradeoffs` is passed. Defender exclusions (Phase 12) still run if the user proceeds. Enterprise policy may revert most of the changes anyway. Run on a domain-joined gaming PC at your own risk.

### Battery laptops

The launcher reports `isLaptop / isHandheld` and surfaces a "start with Setup, then use only the areas you understand" hint. Aggressive power tuning still applies if the user proceeds. The Ultimate Performance plan removes thermal/battery throttling, which on a laptop on battery measurably shortens battery life. Users on laptops should switch the active power plan back to Balanced when on battery.

### ARM64 Windows

Driver-related items (MSI mode for GPU on Snapdragon X) are not separately tested. The PnP enumeration filter in `lib/gpu-detection.ps1` matches by PCI vendor ID, so non-PCI integrated graphics (Snapdragon X Adreno) are skipped automatically. Some other items (DDU flow, NVIDIA-specific scripts) are no-ops on ARM and silently skip.

### `WaaSMedicSvc` on 24H2 / 25H2

`disable-windows-update.ps1` may report a warning if the WaaSMedicSvc registry key has a DACL that prevents even SYSTEM from writing the `Start` value. On those builds, Windows Update may auto-re-enable itself periodically. Taking ownership of the key with `takeown` and `icacls` is documented in `GUIDE.md` Troubleshooting; the toolkit will not do this automatically.

### Stripped Windows images (Server Core, debloat ISOs)

`install-timer-resolution-service.ps1` requires `csc.exe` from .NET Framework 4.0. Missing on stripped images. The script fails with a clear error and exits cleanly. Use `Add-WindowsCapability -Online -Name 'NetFx3~~~~'` to recover, then re-run.

---

## Logged for next release

Items below are tracked work — known issues, audit findings, and untracked
writes that have been catalogued for a future release. None block the current
shipping version; each is logged so it isn't forgotten.

### From the 2026-05-24 continuous-improvement loop (in progress)

**Status: PSScriptAnalyzer gate fully green (0 Error, 0 Warning) on the
default ruleset.** Latest gate in `CHANGELOG.md` → `[Unreleased]` (fourth
loop): **518 Pester tests passing, 23 skipped**. The 16-test and 243-test
rows in that file are earlier snapshots, not the current suite.

#### Function-naming refactor (PSUseApprovedVerbs / PSUseSingularNouns)

22 internal helpers use a non-standard verb namespace: `UI-*`, `Reg-Add`,
`Run-Step`, vendor-`Apply-*`, lib-`Ensure-*` / `Capture-*` / `Record-*` /
`Normalize-*` / `Stage-*` / `Fetch-*`. The two analyzer rules are currently
excluded with rationale (see `.psscriptanalyzer.psd1`); a wholesale rename
to PowerShell-approved verbs + nouns is queued as a v2 refactor. Estimated
~150 call sites to update. Must come with comprehensive Pester coverage to
catch any regressions, since the codebase still lacks runtime tests for
most paths.

#### GPU configure scripts dot-source path bug  *(RESOLVED in commit 8d4f1e — see CHANGELOG `[Unreleased]`)*

Original gap: `6 gpu/{nvidia,amd,intel}/configure-*.ps1` and
`install-*.ps1` dot-sourced `..\lib\*` which resolves to `6 gpu\lib\*`
(does not exist) instead of repo root. The scripts only worked because
their `&`-invocation parent (`install-gpu-driver.ps1`) had already
loaded the helpers into scope; standalone invocation produced silent
no-ops or "command not found" later.

Resolution: all 6 scripts now dot-source `..\..\lib\*` correctly.
Inline admin-check workaround comments from CURSOR-AUDIT #6 are
preserved for clarity but the dot-source now actually loads
`lib/ui-helpers.ps1` if a future cleanup wants to switch from inline
`IsInRole` to the canonical `UI-RequireAdmin`.

#### Phase 5 / Phase 11 Reg-Add cosmetic writes (CURSOR-AUDIT #13 remainder)

~45 `Reg-Add` calls in `APPLY-EVERYTHING.ps1` Phases 5 and 11 are HKCU
cosmetic settings (dark mode, taskbar, explorer flags). High-impact HKLM
keys were migrated to `Set-ToolkitRegistryValue` in commit `40630c3`; the
HKCU writes remain because they're user-toggleable via Windows Settings
without manifest restore. v1.1 migration target. Do not pull those HKCU
writes into a manifest pass early.

The five HKLM ids from that migration now restore from the manifest
before any hardcoded default: `reg:DriverSearchOrderConfig`,
`reg:HiberbootEnabled`, `reg:PowerThrottlingOff`,
`reg:Win32PrioritySeparation`, `reg:AllowTelemetry`. Power-plan scripts
write the same `reg:` id for Hiberboot and power throttling (no second
`pwr:` writer). A legacy `pwr:` entry is read only when the `reg:` id
is absent. Verify on Windows via checklist **12.5** (code-complete,
runtime-pending).

#### Per-script Pester suites  *(suite size matches the fourth-loop gate)*

Coverage spans the 4 top-priority lib helpers
(`lib/toolkit-state.ps1`, `lib/ui-helpers.ps1`, `lib/gpu-detection.ps1`,
`lib/download-helpers.ps1`), the 3 entry points (`APPLY-EVERYTHING.ps1`,
`REVERT-EVERYTHING.ps1`, `9 cleanup/debloat.ps1`), the launcher
(`launcher.ps1`), plus per-feature suites for `check-storage.ps1`,
`check-uwp-apps.ps1`, the DoH pair, the RSS pair, and the MMCSS pair.
Later loops added `tests/5-registry-tweaks/individual-tweaks.Tests.ps1`
(templated sweep of `5 registry tweaks/individual/*.ps1`), the invariant
suites, and the hardware-check tests.

518 Pester tests passing, 23 skipped, at the end of the fourth loop in
`CHANGELOG.md` (from 0 at the original session baseline).

The individual tweak scripts are covered by that templated sweep (parse,
comment-based help, admin self-check, script-start logging, tracked-helper
use). Remaining skips are the gap lists in that suite (`$HelpGaps`,
`$ApplyHelperGaps`, `$RestoreHelperGaps`), not an uncovered folder.

#### Windows Sandbox configs for system-mutating scripts  *(RESOLVED in 2026-05-24 resumed loop, commit `8ddff76`)*

6 `.wsb` configs under `tests/sandbox/`:
`apply-everything-{default,tradeoffs,whatif}.wsb`, `debloat.wsb`,
`revert-everything.wsb`, `check-storage.wsb`. Authored on macOS
(can't execute), so paired with `tools/Start-SandboxSession.ps1`
wrapper that substitutes the host repo path into a temp .wsb and
launches Sandbox on Windows (or inspect-only on macOS). Full layout +
limitations in `tests/sandbox/README.md`.

### From v1.0.0 production-readiness audit

#### `APPLY-EVERYTHING.ps1` Nagle write bypasses toolkit-state  *(RESOLVED in CURSOR-AUDIT #5, commit `dd5dc3e`)*

Original gap: lines 399–400 set `TcpAckFrequency` and `TCPNoDelay` on every interface via raw `Set-ItemProperty` instead of `Set-ToolkitRegistryValue`. Resolved by routing both writes through `Set-ToolkitRegistryValue` with per-interface Ids matching `7 network/optimize-network.ps1`'s pattern. `REVERT-EVERYTHING.ps1` now prefers manifest restore with a blind-remove fallback for legacy interfaces.

#### `APPLY-EVERYTHING.ps1` startup-cleanup `reg delete` calls are not tracked

Phase 6 (Startup Cleanup) deletes `HKCU\...\Run` autostart entries for OneDrive, Teams, etc. via raw `reg delete`. These are deletions of vendor-installed values — there is nothing for the manifest to capture as `before` state in a useful way, and revert relies on the user re-launching OneDrive / Teams to re-register their autostart hooks. Acceptable as an intentional defaults-style policy apply. Document the revert expectation in `GUIDE.md` if user reports surface in the field.

#### `APPLY-EVERYTHING.ps1` Power-Plan attribute unhide is not tier-tagged

Line 163 (`reg add ... PowerSettings\54533251.../Attributes /d 0`) is a metadata write that unhides a hidden power setting so the next `Set-PowerIdx` call can reach it. The Phase block is tier-tagged `Advanced`, but the individual `reg add` is not routed through `Set-TrackedRegistry` because there is no functional change to revert — the Attributes flag only controls visibility, not behavior. Acceptable; no action needed.

#### Notice.txt scope

`Notice.txt` credits Khorvie Tech only — the original toolkit lineage. FR33THY, Chris Titus Tech, and Wagnardsoft are credited in `GUIDE.md` Credits and per-file headers. Owner decision: expand `Notice.txt` to consolidate all upstream credits, or keep it focused on lineage. No technical impact either way.

#### `README.md` launcher screenshot

`README.md` describes the launcher header, three-section layout, and color-coded tier indicators in prose, but does not embed a screenshot. The production-readiness pass ran on macOS (no Windows host), so a real-host screenshot couldn't be captured. After the owner runs `MANUAL-TEST-CHECKLIST.md` section 1 on a Win11 VM, capture the launcher main menu (PNG) and place it at `docs/img/launcher.png`, then add `![](docs/img/launcher.png)` under the Quick start section of `README.md`. v1.1 follow-up.

### Cursor audit #1–#25 (closed)

The 2026-05-24 Cursor pass listed 25 findings. Those remediations shipped;
do not re-open them as new work. The remaining follow-up that is still
open is already tracked above (Phase 5 / Phase 11 Reg-Add remainder).
Per-version history is in `CHANGELOG.md`.
