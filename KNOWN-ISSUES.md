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

### `5 Graphics/12 Resolution Refresh Rate.ps1` & `13 Hags Windowed.ps1`

`12` walks through Settings UI clicks — no scriptable equivalent, leave in
`BIOS-CHECKLIST.md`. `13 HAGS Windowed` is registry-driven and shippable;
tier: `Advanced`.

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

### Items skipped on technical grounds (still shippable, but warn loudly)

These three are not banned — per the new scope philosophy, the user can opt
into them — but if you port them, the header **must** carry a strong
"cargo-cult" warning explaining why most users should not enable them. The PC
still boots and games still run, so they pass the hard-constraint test.

- **`6 Windows/33 Defender Optimize.ps1` + `8 Advanced/1 Defender.ps1` (wholesale Defender disable)** —
  on Win11 24H2, Tamper Protection makes most of these registry writes no-ops
  or unstable. Ship as `8 security vs performance/disable-defender-wholesale.ps1`
  with `UI-Confirm` text noting: "Tamper Protection may revert these writes;
  expected behavior. Defender exclusions for game library paths (already
  shipped) are usually the better choice."
- **`8 Advanced/8 SMT/HT disable`** — measurably **hurts** multi-thread
  performance on modern Ryzen/Intel CPUs in nearly all 2025-era games.
  Workload-specific; users who genuinely need this know exactly when (and can
  do it from BIOS faster than from a script). Ship as
  `8 security vs performance/disable-smt-ht.ps1` with header text noting the
  empirical regression.
- **`8 Advanced/9 Core 1 Thread 1` (explorer.exe → single-core affinity)** —
  pure cargo-cult; zero measurable benefit and can cause Explorer UI hitches
  under multitasking. Shipped as
  `5 registry tweaks/individual/disable-explorer-affinity.ps1` +
  `enable-explorer-affinity.ps1` with header text noting "no measurable benefit;
  documented for completeness."

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
| "Audit/check" scripts that enumerate state before suggesting removal (legacy apps, legacy features, UWP, Task Manager startup) | `6 Windows/14–18` | "Report then decide" UX is healthier than blanket apply | Low–Medium |

### Categories we do NOT have at all

| Upstream folder | Content | Tier when ported | Notes |
|---|---|---|---|
| `1 Check/` | Hardware/BIOS validation, Space/RAM/GPU check, CPU/RAM/GPU stress tests, HWiNFO launcher, BIOS guide | `Safe` (all read-only or external-tool wrappers) | Would fit as a new top-level `11 hardware checks/` folder. Stress tests should download external tools (Prime95, MemTest) with SHA-256 verify, not bundle. |
| `7 Hardware/` | Mouse polling test, controller overclock + polling, monitor optimization, bufferbloat test, PC build guide | `Safe` for tests, `Advanced` for polling overclock | Polling-rate testers are genuinely useful. Bufferbloat test is a web-launch wrapper. |

### Specific new tweaks in existing folders

| Upstream script | Our folder when ported | Tier | One-line rationale |
|---|---|---|---|
| `6 Windows/8 Widgets`, `9 Copilot` (already partly handled), `19 Gamebar`, `20 Edge & WebView` | `5 registry tweaks/individual/` | `Advanced` | Modern Win11 debloat targets; mostly registry one-liners |
| `6 Windows/23 Sound`, `24 Loudness EQ` | `5 registry tweaks/individual/` | `Advanced` | Audio path tuning; mostly preference |
| `6 Windows/28 Write Cache Buffer Flushing` | We already ship `disable-write-cache-flush.ps1` | — | Duplicate; no action |
| `6 Windows/32 Core Isolation` | `8 security vs performance/` | `Security Trade-off` | Memory Integrity / HVCI overlap — verify against our existing VBS scripts before porting |
| `8 Advanced/7 ReBar Force` | `6 gpu/` | `Advanced` | Force-enable Resizable BAR on unsupported configs; real perf win when it works |
| `8 Advanced/10 Priority` | `5 registry tweaks/individual/` | `Advanced` | Process priority class tweaks |
| `8 Advanced/12 Hardware Legacy Flip`, `13 Hardware Composed Independent Flip` | `5 registry tweaks/individual/` | `Advanced` | DWM/flip-model tweaks; complementary to our MPO disable |
| `8 Advanced/18 Start Search Shell Mobsync` | We already ship `mobsync-disable.ps1` | — | Partial overlap; check for new shell-component disables in upstream version |
| `5 Graphics/9 MSI Mode` (folder version vs our `6 gpu/enable-msi-mode.ps1`) | — | — | Compare detection logic; upstream may have improved device enumeration |
| `5 Graphics/13 HAGS Windowed` | `5 registry tweaks/individual/` | `Advanced` | HAGS-in-windowed-mode toggle |
| `3 Setup/12 Updates Pause` (programmatic pause, not full disable) | `5 registry tweaks/individual/` | `Advanced` | Softer alternative to our `disable-windows-update.ps1`; ship alongside |

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

### `5 registry tweaks/individual/disable-write-cache-flush.ps1`

Per-disk write cache buffer flushing disabled. Material data-loss risk on power loss. Provided as a standalone script for users on UPS-backed desktops who explicitly want the small write-throughput gain. Reverted via paired `enable-write-cache-flush.ps1`.

---

## Existing toolkit limitations carried forward

### Domain-joined PCs

`partOfDomain = true` is captured in the manifest profile and surfaced as a launcher hint. The aggressive update-suppression and Defender-exclusion steps will still run if the user proceeds — the toolkit does not auto-skip them. Enterprise policy may revert most of the changes anyway. Run on a domain-joined gaming PC at your own risk.

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
default ruleset.** 16/16 Pester tests passing. Full progression table in
`CHANGELOG.md` → `[Unreleased]`.

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
without manifest restore. v1.1 migration target.

#### Per-script Pester suites  *(largely RESOLVED in 2026-05-24 resumed loop)*

Coverage now spans the 4 top-priority lib helpers
(`lib/toolkit-state.ps1`, `lib/ui-helpers.ps1`, `lib/gpu-detection.ps1`,
`lib/download-helpers.ps1`), the 3 entry points (`APPLY-EVERYTHING.ps1`,
`REVERT-EVERYTHING.ps1`, `9 cleanup/debloat.ps1`), the launcher
(`launcher.ps1`), plus per-feature suites for `check-storage.ps1`,
`check-uwp-apps.ps1`, the DoH pair, the RSS pair, and the MMCSS pair.

243 total Pester tests passing (from 0 at original session baseline).

Still uncovered: the 30+ individual `5 registry tweaks/individual/*.ps1`
tweak scripts. Most are short and follow the same shape — a future
loop can sweep them with a templated test suite. Lower priority than
the entry points + libs, which were the original concern.

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
