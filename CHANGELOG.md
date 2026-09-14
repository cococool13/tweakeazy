# Changelog

All notable changes to this toolkit are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The audit history is preserved in `CHANGES.md`, `CODEX-AUDIT.md`, `CURSOR-AUDIT.md`, and `CLEANUP.md`; this file is the user-facing roll-up.

## [Unreleased] — continuous-improvement loop (in progress)

Started 2026-05-24. Quality-gate-driven pass focused on making the analyzer-clean a hard precondition for every script. Baseline at session start: 1537 PSScriptAnalyzer findings (3 Error, 1415 Warning, 119 Info).

### Removed
- Spent one-shot agent prompts `prompts/cleanup-and-redesign.md` and `prompts/production-readiness.md`. Outcomes already recorded in `CLEANUP.md` and `PRODUCTION-READY.md`. Those files are not live instructions; the current Cloudflare landing page is `site/` and must not be deleted.

### Added
- `.psscriptanalyzer.psd1` project ruleset — PS 5.1+7.4 compatibility targets, formatter rules, explicit exclusions with documented rationale per excluded rule. (`bbd2a56`)
- `tools/Invoke-ToolkitGate.ps1` — single quality-gate entrypoint reproducible locally and in CI. Supports `-Strict`, `-SkipTests`, `-SkipAnalyzer`, scoped `-Path`. (`bbd2a56`)
- `.github/workflows/ci.yml` — two-job matrix (ubuntu-latest + windows-latest), both invoke `Invoke-ToolkitGate.ps1` so dev-vs-CI behavior matches exactly. (`bbd2a56`)
- `tests/_common.ps1` — shared Pester scaffolding (AST helpers, parameter-shape assertions, admin-check assertions, comment-based-help assertions). macOS-runnable. (`bbd2a56`)
- `tests/lib/toolkit-state.Tests.ps1` — 16 passing Pester v5 tests covering file health, mutator ShouldProcess contract, and public-surface stability. Anchors the per-script test pattern. (`d02bd37`)
- `SupportsShouldProcess` on `Set-ToolkitRegistryValue`, `Set-ToolkitServiceStartMode`, `Set-ToolkitDnsServers` — `-WhatIf` and `-Confirm` now propagate from any caller per CLAUDE.md quality bar. (`eacd601`)
- Defense-in-depth enforcement of `$neverRemove` safety list in `9 cleanup/debloat.ps1`. Previously declared but never used (latent safety gap exposed by `PSUseDeclaredVarsMoreThanAssignments`). (`f71d130`)

### Fixed
- 3 `PSScriptAnalyzer` Error-severity findings — replaced `Test-Connection -ComputerName "8.8.8.8"` with `[System.Net.NetworkInformation.Ping]` in `lib/download-helpers.ps1`, `lib/ui-helpers.ps1`, `0 prerequisites/install-runtimes.ps1`. Sidesteps a false-positive rule AND drops Cim warmup latency from ~200–500ms to ~5–50ms. (`4e993a9`)
- 26 .ps1 files reformatted via `Invoke-Formatter` — clears 337 whitespace/indent warnings in one verified-balanced (216/216 line) pass. (`bda742c`)
- 6 `$profile` shadowings — renamed locals to `$machineProfile` so PowerShell's automatic `$profile` (the user's profile script path) is no longer clobbered in any toolkit script. (`596e701`)
- 1 null-comparison bug at `lib/toolkit-state.ps1:244` — `$null` now on the left side per PowerShell idiom. (`596e701`)
- 2 empty `catch` blocks in defender wholesale scripts — now log the rejection reason instead of swallowing silently. (`596e701`)
- 10 `$state = Initialize-ToolkitState` dead-write sites — switched to `Initialize-ToolkitState | Out-Null` so the side-effect-only intent is explicit. (`858c8ab`)
- 9 misc unused variables — dead-code removal or pipe-to-Out-Null. One was a real defense-in-depth gap (`debloat.ps1` `$neverRemove`). (`f71d130`)

### Changed
- Analyzer rule exclusions with explicit rationale comments:
  - `PSAvoidUsingWriteHost` — toolkit is interactive UI, not pipeline; quality bar enforces "no `Write-Host` for data" by code review.
  - `PSUseBOMForUnicodeEncodedFile` — `.gitattributes` enforces UTF-8 without BOM; .bat callers don't grok BOMs.
  - `PSUseApprovedVerbs` + `PSUseSingularNouns` — `UI-*` / `Reg-Add` / `Run-Step` / vendor-`Apply-*` / lib-`Ensure-*`+`Capture-*` namespace is cross-script convention; wholesale rename queued as v2.

### Quality-gate progression

| Gate snapshot | Errors | Warnings | Pester passing |
|---|---|---|---|
| Baseline (session start)     | 3 | 1415 | 0 |
| After error fixes            | 0 | 1441 | 0 |
| After rule-policy exclusions | 0 |  434 | 0 |
| After formatter pass         | 0 |   97 | 0 |
| After test foundation        | 0 |   93 | 16 |
| After multi-fix              | 0 |   84 | 16 |
| After verb/noun policy       | 0 |   30 | 16 |
| After state batch            | 0 |   20 | 16 |
| After unused-var batch       | 0 |   11 | 16 |

98%+ analyzer reduction, errors cleared, first Pester suite green. Remaining 11 warnings are all `PSUseShouldProcessForStateChangingFunctions` — addressed next.

---

### 2026-05-24 resumed loop (commits `128a6e2` → `c2795e7`)

Floor moved from 0/0 PSSA + 77 tests to **0/0 PSSA + 243 tests**. Every commit kept the gate green; no reverts fired.

**Added — entry-point Pester suites.** `tests/APPLY-EVERYTHING.Tests.ps1` (15 tests covering the `-IncludeSecurityTradeoffs` gate, BattlEye/EAC text, phase headings, Skip-Step plumbing). `tests/REVERT-EVERYTHING.Tests.ps1` (14 tests; Nagle manifest-first/blind-fallback, DNS / service restore presence, init-before-restore ordering). `tests/9-cleanup/debloat.Tests.ps1` (regression test for f71d130 — `$neverRemove` enforcement). Each script gets a `tests/manual/<name>.md` Windows-runner checklist for what AST can't prove. (`128a6e2`)

**Added — structured logging wiring.** `Write-ToolkitScriptStart` / `Write-ToolkitScriptComplete` in `lib/toolkit-state.ps1` with idempotency via `$script:ToolkitScriptStartLogged`. Auto-invoked by `Initialize-ToolkitState` (SkipFrames=2) so the ~35 mutators that already initialize the manifest get the audit-trail log line for free. The 13 hold-outs got an explicit `Write-ToolkitScriptStart` call (after the admin gate, after lib dot-source). New `tests/invariants/script-start-logging.Tests.ps1` enforces the invariant across the tree — 50 dynamic test cases, one per mutator. (`ecacca7`)

**Added — Windows Sandbox configs.** `tests/sandbox/*.wsb` × 6 (apply default / tradeoffs / WhatIf, debloat, revert-everything, check-storage) + `tools/Start-SandboxSession.ps1` wrapper that substitutes `%REPO%` placeholder into a temp .wsb and launches Sandbox (Windows) or prints inspect-only path (macOS dev). `tests/sandbox/README.md` documents what Sandbox proves and what it doesn't (no reboot persistence, no anti-cheat, no real driver state). (`8ddff76`)

**Added — Phase C user features.**
- `7 network/enable-doh.ps1` + `disable-doh.ps1` — Cloudflare/Quad9/Google DoH templates via `Set-DnsClientDohServerAddress`. Before/after `Resolve-DnsName` metric logged. Sources cited (Microsoft Learn DnsClient, RFC 8484). 14 Pester tests including a "list parity" assertion that disable cleans up every IP enable might register. (`bd7942a`)
- `7 network/enable-rss-tuning.ps1` + `disable-rss-tuning.ps1` — RSS toggle + per-adapter queue count tuned to `min(LogicalCpu, NIC.MaxQueues, 8)`. Sidecar-JSON revert pattern (matches `enable-write-cache-flush.ps1`). 9 tests. (`c7f4710`)
- `5 registry tweaks/individual/tune-mmcss-audio.ps1` + `restore-mmcss-audio.ps1` — Pro Audio scheduling profile (Priority/Category/SFIO/BackgroundOnly) for low-latency audio threads. 14 tests including manifest-Id parity between tune/restore. (`c7f4710`)
- `11 hardware checks/check-uwp-apps.ps1` — FR33THY-style audit-then-decide pattern. Read-only inventory of installed Appx packages cross-referenced with `debloat.ps1`'s `$appsToRemove` + `$neverRemove` via AST walk (no duplicate list maintenance). Supports `-Sort`, `-OnlyDebloatCandidates`, `-AsObject` for pipeline use. 7 tests including a "stays read-only" guard. (`c2795e7`)

**Added — `tests/lib/download-helpers.Tests.ps1`.** Behavioral tests for `Test-FileSha256` (deterministic hash of `"hello world"`) + idempotency of `Ensure-Directory`. Surfaced + fixed a real cross-platform bug: `$env:ProgramData` is null on macOS so dot-sourcing the lib threw. Applied the same `$XDG_DATA_HOME` / `~/.local/share` fallback already in `toolkit-state.ps1` so dev-on-macOS works consistently. 15 tests. (`4910240`)

**Fixed — GPU dot-source path bug.** All 6 scripts in `6 gpu/{nvidia,amd,intel}/` used `$PSScriptRoot\..\lib\*` which resolves to `6 gpu/lib/*` (does not exist) instead of repo root. Worked in practice because the only caller (`install-gpu-driver.ps1`) had already loaded lib helpers into scope, but standalone invocation was silently broken. Corrected to `..\..\lib\*`. `KNOWN-ISSUES.md` entry marked RESOLVED. (`f2a332a`)

**Fixed — invariant-helper alignment.** `Test-ToolkitInvariants` was reading 80 head lines while `Test-ToolkitAdminCheck` was reading 60 (and now 120). Phase C scripts have ~75-line comment-help blocks that pushed the admin check past 80 → false-positive "missing admin guard." Both helpers now use 120 with rationale comment. (`c6498e9`)

### Quality-gate progression (resumed loop)

| Gate snapshot | Errors | Warnings | Pester passing |
|---|---|---|---|
| Resume start (prior session end) | 0 | 0 | 77 |
| After entry-point Pester         | 0 | 0 | 130 |
| After script-start auto-wire     | 0 | 0 | 180 |
| After sandbox additions          | 0 | 0 | 180 |
| After GPU dot-source fix         | 0 | 0 | 180 |
| After DoH                        | 0 | 0 | 194 |
| After RSS + MMCSS                | 0 | 0 | 220 |
| After invariant-helper alignment | 0 | 0 | 220 |
| After download-helpers tests     | 0 | 0 | 235 |
| After check-uwp-apps             | 0 | 0 | 243 |

---

### 2026-05-24 third loop (commits `9d8781b` → `f5387af`, 10 commits)

Architecture-over-wiring focus: every change either promotes a repeated
pattern to a library helper OR adds a repo-wide invariant that catches
the next instance of a class of bug. Floor moved from
**0/0 PSSA + 258 tests** to **0/0 PSSA + 468 tests** (+210 tests, +14
of which from one new user-facing feature; the rest from architecture).

**arch(lib) — sidecar pattern promoted to lib helpers.** Three existing
callers had hand-rolled `ConvertTo-Json | Out-File ... | Test-Path |
Get-Content | ConvertFrom-Json` block-pairs for per-device state
capture. Extracted to `Save-ToolkitSidecar` / `Read-ToolkitSidecar` /
`Remove-ToolkitSidecar` / `Get-ToolkitSidecarPath` in
`lib/toolkit-state.ps1` with capture-once semantics, `-Force` override,
single-element JSON unwrapping, `SupportsShouldProcess`, and per-test
temp-root override for behavioral tests. Refactored 3 call-site pairs
(RSS, IM, write-cache-flush) with measurable diff shrink: **-25, -21,
-9 net lines** in each pair. New `tests/lib/sidecar-helpers.Tests.ps1`
× 14 covers the contract end-to-end. (`9d8781b` → `65a7c9f`)

**arch(tests) — templated sweep for `5 registry tweaks/individual/`.**
Single-template Pester suite (`tests/5-registry-tweaks/individual-tweaks.Tests.ps1`)
walks every `.ps1` in the folder and asserts the standard matrix:
parses, comment-based help present, admin self-check, script-start
audit-log, apply uses tracked helper, restore uses tracked helper.
360+ test cases generated from one template. Gap-tracking pattern
(`$HelpGaps` × 20, `$ApplyHelperGaps` × 2, `$RestoreHelperGaps` × 3)
uses `Set-ItResult -Skipped` inside the It body — Pester v5's `-Skip`
parameter doesn't filter per-ForEach-case, so this is the working
workaround. Same gap-shrink-per-commit pattern as the prior loop's
invariant suites. (`9efde6a`)

**arch(invariants) — three new repo-wide sweeps.** All three use the
same "iterate, classify, assert, gap-track" shape:
- `tests/invariants/mutator-shouldprocess.Tests.ps1` — 44 mutators
  validated, 9 tracked gaps. Catches scripts that mutate via raw
  native calls (`bcdedit`, `sc.exe`, `fsutil`) without opening a
  ShouldProcess gate — PSScriptAnalyzer's `PSShouldProcess` rule
  only inspects function-level mutators, missing script-body ones.
  (`5c2b9d0`)
- `tests/invariants/mutator-paired-restore.Tests.ps1` — 46 pairs
  validated, 7 tracked gaps. Enforces CLAUDE.md's "every opt-in tweak
  ships with a colocated `enable-*`/`revert-*` sibling" rule by
  computing the inverse-prefix stem (configurable map covering
  disable↔enable, install↔uninstall, configure↔revert|restore|
  disable|enable, force↔revert|disable, apply↔revert, pause↔resume,
  tune↔restore, optimize↔revert) and asserting `Test-Path` on the
  candidate sibling (`.ps1` OR `.bat` — `configure-vbs.ps1` legitimately
  pairs with `enable-vbs.bat`/`disable-vbs.bat`). (`74e18c3`)
- `tests/invariants/downloader-trust-verify.Tests.ps1` — 4/4 compliant.
  Any `.ps1` calling `Invoke-WebRequest -OutFile`, `Get-FileFromWeb`,
  `.DownloadFile`, or `Start-BitsTransfer` must also call one of
  `Get-FileHash` / `Test-FileSha256` / `Get-AuthenticodeSignature` /
  `Test-FileAuthenticode` in the same file. Discriminates file-download
  from metadata-fetch via `-OutFile` presence (in-memory JSON reads
  correctly excluded). Regression-net for "added a new downloader
  without a verifier." (`74fa679`)

**feat(storage-sense) — disable/enable pair from the deferred queue.**
Single-key toggle at `HKCU:\...\StorageSense\Parameters\StoragePolicy\01`
(DWORD). Anti-cheat impact NONE (UWP/settings feature). Microsoft
Learn cited. Restore-from-manifest with delete-key fallback when no
prior value captured. Verify-tweaks.ps1 grew a corresponding check.
(`6c81e16`)

**feat(gate) — `-Coverage` non-gating CodeCoverage report.** Coverage
on `lib/*.ps1` (the long-lived helper surface; per-script files are
runtime-untestable from dev macOS, so including them would dilute the
signal). JaCoCo XML output to `coverage.xml` (gitignored). Summary row
shows rounded percent; row suppressed entirely when `-Coverage` not
passed so the default summary stays terse. Baseline: 10.2% on
lib helpers. (`f5387af`)

### Quality-gate progression (third loop)

| Gate snapshot | Errors | Warnings | Pester passing | Skipped |
|---|---|---|---|---|
| Loop start (resume) | 0 | 0 | 258 | 0 |
| After sidecar lib + 3 refactors | 0 | 0 | 275 | 0 |
| After templated sweep | 0 | 0 | 360 | 25 |
| After ShouldProcess invariant | 0 | 0 | 404 | 34 |
| After pair-restore invariant | 0 | 0 | 450 | 41 |
| After downloader-trust invariant | 0 | 0 | 454 | 41 |
| After Storage Sense pair | 0 | 0 | 468 | 41 |
| After -Coverage flag | 0 | 0 | 468 | 41 |

---

### 2026-05-24 fourth loop (commits `f44609c` → `92e9c3c`, 8 commits)

Theme: zero out both gap arrays + ship the deferred Phase C trio. Floor
moved from **0/0 PSSA + 474 Pester / 35 skip** to **0/0 PSSA + 518 Pester
/ 23 skip + 11.1% coverage**. Every invariant suite at 100% compliance.

**fix(shouldprocess) — close the final 3 gaps; invariant 100%.** Three
scripts using raw native calls (`bcdedit`, `sc.exe`, `Start-Process` on
installers, `Set-NetAdapterPowerManagement`) got `[CmdletBinding(Supports
ShouldProcess)]` and per-call gates. `enable-windows-update.ps1`
collapsed 3 hand-copied 4-line `sc.exe config` blocks into a
data-driven foreach. `install-runtimes.ps1` gated its Start-Process
chain inline; spawned a separate task for a latent `continue`-outside-
loop bug. `enable-adapter-power-savings.ps1` used the canonical
hoisted-gate pattern in both branches (sidecar + defaults fallback).
ShouldProcess invariant: 50/53 → **53/53 (100%)**. (`f44609c`)

**arch(lib) — gpu-uninstall helper + 3 vendor wrappers.** Three of seven
pair-script gaps had identical shape (missing uninstall-`<vendor>`.ps1
per GPU install-`<vendor>`.ps1). Architecture pre-check: build the
upstream helper FIRST, then thin wrappers. New `lib/gpu-uninstall.ps1`
exposes `Get-GpuDriverPublisherPattern`, `Get-InstalledGpuDriver
Packages` (parses `pnputil /enum-drivers`), and `Uninstall-GpuDriver
ByPublisher` (gates each `pnputil /delete-driver` via $PSCmdlet.Should
Process). Cross-platform safe (returns @() on non-Windows). 7
behavioral tests cover the contract. Three vendor wrappers
(`uninstall-{nvidia,amd,intel}.ps1`) call the helper and recommend
DDU follow-up. Caught `$matches` automatic-variable shadowing during
gate run — renamed to `$pkgMatches` everywhere with explanatory
comments. (`127fda2`)

**fix(rename) — finalize explorer-affinity rename + clear all pair
gaps.** External worktree changes renamed `explorer-affinity-core1`
→ `disable-explorer-affinity` and `restore-explorer-affinity` →
`enable-explorer-affinity` (now match the verb-prefix rule).
Companion commits updated all inter-script references, the templated
sweep's pair table, and the gap list. A separate external change
added `revert-power.ps1` and renamed `revert-all.ps1` →
`enable-services.ps1` — closing the last two pair gaps. **Pair
invariant: 46/53 → 56/56 (100%).** (`53c498e`, `bbc40e0`)

**feat(hardware) — check-input-polling.ps1 read-only HID audit.**
Walks `Get-PnpDevice` for Mouse / Keyboard / HIDClass and reports
each device's friendly name, parsed VID/PID, registry-claimed
SampleRate, and an interpretation note (1000+ Hz OK, etc.).
`-AsObject` switch for pipeline use. Read-only by design with a
regression test that fails the suite if any tracked-write helper
or `sc.exe` leaks in. Phase A foundation for a planned
`check-mouse-polling.ps1` that downloads MouseTester with SHA-256
verify (the new downloader will pass the trust-verify invariant
automatically). Caught `$pid` automatic-variable shadowing during
gate — renamed to `$devPid` with explanatory comments. (`2de14ea`)

**feat(mpo) — WDDM 2.7 gate + full Phase C polish on disable-mpo.**
`OverlayTestMode` is silently ignored below WDDM 2.7 (Windows 10
build 18363 / 1909). Setting a manifest entry for a phantom write
would mislead the user on revert, so the script now fails CLOSED
below 18363 with an explicit "your build doesn't support this"
message. Reframed banner header as full `<# .SYNOPSIS / .DESCRIPTION
/ .NOTES #>`: case-for, case-against, before/after metric (DxDiag
Plane Count), anti-cheat impact NONE, Microsoft Learn citations
for both WDDM 2.7 features and DWM MPO registry docs. (`00cab05`)

**feat(hags) — enable-hags + disable-hags pair, [Experimental]
gated.** Standalone HAGS toggle extracted from the bundled APPLY
flow (where HwSchMode=2 lands as part of windows-settings).
`enable-hags.ps1` requires `-Experimental` switch and refuses to
run without it, citing 24H2 (build 26100+) / 25H2 (26200+) WDDM
scheduler regression reports on multiple NVIDIA driver branches
(566.x, 572.x, 576.x) with symptoms (frame-time variance, stutter
regression, TDR events). `disable-hags.ps1` writes HwSchMode = 1
(documented "OS scheduler" value, not just delete-the-key — fresh
installs vary by GPU vendor). Header anti-cheat impact NONE.
Microsoft Learn cited. (`5a8b0e9`)

**docs(CLAUDE.md) — codify three rules earned constitutional
status.** Architecture-over-wiring, gap-tracking-not-silenced, and
ShouldProcess-hoist-out-of-UI-Step are now standing rules with
the canonical reference scripts cited. Added "don't shadow
PowerShell automatic variables" to Known gotchas with the top-5
offenders ($matches, $pid, $profile, $error, $host) listed. (`92e9c3c`)

### Quality-gate progression (fourth loop)

| Gate snapshot | Errors | Warnings | Pester | Skipped | Coverage |
|---|---|---|---|---|---|
| Loop start (post-batch)              | 0 | 0 | 474 | 35 | 10.2% |
| After 3 ShouldProcess gaps closed    | 0 | 0 | 477 | 32 | 10.2% |
| After GPU uninstall trio (lib + 3)   | 0 | 0 | 490 | 29 | 11.1% |
| After explorer-affinity rename       | 0 | 0 | 494 | 25 | 11.1% |
| After $PairGaps cleared              | 0 | 0 | 496 | 23 | 11.1% |
| After check-input-polling            | 0 | 0 | 504 | 23 | 11.1% |
| After MPO WDDM gate                  | 0 | 0 | 504 | 23 | 11.1% |
| After HAGS pair                      | 0 | 0 | 518 | 23 | 11.1% |
| After CLAUDE.md rule codification    | 0 | 0 | 518 | 23 | 11.1% |

## [1.0.0] — 2026-05-07

First public release. The toolkit went through three predecessor passes (FR33THY integration + bug audit, codex verification + discovery, cleanup + launcher redesign) and a final production-readiness audit before this tag.

### Added
- Manifest-aware launcher (`launcher.ps1`) with header status (`Admin: yes/no`, `Build: <number>`, `Manifest: <N> entries`), per-category risk-tier coloring (`Safe` green, `Advanced` yellow, `Trade-off` red), and per-category status indicators (`[OK] applied` / `! drift`). ASCII fallback engages automatically in PowerShell ISE or terminals narrower than 80 columns.
- Twelve FR33THY/Ultimate-derived tweak scripts with paired reverts: `disable-mpo.ps1` / `enable-mpo.ps1`, `configure-mmagent.ps1` / `revert-mmagent.ps1`, `disable-adapter-power-savings.ps1` / `enable-adapter-power-savings.ps1`, `disable-ipv6-binding.ps1` / `enable-ipv6-binding.ps1`, `disable-spectre-meltdown.ps1` / `enable-spectre-meltdown.ps1`, `disable-dep.ps1` / `enable-dep.ps1`, `force-p0-state.ps1` (NVIDIA-gated), `configure-amd-ulps.ps1` (AMD-gated), `disable-write-cache-flush.ps1` / `enable-write-cache-flush.ps1` (opt-in due to data-loss risk), `disable-edge-background.ps1` / `enable-edge-background.ps1`, `disable-ntfs-last-access.ps1` / `enable-ntfs-last-access.ps1`, `mobsync-disable.ps1` / `mobsync-enable.ps1`. See `docs/freethy-integration.md` for the full inventory.
- Single-source-of-truth `VERSION` file at repo root; `lib/toolkit-state.ps1` reads it; `launcher.ps1` header pulls from `$script:ToolkitVersion`.
- Quick actions in launcher: `[A]` Apply All, `[V]` Verify status, `[R]` Revert All — each dispatches directly to the existing top-level scripts.
- Tools menu: `[M]` View manifest, `[L]` View recent log (under `%ProgramData%\Win11GamingToolkit\logs`), `[B]` Regenerate baseline (after typed `YES` confirm), `[?]` Help.
- Shared `Get-ToolkitLogRoot` helper in `lib/toolkit-state.ps1` for log-tail lookups.
- `MANUAL-TEST-CHECKLIST.md` — sixteen-section runtime gate the owner runs on Win11 before promoting the tag publicly.
- `PRODUCTION-READY.md` documenting the audit pass-fail matrix and accepted deviations.
- `BIOS-CHECKLIST.md` Diagnostic Tools appendix listing HWInfo64, GPU-Z, CPU-Z, MemTest86, CrystalDiskInfo, LatencyMon, Furmark, OCCT.

### Changed
- Launcher menu structure: from a single flat letter-keyed list to a tiered three-section layout (Quick actions / Categories / Tools) with category submenus per numbered folder.
- `APPLY-EVERYTHING.ps1` no longer calls `Initialize-ToolkitState -ForceNew`, preserving captured `before` state across re-applies. (Codex audit fix A3.)
- GPU MSI mode now targets only real graphics adapters (`VEN_10DE` NVIDIA, `VEN_1002` AMD, `VEN_8086` Intel) via `Get-GpuVendor`; virtual displays (Microsoft Basic Display, IDD, OBS Virtual Cam, Parsec) are excluded. Revert is manifest-driven via the `gpu-msi` step key. (Codex audit fix A2.)
- `enable-ultimate-performance.bat` activates the Ultimate Performance plan via fixed GUID + `powercfg -duplicatescheme`, removing the locale-dependent `for /f "tokens=4"` parse of `powercfg -list` output. (Codex audit fix A9.)
- DDU + WinUtil downloads compute SHA-256 against an expected hash in `versions.json` / a constant in the wrapper script, and refuse to execute on mismatch. (Audit fixes A6 + A7.)
- DNS state capture now keys on both `InterfaceIndex` and `AddressFamily`, so IPv4 and IPv6 entries for the same adapter are tracked separately. Revert restores both families.
- `verify-tweaks.ps1` footer uses canonical `Security Trade-off` (capitalized, hyphenated) instead of `Security-tradeoff`. Brought into line with the launcher's display-label convention.

### Fixed
- **A1**: `visual-effects-performance.reg` writes `UserPreferencesMask` as `REG_BINARY` (`hex:`), not `REG_EXPAND_SZ` (`hex(2):`).
- **A4**: `APPLY-EVERYTHING.ps1` cleanup phase guards the `C:\inetpub` removal with `Get-WindowsOptionalFeature -FeatureName IIS-WebServer`, so IIS / IIS Express setups are not destroyed.
- **A5**: `install-timer-resolution-service.ps1` prints the probed `csc.exe` path and a clear DISM recovery hint when the .NET Framework 4 compiler is missing on stripped images.
- **A8**: WaaSMedicSvc DACL recovery sequence (`takeown` + `icacls`) is documented in `GUIDE.md` Troubleshooting for Windows 24H2 / 25H2.
- **A10**: `Restore-ToolkitRegistryValue` parenthesizes `Test-Path` so its `-and` clause is not bound as a `Test-Path` parameter.
- Manifest preservation across re-runs: `Set-ToolkitRegistryValue` guards against overwriting an existing entry's `before` block.
- Phase 1 cleanup integrity: dropped the stale `.claude/launch.json` VS Code debug config that referenced the removed `website/` directory.

### Removed
- The entire `website/` Next.js landing site (30 tracked files, ~11.5k lines). The toolkit is the only deliverable.
- `lib/launcher-menu.ps1` (orphaned by the launcher rewrite — the new launcher embeds menu definitions inline).
- Build-tooling entries from `.gitignore` that referenced `website/.next/`, `website/out/`, `node_modules/`, and `firebase-debug.log`.
- Branches: `codex/audit-extend-win11-toolkit` (merged), `CC/hardcore-rubin-7d2584` (subset of codex), `claude/implement-todo-item-9uEXR` (website-only commit), `claude/add-claude-documentation-zxdYP` (orphan CLAUDE.md).

### Documented for next release (non-blocker, see `KNOWN-ISSUES.md`)
- `APPLY-EVERYTHING.ps1` Nagle write at lines 399–400 bypasses `Set-ToolkitRegistryValue`. The standalone `7 network/optimize-network.ps1` uses the helper. Convert APPLY's block in v1.1 so REVERT can restore Nagle defaults.
- Startup-cleanup `reg delete` calls (OneDrive / Teams autostart) are intentional vendor-default policy applies. Revert depends on the user re-launching the affected app.
- Power-Plan `Attributes` write at line 163 unhides a hidden setting (metadata, not behavior). No tier tag needed.
- Notice.txt scope: lineage credit only (Khorvie Tech). Broader credits are in `GUIDE.md`. Owner decision in `CHANGES.md` Q2.

### Design deviation
- The launcher omits a `[3] Privacy / telemetry` category. The repo's numbered-folder layout has no `3 privacy/`; privacy tweaks (`privacy-telemetry.reg`, `disable-edge-background.ps1`, `disable-windows-update.ps1`) live in `5 registry tweaks/individual/` and are reachable via `[5]` Registry tweaks → submenu. Documented in `CLEANUP.md`.

[1.0.0]: https://github.com/cococool13/TweakEazy/releases/tag/v1.0.0
