# Cleanup + Launcher Redesign

> **HISTORICAL — DO NOT RUN.**
>
> This prompt already ran before v1.0.0. It is an archive, not a task. Do not execute any phase below. Do not start at Phase 0.
>
> These actions are cancelled, even where the archive text below still mentions them:
>
> - Do not delete `website/` or `site/`. The landing site lives in `site/` and stays.
> - Do not remove site deploy workflows. `.github/workflows/deploy-site.yml` stays.
> - Do not read, write, or recreate `CHANGES.md`, `CODEX-AUDIT.md`, `CLEANUP.md`, `CURSOR-AUDIT.md`, `SESSION-REPORT.md`, or `prompts/README.md`. Those audit docs were folded into `KNOWN-ISSUES.md` and `CHANGELOG.md` and must not be recreated (`CLAUDE.md`).

Archived task (already finished): consolidate branches, remove the old Next.js tree that used to live at `website/`, prune dead files, redesign `launcher.ps1`. Do not run it again.

## Phase 0 — Ground

Read in this order:
1. `git branch -a`, `git status`, `git log --oneline -50 --all`
2. Living docs only: `KNOWN-ISSUES.md` and `GUIDE.md`. Do not read or recreate `CHANGES.md`, `CODEX-AUDIT.md`, or `prompts/README.md`.
3. Current `launcher.ps1` end-to-end. You're rewriting it — read what's there first.
4. `lib/toolkit-state.ps1` for the manifest format. The new launcher reads from this.

Output before doing anything destructive:
- Branch list with one-line plan per branch (merge / delete / keep).
- The old `website/` tree is already gone. Do not delete `site/`.
- Approximate count of dead-file candidates from Phase 3.

## Phase 1 — Branch consolidation

Goal: single `main` branch with all good work merged. Stale branches gone, locally and on origin.

1. For each non-main branch:
   - `git log main..<branch>` empty → already merged → safe to delete.
   - Has commits not in main → review those commits. If they belong, merge into main. If they're abandoned experiments, delete.
2. Resolve merge conflicts conservatively. Prefer the version that:
   - Routes through `lib/toolkit-state.ps1` helpers.
   - Has a paired revert.
   - Has a verify check.
3. Push main, delete merged branches local + remote:
   ```bash
   git push origin --delete <branch>
   git branch -D <branch>
   ```
4. One commit per merge; document the merge order in commit messages.

## Phase 2 — Old `website/` tree (already removed; do not repeat)

This phase already ran. The old Next.js tree at `website/` is gone. That record is not a task.

Leave `site/` in place. Leave `.github/workflows/deploy-site.yml` in place. Do not delete either. Do not strip the current landing site out of `README.md`, `GUIDE.md`, `.gitignore`, or workflow files.

## Phase 3 — Dead file cleanup

"Unused" means truly not referenced. Prove it before deleting.

1. Build the candidate list:
   - `*.bak`, `*.old`, `*~`, `.DS_Store`, `Thumbs.db` — drop unconditionally.
   - Files at repo root or in numbered folders that aren't referenced by any `.ps1`, `.bat`, `.md`, or `launcher.ps1`. Use grep across the whole repo to confirm.
   - `revert-*` orphans whose `apply-*` is gone. Same in reverse.
   - Files older than 6 months with zero references in current code (`git log -1 --format=%ai -- <file>`).
2. Do NOT delete:
   - Anything in `lib/` without grepping the entire repo for the symbol/function name first.
   - `GUIDE.md`, `BIOS-CHECKLIST.md`, `KNOWN-ISSUES.md`, `CHANGELOG.md`, `LICENSE`, `README.md`, `site/`.
   - The `prompts/` folder.
   - Any `.reg` file paired to a tracked tweak.
3. For each delete, write a one-line justification in the commit body.
4. Commit per logical group: `chore: drop .DS_Store and editor backups`, `chore: remove orphan revert-foo (apply gone since v0.2)`, etc.

## Phase 4 — Launcher redesign

Rewrite `launcher.ps1`. The current one is functional; the new one is intentional. See `prompts/launcher-design.md` if present, else this spec is canon.

### Layout

Three sections in this order: Quick actions, Categories, Tools. Header above, prompt below.

```
┌──────────────────────────────────────────────────────────────────┐
│  Win11 Gaming Toolkit                              v<version>    │
│  Admin: <yes|no>   Build: <build>   Manifest: <N> entries        │
└──────────────────────────────────────────────────────────────────┘

  Quick actions
    [A]  Apply All                  <N tweaks>  ~<min>
    [V]  Verify status              <N> applied · <N> pending
    [R]  Revert All                 rollback to manifest

  Categories
    [0]   Prerequisites             Safe
    [1]   Backup                    Safe           ✓ applied
    [2]   Power plan                Advanced       ✓ applied
    [3]   Privacy / telemetry       Safe           ✓ applied
    [4]   Services                  Advanced       ! drift
    [5]   Registry tweaks           Advanced       ✓ applied
    [6]   GPU                       Advanced
    [7]   Network                   Safe           ✓ applied
    [8]   Security vs performance   Trade-off
    [9]   Cleanup                   Advanced
   [10]   Verify                    Safe

  Tools
    [M]  View manifest              [L]  View recent log
    [B]  Regenerate baseline        [?]  Help     [Q]  Quit

  PS> _
```

### Color rules

- Toolkit name + version: white / cyan accent.
- Section labels (Quick actions, Categories, Tools): `Yellow`.
- Bracketed keys `[A]`, `[0]`, `[10]`: `Cyan`.
- Risk tier:
  - `Safe` → `Green`
  - `Advanced` → `Yellow`
  - `Trade-off` → `Red` (display label is "Trade-off", canonical string in code stays `Security Trade-off`)
- Status:
  - `✓ applied` → `Cyan`
  - `! drift` → `Red`
  - blank if untracked / not applied
- Muted descriptions (counts, durations, build): `DarkGray`.
- Box-drawing chars: `DarkGray`.

Use `Write-Host -ForegroundColor` exclusively. No raw ANSI escape sequences — they break in PS 5.1 ISE.

### Behavior

- Read the manifest once at launcher start. Refresh on every return to main menu.
- `[A]`, `[V]`, `[R]` execute the existing top-level scripts; do not re-implement.
- Selecting `[0]` through `[10]` opens a category submenu listing that folder's individual scripts. Submenu uses the same color system. Back via `Esc` or `Q`.
- `[M]` opens the manifest in the user's default editor (`Invoke-Item`).
- `[L]` tails the most recent log under wherever the toolkit writes them. Read the path from `lib/toolkit-state.ps1`.
- `[B]` re-runs the baseline capture used by Windows testing (or no-op + message if testing harness isn't set up).
- `[?]` shows a help screen with all keybindings.
- `[Q]`, `Ctrl+C`, `Esc` from main menu: exit cleanly.
- Non-admin launch: print "must run as administrator" and exit cleanly. No partial menus.

### Implementation rules

- Pure PS 5.1 compatible. Built-in modules only. No external Install-Module dependencies.
- One function per screen: `Show-MainMenu`, `Show-CategoryMenu -Index <int>`, `Show-Help`.
- One input helper: `Read-MenuChoice -ValidKeys @('A','V','R',...)`. Uppercase comparison; accept lowercase input.
- Box-drawing characters acceptable. If `$Host.UI.RawUI` indicates ISE, fall back to ASCII (`+-|`). Detect once at startup.
- No `Clear-Host` more than once per screen render. Do not clear scroll history aggressively.
- No emoji. No marketing language.
- All user-facing output ≤ 80 cols. Test by resizing the terminal narrow during dev — layout must not blow up.

### Done means

- Fresh VM: launches, all menu options work, nothing errors to console.
- Partial manifest: status indicators correct (`✓ applied` vs `! drift` vs blank).
- Non-admin: clean refusal.
- Narrow terminal (60 cols): readable, doesn't break.
- ISE: ASCII fallback engages, still readable.

## Phase 5 — Verify nothing broke

After all four phases:
1. `APPLY-EVERYTHING.ps1` still runs end-to-end on a clean VM (or, if you can't run it, walk the script and confirm no dangling references to deleted files).
2. `REVERT-EVERYTHING.ps1` same.
3. `verify-tweaks.ps1` same.
4. `launcher.ps1` exercises every menu option locally without error.
5. `GUIDE.md` matches the actual filesystem.

If any check fails, fix forward in a `fix:` commit. Do not unwind the cleanup unless something is genuinely unrecoverable.

## Phase 6 — Output (archive; do not produce these again)

These outputs already landed. Do not write `CLEANUP.md` or any other removed audit doc.

1. Cleanup notes were folded into `KNOWN-ISSUES.md` and `CHANGELOG.md`. Do not recreate `CLEANUP.md`.
2. `launcher.ps1` was redesigned in that pass.
3. `GUIDE.md` was updated for the launcher. Do not remove `site/` links from it under this prompt.
4. Conventional commits from that pass (already on `main`; do not repeat):
   - `chore: merge feat/freethy-integration into main`
   - `chore: drop .DS_Store and editor backups`
   - `chore: remove orphan revert scripts`
   - `feat(launcher): redesign with tiered color coding and status indicators`
   - `docs: update GUIDE.md for new launcher`

## Hard constraints

- Do not delete anything in `lib/` without grepping the entire repo for usage first.
- Do not break apply / revert / verify. If cleanup conflicts with keeping the toolkit working, keep it working.
- Do not change risk tier strings, manifest format, or helper function signatures during this cleanup. Scope creep.
- Do not stuff branch consolidation, file deletion, and launcher redesign into one mega-commit.
- The new launcher is opinionated about layout and color. Deviations from that pass, if any, live in `KNOWN-ISSUES.md`. Do not recreate `CLEANUP.md`.

Do not begin. This file is historical.
