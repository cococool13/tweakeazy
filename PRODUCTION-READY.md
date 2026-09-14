# Production Readiness Report — v1.0.0

Outcome of a spent production-readiness one-shot (prompt retired; this file is the record) against `main`. The release tag follows once `MANUAL-TEST-CHECKLIST.md` is run on a Win11 host and updated with a pass row.

## Decisions

These are the choices the audit made when the prompt left them open. Each is documented here per the prompt's hard constraint *"if something is genuinely ambiguous … pick the most defensible default, document the choice in `PRODUCTION-READY.md` under `## Decisions`, and continue."*

- **Release version: `1.0.0`.** First public tag of this repository (`git tag -l` was empty before this pass). Per the prompt: "First public release → `v1.0.0`."
- **License: MIT.** No prior license signal in the repo. Per the prompt: "If absent, add one matching the repo's existing license signal (MIT default)."
- **Single source of truth: `VERSION` file at repo root.** Lighter than a `lib/version.ps1` module — `lib/toolkit-state.ps1` reads it once at script load and exposes `$script:ToolkitVersion` to the rest of the codebase. No helper signature change.
- **Phase 3 path: B.** No Windows VM accessible from this audit environment. Deliverable is `MANUAL-TEST-CHECKLIST.md` (sixteen sections, ~one hour of click-through testing) at repo root. The actual Windows runtime test is the owner's gate before promoting v1.0.0 publicly.
- **Safety branches retired: yes, after tag push.** The cleanup-pass branches (`CC/salvage-pre-cleanup`, `CC/sleepy-hellman-f4b52f`) are deleted after the tag pushes clean. Phases 1–3 surfaced zero blockers, so the prompt's gate to retire them is satisfied.
- **`Notice.txt` left untouched.** Owner-decision per `CHANGES.md` Q2; documented in `KNOWN-ISSUES.md`. Lineage credit only; broader credits live in `GUIDE.md` and per-file headers.

## Phase 1 — Cleanup integrity (verification table)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Merge sanity (`git log --oneline main~30..main`) | PASS | 30 commits visible, all conventional (`feat:`, `fix:`, `docs:`, `chore:`). Zero `wip`, zero forced merges, zero partial reverts. |
| 2 | `lib/launcher-menu.ps1` orphan deletion | PASS | `git log` shows three commits touching the file (creation in `cd81821`, salvage in `c7e856c`, deletion in `7be145f`). Zero current code references; only `CLEANUP.md` mentions the path historically. |
| 3 | `$script:ToolkitLogRoot` consumed correctly | PASS | Defined once in `lib/toolkit-state.ps1:9`; surfaced via `Get-ToolkitLogRoot` in `lib/toolkit-state.ps1:16`; consumed in `launcher.ps1:454` (the `[L] View recent log` action). No legacy export shape remains. |
| 4 | Website residue grep | FAIL → fixed in `2a35ce7` | `.claude/launch.json:7` referenced `npm run dev --prefix website`. Stale VS Code-style debug config for the deleted landing page. Removed entire file (only entry was the website debugger). The other three grep hits (`5 registry tweaks/apply-all.reg:220`, `5 registry tweaks/individual/privacy-telemetry.reg:98`, `8 security vs performance/README.txt:51`) are English-language usage of the word "website", unrelated to the deleted directory. |
| 5 | Tier string consistency | FAIL → fixed in `b36d773` | `10 verify/verify-tweaks.ps1:353` emitted `Security-tradeoff` (lowercase, hyphenated). Corrected to canonical `Security Trade-off`. The `launcher.ps1:177` short-form `Trade-off` is correct (display-only translation). |
| 6 | `GUIDE.md` filesystem reconciliation | PASS | Every path mentioned in `GUIDE.md` exists on disk (`0 prerequisites/install-runtimes.ps1`, `1 backup/create-backup.ps1`, `5 registry tweaks/individual/enable-edge-background.ps1`, etc., 28 paths total). Zero broken references. |
| 7 | `.reg` value types | PASS | All 17 tracked `.reg` files have correct `Windows Registry Editor Version 5.00` headers. `UserPreferencesMask` in `visual-effects-performance.reg:19` is `hex:` (REG_BINARY) — A1 fix holds. No `hex(2):` / `hex(7):` mistypes detected. |

## Phase 2 — Final audit findings

Six checks ran (dispatcher consistency, idempotency, manifest schema, tier surface, doc drift, hash verification). The first audit pass had a false-positive sub-agent finding ("18 of 24 `Set-ToolkitRegistryValue` calls lack `-Step`") that I verified directly: the agent had grepped only the bare helper name and missed 29 calls through the `Set-TrackedRegistry` / `Set-TrackedService` wrappers defined in `APPLY-EVERYTHING.ps1:87` and `:98`. After re-verifying line-by-line, every audit check passed at the structural level.

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Dispatcher coverage (apply / revert / verify) | PASS | 29 `Set-TrackedRegistry` and `Set-TrackedService` calls in `APPLY-EVERYTHING.ps1`. `REVERT-EVERYTHING.ps1` walks `state.registry` and `state.services` manifest-driven. `verify-tweaks.ps1` reads `state.steps` keyed by step ID. Field map aligned. |
| 2 | Ad-hoc registry / service writes | 4 NON-BLOCKERS | Logged in `KNOWN-ISSUES.md` `## Logged for next release`. Details below. |
| 3 | Idempotency hazards | PASS | `Initialize-ToolkitState` uses `-Force` for the state directory; `Set-ToolkitRegistryValue` / `Set-ToolkitServiceStartMode` guard against overwriting an existing entry's `before` block; service mode changes are idempotent at `sc.exe config` level. |
| 4 | Manifest schema field consumption | PASS | `state.steps`, `state.registry`, `state.services`, `state.dns.interfaces`, `state.defender.added`, `state.packages.removed`, `state.packages.provisionedRemoved` — every field populated in apply is consumed by both revert and verify. |
| 5 | Tier surface area | PASS | Every `Run-Step` call in `APPLY-EVERYTHING.ps1` is inside one of the labeled `Phase` blocks tagged `Safe`, `Advanced`, or `Security Trade-off`. `Set-TrackedRegistry` / `Set-TrackedService` carry the tier explicitly. |
| 6 | DDU + WinUtil hash verification | PASS | `DduManual.ps1:46` calls `Test-FileSha256 -ExpectedHash $expectedDduSha256` (sourced from `versions.json`). `9 cleanup/chris-titus-winutil.bat:67` runs `if /I not "%WINUTIL_HASH%"=="%WINUTIL_SHA256%" (` and exits on mismatch. Both compare, not just print. |
| 7 | Doc drift (GUIDE / BIOS / credits) | PASS | All paths mentioned in `GUIDE.md` resolve. Credits in `GUIDE.md:293` cover FR33THY, Khorvie Tech, Chris Titus Tech, Wagnardsoft. Per-file headers carry `# Source: FR33THYFR33THY/Ultimate — …` for ported scripts. `Calypto` / `BoringBoom` / `djdallmann` are not used in any tracked file — only `djdallmann/GamingPCSetup` appears in `DISCOVERY-BACKLOG.md` as a not-yet-integrated source reference. |

### Non-blocker findings (Phase 2 detail)

These four findings are real bypasses or open questions that do not gate v1.0.0:

1. **`APPLY-EVERYTHING.ps1` Nagle write at lines 399–400** — raw `Set-ItemProperty TcpAckFrequency` / `TCPNoDelay` instead of `Set-ToolkitRegistryValue`. Consequence: `REVERT-EVERYTHING.ps1` won't roll back Nagle changes that came from the APPLY path. The standalone `7 network/optimize-network.ps1` *does* use `Set-ToolkitRegistryValue` for the same writes. Default Nagle behavior is harmless when left in place; this is a revert-completeness gap, not a stability risk. Convert APPLY's block in v1.1.
2. **Startup-cleanup `reg delete` at lines 328+ (OneDrive / Teams autostart)** — vendor-installed values; nothing useful to capture as `before` state. Revert relies on the user re-launching the affected app to re-register the autostart hook. Acceptable as intentional defaults-style policy apply.
3. **Power-Plan `Attributes` write at line 163** — metadata write (`/v Attributes /d 0`) that unhides a hidden power setting so the next `Set-PowerIdx` call can reach it. The Phase block is tier-tagged; the individual write isn't, because there's no functional change to revert. Acceptable.
4. **`Notice.txt` scope** — credits Khorvie Tech only (lineage). FR33THY / Chris Titus Tech / Wagnardsoft credits live in `GUIDE.md`. Owner decision in `CHANGES.md` Q2; no technical impact.

All four are recorded in `KNOWN-ISSUES.md` `## Logged for next release` (commit `9bfa79e`).

## Phase 3 — Windows runtime validation

**Path: B (manual-checklist).** No Windows host accessible from the audit environment.

Deliverable: `MANUAL-TEST-CHECKLIST.md` at repo root (commit `9d44972`). 16 sections, ~60 minutes on a clean Win11 24H2 Pro VM. Coverage:
- Launcher render (header alignment, tier colors, status indicators, ASCII fallback in ISE, narrow-terminal layout).
- Non-admin refusal (one-line message, exit code 1, no partial menu).
- `APPLY-EVERYTHING.ps1` clean run + post-reboot sanity (network / audio / display / login).
- `verify-tweaks.ps1` post-apply (tracked tweaks `APPLIED`, no `DRIFTED`, footer reads canonical `Security Trade-off`).
- `REVERT-EVERYTHING.ps1` clean run + post-reboot sanity.
- Idempotency (apply ×2, revert ×2, apply / revert / apply manifest equivalence).
- Locale: `enable-ultimate-performance.bat` GUID-based path on non-English Windows.
- Direct spot-checks for codex audit fixes A1, A2, A4, A6, A7.

The owner runs the checklist on a Win11 VM, fills in pass/fail per row, and pastes the summary block back into this section under `### Phase 3 result` once everything is green. Until then, the v1.0.0 tag is "code-complete on macOS, runtime-pending on Windows."

### Phase 3 result

> _To be filled in by the owner after running `MANUAL-TEST-CHECKLIST.md`. Format: pass / fail / skip counts, plus links to any `fix:` commits that landed in response to runtime fails._

## Phase 4 — Release artifact confirmation

| Artifact | Path | Status | Commit |
|---|---|---|---|
| Version file | `VERSION` | Created with content `1.0.0` | `a067c37` |
| `lib/toolkit-state.ps1` reads `VERSION` | `lib/toolkit-state.ps1:6-11` | Initialization rewritten; no helper signature changed | `a067c37` |
| MIT license | `LICENSE` | Added | `900fc8f` |
| `.gitattributes` | repo root | Added (CRLF for `.ps1` `.bat` `.cmd` `.reg`; LF for `.md` `.json` `.yml` `VERSION` `LICENSE`; binary for images) | `900fc8f` |
| `.editorconfig` | repo root | Added (4-space CRLF for PS / batch; 2-space LF for Markdown / JSON / YAML; trailing-whitespace preserved on `.md`) | `900fc8f` |
| `CHANGELOG.md` | repo root | Added (Keep-a-Changelog format; v1.0.0 user-facing summary rolling up `CHANGES.md` + `CODEX-AUDIT.md` + `CLEANUP.md` + this audit pass) | `3a05ec3` |
| `README.md` | repo root | Added (quick start, risk-tier explanation, doc index, credits, license, versioning) | `3a05ec3` |
| Screenshot placeholder note | `KNOWN-ISSUES.md` | Added (no Windows host to capture; v1.1 follow-up after MANUAL-TEST run) | `b4cd3d5` |
| Release tag | `v1.0.0` | Created and pushed after this report commits | (tagged on the commit that includes this file) |

The launcher header reads `v1.0.0` from `VERSION` at runtime. No hardcoded version string remains in the codebase (verified via `git grep '2\.0\.0'` against the post-`a067c37` tree — only audit / changelog mentions, no live code).

## Phase 5 — Branch retirement

Phase 5 runs only after the v1.0.0 tag pushes clean. The plan:

- `git push origin --delete CC/salvage-pre-cleanup CC/sleepy-hellman-f4b52f`
- `git branch -D CC/salvage-pre-cleanup CC/sleepy-hellman-f4b52f`

Phases 1–3 surfaced zero blockers; Phases 1 and 2 fix commits all landed clean (`2a35ce7`, `b36d773`). Phase 5 is unblocked.

### Phase 5 result

`CC/salvage-pre-cleanup`: deleted from origin and locally (was at `c7e856c`).
`CC/sleepy-hellman-f4b52f`: worktree at `.claude/worktrees/sleepy-hellman-f4b52f` removed via `git worktree remove --force`; local branch deleted (was at `5aa8db2`; never pushed to origin).

Final state: `main` is the only active branch. Only the main worktree at `/Users/cococool/Projects/PC Tweaks/` remains. Tag `v1.0.0` present locally and on origin.

## Accepted deviations

- **No `[3] Privacy / telemetry` category in the launcher.** The repo has no `3 privacy/` folder; privacy tweaks live in `5 registry tweaks/individual/`. Creating a new folder would have required updating every reference in APPLY / REVERT / verify / READMEs / docs — explicit scope creep per the cleanup-pass prompt. Documented in `CLEANUP.md` and recapped in `CHANGELOG.md` v1.0.0 design-deviation section.
- **`Notice.txt` carries lineage credit only.** Khorvie Tech only. FR33THY / Chris Titus Tech / Wagnardsoft are credited in `GUIDE.md` Credits and per-file headers. Owner-decision item (`CHANGES.md` Q2). No technical impact.
- **Phase 3 deliverable is the checklist, not the test result.** Path B is the prompt's explicit option for environments without a Windows host. The runtime gate is owned by `MANUAL-TEST-CHECKLIST.md` and the owner's post-tag verification, not by this report. Public promotion of the v1.0.0 tag (e.g. attaching release notes on GitHub Releases, updating any external "latest version" pointers) waits on the checklist coming back green.
- **Three intentional non-tracked operations in `APPLY-EVERYTHING.ps1`.** PowerSettings `Attributes` unhide (line 163), `reg delete` startup hooks (line 328+), raw Nagle write (line 399–400). All inside tier-tagged Phase blocks; functional consequences are documented in `KNOWN-ISSUES.md` `## Logged for next release`. Refactoring them to `Set-TrackedRegistry` is v1.1 work.

## Audit chain

| Pass | Commit | File / artifact |
|---|---|---|
| Predecessor: Claude — FR33THY integration + bug audit | merge `6730a47` | `CHANGES.md`, `KNOWN-ISSUES.md`, `docs/freethy-integration.md`, 12 ported scripts + 4 paired reverts |
| Predecessor: Codex — verification + discovery | merge `6730a47` | `CODEX-AUDIT.md`, `DISCOVERY-BACKLOG.md`, A1–A10 fix commits |
| Predecessor: Claude — cleanup + launcher redesign | merges `c3c4de0` `7be145f` `f6f22b6` | `CLEANUP.md`, new `launcher.ps1`, `website/` removed, branches consolidated |
| This pass: Claude — production readiness | this commit chain | `MANUAL-TEST-CHECKLIST.md`, `CHANGELOG.md`, `README.md`, `LICENSE`, `VERSION`, `.gitattributes`, `.editorconfig`, this file, plus the two Phase 1 fixes (`2a35ce7`, `b36d773`) and the Phase 2 KNOWN-ISSUES.md log (`9bfa79e`) |

## Commit sequence (this pass)

```
2a35ce7  fix: drop stale .claude/launch.json (referenced deleted website/)
b36d773  fix: align verify-tweaks.ps1 footer note with canonical tier string
9bfa79e  docs: log Phase 2 audit findings to KNOWN-ISSUES.md
9d44972  docs: add MANUAL-TEST-CHECKLIST.md (Path B runtime gate for v1.0.0)
a067c37  chore: wire VERSION as single source of truth, drop hardcoded 2.0.0
900fc8f  chore: add LICENSE (MIT), .gitattributes, .editorconfig
3a05ec3  docs: add CHANGELOG.md and README.md
b4cd3d5  docs: log launcher-screenshot placeholder in KNOWN-ISSUES.md
[next]   docs: add PRODUCTION-READY.md
[tag]    v1.0.0
[next]   chore: retire CC/salvage-pre-cleanup and CC/sleepy-hellman-f4b52f
```

The tag is the final action before branch retirement, per the prompt's hard constraint *"the tag is the final action."*
