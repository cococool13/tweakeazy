# Win11 Gaming Toolkit — Claude Context

PowerShell + batch toolkit for tuning Windows 11 gaming PCs. Manifest-tracked,
reversible, no bundled binaries. Currently v1.0.0 (`VERSION` is single source).

## ⚠️ Dev environment vs. runtime

Development happens on macOS. The toolkit runs on Windows 11 only. Nothing in
this repo can be executed or runtime-tested from here — `MANUAL-TEST-CHECKLIST.md`
is the human gate before any new tag. Never claim a change is "tested" without a
checklist run; mark it "code-complete, runtime-pending."

## Core invariants (do not violate)

1. **Every tweak declares a risk tier**: `Safe` / `Advanced` / `Security Trade-off`.
   The launcher color-codes them (green / yellow / red). New scripts pick one
   and tag the `Run-Step` / `Phase` block in `APPLY-EVERYTHING.ps1`.
2. **All tracked writes go through helpers** in `lib/toolkit-state.ps1`:
   `Set-ToolkitRegistryValue`, `Set-ToolkitServiceStartMode`, or the
   `Set-TrackedRegistry` / `Set-TrackedService` wrappers in `APPLY-EVERYTHING.ps1`.
   Raw `Set-ItemProperty` / `sc.exe config` bypasses revert. (Known untracked
   writes are catalogued in `KNOWN-ISSUES.md` → `## Logged for next release`.)
3. **PowerShell 5.1 compatibility**. No PS 7-only syntax: no ternary `? :`,
   no `??` / `??=`, no `&&` / `||` in pipelines. Test mentally against
   Windows PowerShell 5.1 (the inbox version on Win11).
4. **No bundled binaries.** Third-party tools (DDU, WinUtil) are downloaded at
   runtime and verified by SHA-256 against `versions.json`. Hash mismatch must
   abort, never warn-and-continue.
5. **Manifest is the rollback contract.** State lives at
   `%ProgramData%\Win11GamingToolkit\state\manifest.json` with keys
   `state.steps` / `state.registry` / `state.services` / `state.dns.interfaces` /
   `state.defender.added` / `state.packages.removed`. Every field populated by
   APPLY must be consumed by REVERT and verify.
6. **Every mutating script self-checks admin.** Use `UI-RequireAdmin` (or an
   inline `IsInRole(Administrator)` check) at the top of every `.ps1` / `.bat`
   that writes registry, services, or files. Scripts must fail fast on their
   own — do not assume a parent script already elevated.

## Scope: nothing is permanently off-limits

Hard constraints are only **(a) the PC still boots after Apply + reboot** and
**(b) games still run**. Anything else is fair game — including items currently
listed in `KNOWN-ISSUES.md` as previously declined from FR33THY/Ultimate
(wholesale Defender disable, UAC lowering, Firewall disable, SmartScreen /
Mark-of-the-Web disable, driver-signing bypass, SMT / Hyper-Threading disable,
single-core Explorer affinity, inbox-NVMe driver swap, HDCP disable, etc.).

When asked to add any such item:

- Classify at the right tier — most belong in `Security Trade-off`.
- Make it reversible through the manifest (`Set-TrackedRegistry` /
  `Set-TrackedService`). If it's truly not reversible, document that in the
  header and provide a paired `enable-*` / `restore-*` script.
- Ship it **opt-in only** — do NOT add to `APPLY-EVERYTHING.ps1` unless the
  user explicitly asks for it in the bundled flow. Standalone script under the
  right numbered folder is the default.
- Document the risk in the script header (what it disables, why you might want
  it, what breaks if you do, anti-cheat implications if relevant) and surface
  the tier in the launcher.

The "Items not currently shipped from FR33THY/Ultimate" section of
`KNOWN-ISSUES.md` is historical context, not a binding "won't ship" list.
Treat upstream-port requests as "yes, here's how" — not "no, see KNOWN-ISSUES."

## Entry points

| File | Purpose |
| --- | --- |
| `launcher.ps1` | Interactive menu; the recommended entry. PS 5.1 compatible, ASCII fallback for ISE/narrow terminals. |
| `APPLY-EVERYTHING.ps1` | Aggressive full stack. Calls every phase. |
| `REVERT-EVERYTHING.ps1` | Manifest-driven rollback with defaults fallback. |
| `10 verify/verify-tweaks.ps1` | Read-only state check. |

Numbered folders (`0 prerequisites/` → `10 verify/`) hold per-phase scripts.
`lib/` is shared helpers; everything else at root is documentation.

## Doc map (where to look first)

- **Architecture / phases / repo map** → `GUIDE.md`
- **Living tracker (open work, limitations, owner decisions)** → `KNOWN-ISSUES.md`
- **Per-version history** → `CHANGELOG.md`
- **Manual runtime test gate** → `MANUAL-TEST-CHECKLIST.md`
- **Hardware/BIOS items the toolkit cannot script** → `BIOS-CHECKLIST.md`
- **Upstream FR33THY port log** → `docs/freethy-integration.md`
- **v1.0.0 readiness snapshot (historical)** → `PRODUCTION-READY.md`

`KNOWN-ISSUES.md` and `CHANGELOG.md` are the living record. Spent audit reports (`CHANGES.md`, `CODEX-AUDIT.md`, `CURSOR-AUDIT.md`, `CLEANUP.md`, `SESSION-REPORT.md`) were folded into those two files and removed. Do not recreate them.

## Conventions

- **Commits**: conventional (`feat:` / `fix:` / `docs:` / `chore:` / `refactor:` / `perf:`).
  Attribution disabled globally.
- **Line endings**: CRLF for `.ps1` `.bat` `.cmd` `.reg`; LF for `.md` `.json` `.yml`
  (enforced by `.gitattributes`).
- **Per-file headers**: scripts ported from upstream must carry
  `# Source: <upstream>/<path> — <one-line rationale>`.
- **Tier string**: canonical form is `Security Trade-off` (with hyphen, space, capital T).
  The launcher displays it short as `Trade-off`; never write `Security-tradeoff`
  or any other variant in code.
- **Apply / revert pairing**: every new opt-in tweak ships with a colocated
  `enable-*` (or `revert-*`) sibling script. Manifest-only revert is not a
  substitute for a paired script — both are required.
- **Anti-cheat warnings**: any script touching VBS / HVCI / LSA-PPL / Spectre
  mitigations / kernel timer resolution must include a header comment noting
  potential BattlEye / EAC impact (R6 Siege and similar titles on 24H2+).
- **Architecture-over-wiring**: a fix that touches 3+ scripts mechanically is
  a signal to STOP and find the single-point upstream change (probably a
  missing `lib/` helper). Commit the helper + behavioral tests first; per-
  caller refactors land in follow-up commits with measurable diff shrink.
  Mark architecture commits `arch(<lib>): <change> — replaces N call-site
  edits, covers future M`.
- **Invariants ship with a tracked gap list, not silenced**: each invariant
  Pester suite in `tests/invariants/` includes a `$KnownGaps` array. Real
  violations are added there (visible in test output as `Set-ItResult
  -Skipped -Because '<reason>'` per entry), NOT by disabling the assertion.
  Each fix commit removes the gap entry from the array — the diff IS the
  proof the fix landed. NEVER expand a gap list to silence a regression;
  fix the script.
- **ShouldProcess gates go OUTSIDE the `& $UIStepAction` ScriptBlock.**
  `$PSCmdlet` scope resolution inside a script block invoked via `& $block`
  is unreliable across PowerShell versions. Pattern:
  ```
  if (-not $PSCmdlet.ShouldProcess(...)) { UI-Skip ...; continue }
  UI-Step -Label ... -Action { <do the work> }.GetNewClosure()
  ```
  `.GetNewClosure()` captures loop variables at iteration time. The
  `5 registry tweaks/individual/configure-mmagent.ps1` / `revert-mmagent.ps1`
  pair is the canonical reference.

## Known gotchas

- **Don't shadow PowerShell automatic variables.** PSSA's
  `PSAvoidAssignmentToAutomaticVariable` catches the common cases at gate
  time, but the cost is wasted dev cycles. Top offenders we've hit:
    - `$matches` — populated by `-match` operator (use `$pkgMatches`,
      `$results`, etc.)
    - `$pid` — current process ID (use `$devPid` for device PIDs)
    - `$profile` — user profile script path (use `$machineProfile`)
    - `$error` — error array (use `$errors` if you need it as a variable)
    - `$host` — host UI object (don't reuse for anything else)
  Test files inherit the same rule.
- **WaaSMedicSvc on Win11 24H2 / 25H2**: DACL blocks even SYSTEM from setting
  `Start = 4`. `disable-windows-update.ps1` detects this and warns rather than
  failing. The recovery path (manual `takeown` / `icacls`) is documented in
  `GUIDE.md` Troubleshooting — ship it as an opt-in helper script if asked,
  but don't auto-run it.
- **`launcher.ps1` admin refusal**: launcher exits clean with exit code 1 if
  not elevated. Don't add partial-menu rendering for non-admin.
- **Domain-joined / laptop hints**: surfaced in launcher header but APPLY still
  runs if the user proceeds — never auto-skip phases based on profile.
- **Apply All leaves `Security Trade-off` phases off by default.** Phases 9–10
  (VBS/HVCI/LSA/Spectre/WU suppression) run only when `-IncludeSecurityTradeoffs`
  is passed. Launcher `[A]` prompts before passing that switch. Default new
  Security Trade-off items to standalone scripts unless the user asks them
  into the bundled APPLY path.
