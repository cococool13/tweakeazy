# Cleanup + Launcher Redesign

Outcome of a spent cleanup-and-redesign one-shot (prompt retired; this file
is the record). Each phase landed in its own commit cluster on `main`.
Branches consumed by the merge were deleted; one safety-net branch
(`CC/salvage-pre-cleanup`) was kept.

## Branches

### Merged
- `codex/audit-extend-win11-toolkit` → `main` via `chore: merge codex/audit-extend-win11-toolkit into main`. 26 commits brought the FR33THY/Ultimate integration plus the codex audit fixes (A1–A10) onto `main`. Adds `CHANGES.md`, `KNOWN-ISSUES.md`, `CODEX-AUDIT.md`, `DISCOVERY-BACKLOG.md`, `TESTING.md`, `docs/freethy-integration.md`, 12 new tweak scripts with paired reverts, and 10 audit-driven bug fixes.

### Deleted (consumed)
- `CC/hardcore-rubin-7d2584` (local) — strict subset of `codex/audit-extend-win11-toolkit`. Every commit in this branch was already in codex; deleting it lost no work.
- `claude/implement-todo-item-9uEXR` (origin) — single commit `60738e6 Fix missing external link attributes on Hero Download button and FAQ key`. Touched only `website/`, which is gone.
- `claude/add-claude-documentation-zxdYP` (origin) — single commit `7d0c456 docs: add CLAUDE.md with codebase structure and AI assistant guidance`. The codex `CHANGES.md` + `GUIDE.md` updates already cover the same purpose with more detail.
- `codex/audit-extend-win11-toolkit` (local, post-merge) — also removed `/private/tmp/pc-tweaks-codex-audit` and `.claude/worktrees/hardcore-rubin-7d2584` worktrees that held it.

### Kept
- `main` — target.
- `CC/salvage-pre-cleanup` (origin + local) — pre-cleanup snapshot of the main worktree's 42 modified + 16 untracked files. Safety net only; nothing in this branch is intended for integration.
- `CC/sleepy-hellman-f4b52f` (this worktree's branch) — also a safety net during cleanup. Can be deleted once the work is confirmed.

## Files

### Removed by `chore: remove website/ and associated tooling`
The entire `website/` subtree — 30 tracked files, 11,500+ lines. The Next.js landing site is gone; the toolkit is now the only deliverable.

| Reason | Files |
|---|---|
| Site deleted | `website/**` (entire subtree, 30 files including `package.json`, `next.config.ts`, `tsconfig.json`, every component, every page, every asset) |
| Doc reference dropped | `GUIDE.md` (removed the `website/` line from the repo-map section) |
| Question about deleted file moot | `CHANGES.md` Q1 (rewrote — `website/src/lib/constants.ts` is gone; `lib/version-manifest.ps1` GitHub raw URL stays) |
| Build-tooling references | `.gitignore` (dropped `node_modules/`, `website/.next/`, `website/out/`, `firebase-debug.log`) |

There was no top-level `package.json` / `tsconfig.json` / `vite.config.*` / `index.html` outside `website/`, and no `.github/workflows/*` directory — nothing else to remove.

### Removed by `feat(launcher): redesign with tiered color coding and status indicators`
| Reason | File |
|---|---|
| Orphaned by launcher rewrite | `lib/launcher-menu.ps1` — defined `Get-LauncherMenu` for the previous flat-menu launcher. The new launcher embeds its menu definition inline (`$script:LauncherCategories`, `$script:LauncherQuickActions`); no other script in the merged tree referenced this helper. |

### Phase 3 dead-file scan: zero additional deletions

Pre-merge sweep (`main` before the codex merge) and post-merge sweep both came back clean:

- **Filesystem debris**: zero tracked `*.bak`, `*.old`, `*.orig`, `*.swp`, `*~`, `.DS_Store`, `Thumbs.db` files. Two untracked `.DS_Store` files were on disk (root and `6 gpu/`); deleted from disk only — they were already gitignored, no commit needed.
- **`lib/gpu-download.ps1`** (initial candidate): kept — referenced from `6 gpu/install-gpu-driver.ps1:32`.
- **`5 registry tweaks/individual/disable-nagle-README.txt`** (initial candidate): kept — intentional informational README explaining why Nagle's Algorithm needs per-adapter manual setup (the GUID-keyed registry path can't be hardcoded). Points users to `7 network/optimize-network.ps1` for the automated path.
- **Apparent orphan `disable-*` files in `5 registry tweaks/individual/`** (e.g., `disable-power-throttling.reg`, `disable-fast-startup.reg`, etc., with no paired `enable-*.reg`): kept — these are batch-reverted via `5 registry tweaks/revert-all.reg`, not per-file. Same pattern for `4 services/disable-services.ps1` (reverted via `4 services/revert-all.bat`) and `6 gpu/enable-msi-mode.ps1` (manifest-driven revert through `REVERT-EVERYTHING.ps1`).
- **All numbered-folder README.txt files**: kept — they document tier and intent for each category.

The merged tree is disciplined: every numbered folder has functional pair coverage either per-file or via batch-revert scripts, and no editor / OS / build debris was tracked.

## Launcher

`launcher.ps1` was rewritten end-to-end (562 insertions, 137 deletions) to match the retired cleanup-prompt spec (Phase 4 launcher redesign).

**Header**
- Title + version on the top line; admin state, OS build, and manifest entry count on the second line.
- Box-drawing chars in `DarkGray`; Unicode by default, ASCII fallback in PowerShell ISE or in terminals narrower than 80 columns. Detection runs once at startup.

**Quick actions** dispatch to existing top-level scripts; behavior is not reimplemented:
- `[A]` Apply All → `APPLY-EVERYTHING.ps1`
- `[V]` Verify status → `10 verify\verify-tweaks.ps1`
- `[R]` Revert All → `REVERT-EVERYTHING.ps1`

**Categories** open per-folder submenus listing every `*.ps1` / `*.bat` / `*.reg` file in that folder (recursive). Submenu uses the same color system. `[Q]` returns to the main menu. The full set: `[0]` Prerequisites, `[1]` Backup, `[2]` Power plan, `[4]` Services, `[5]` Registry tweaks, `[6]` GPU, `[7]` Network, `[8]` Security vs performance, `[9]` Cleanup, `[10]` Verify.

**Tools**
- `[M]` View manifest → `Invoke-Item (Get-ToolkitManifestPath)`.
- `[L]` View recent log → tails the newest `*.log` under `$script:ToolkitLogRoot` (new constant in `lib/toolkit-state.ps1`); prints `(no logs yet)` if the directory is missing or empty.
- `[B]` Regenerate baseline → reruns `Initialize-ToolkitState -ForceNew` after a typed `YES` confirmation.
- `[?]` Help screen with every keybinding and status indicator.
- `[Q]` exits clean.

**Risk-tier coloring** (display only — code paths still use the canonical `"Security Trade-off"` string):
- `Safe` → Green
- `Advanced` → Yellow
- `Trade-off` → Red

**Per-category status**:
- `[OK] applied` (Cyan) when `state.steps` records an applied tweak whose key prefix matches the category.
- `! drift` (Red) when the toolkit applied a registry change but the OS now reports the original `before.value` (i.e., the user has reverted externally).
- Blank when the category has no tracked apply state.

**Non-admin**: prints a one-line refusal and exits with code 1. No partial menus.

**Implementation discipline**:
- Pure PS 5.1; built-in modules only.
- `Write-Host -ForegroundColor` exclusively. No raw ANSI escape codes (PS 5.1 ISE can't handle them).
- One `Clear-Host` per render. No emoji. No marketing copy.
- Reuses `lib/ui-helpers.ps1` color constants (`$script:UI_Success`, `$script:UI_Error`, `$script:UI_Warning`, etc.) and `UI-RequireAdmin`. Replaces only the menu definition and dispatcher.

## Design deviations

The retired cleanup prompt's example main menu listed `[3] Privacy / telemetry` as a category. The repo's numbered-folder layout has folders `0 1 2 4 5 6 7 8 9 10` — there is no `3 privacy/`. Privacy / telemetry tweaks live inside `5 registry tweaks/individual/` (`privacy-telemetry.reg`, `disable-edge-background.ps1`, `disable-windows-update.ps1`, etc.).

Creating a new `3 privacy/` folder and moving those files would have required updating every reference in `APPLY-EVERYTHING.ps1`, `REVERT-EVERYTHING.ps1`, `10 verify/verify-tweaks.ps1`, every README, and `docs/freethy-integration.md`. That crosses the prompt's "scope creep" line, so `[3]` is omitted from the main menu in v1. Privacy/telemetry tweaks remain reachable via `[5] Registry tweaks` → submenu.

If a separate `[3] Privacy / telemetry` category is desired later, the right time to do it is during a folder reorganization pass, not during a launcher redesign.

## Verification

End-to-end testing on macOS (no Windows VM available; documented fallback per `CHANGES.md` and `TESTING.md`):

- All 12 top-level / `lib/` PowerShell scripts parse cleanly via `pwsh` (`APPLY-EVERYTHING.ps1`, `REVERT-EVERYTHING.ps1`, `10 verify/verify-tweaks.ps1`, `launcher.ps1`, `DduManual.ps1`, `DduAuto.ps1`, every file in `lib/`).
- Every `[A]` / `[V]` / `[R]` / `[0]` / `[1]` / `[2]` / `[4]` / `[5]` / `[6]` / `[7]` / `[8]` / `[9]` / `[10]` dispatch path resolves to an existing file or directory in the merged tree.
- Zero residual `website/` references in tracked files outside `CHANGES.md` (intentional historical mention). The live Cloudflare landing page is `site/` and was never in scope for that cleanup.
- The `lib/version-manifest.ps1` GitHub raw URL (`https://raw.githubusercontent.com/cococool13/TweakEazy/main/versions.json`) is functional and unrelated to the deleted website folder; it stays.
- `git ls-tree -r --name-only main` went from 125 (pre-merge) → 155 (post-merge) → 125 (post-website-removal) → 124 (post-launcher-rewrite, after `lib/launcher-menu.ps1` deletion).

The user must still run `launcher.ps1` on Windows to confirm the rendered output matches the spec at runtime; if a category status indicator misfires, the fix is forward via a `fix(launcher):` commit.

## Commit sequence

```
c7e856c chore: salvage pre-cleanup state from main worktree
6730a47 chore: merge codex/audit-extend-win11-toolkit into main
c3c4de0 chore: remove website/ and associated tooling
7be145f feat(launcher): redesign with tiered color coding and status indicators
```

The launcher commit also carries the one-line `$script:ToolkitLogRoot` constant addition to `lib/toolkit-state.ps1` and the `lib/launcher-menu.ps1` deletion, since both are direct consequences of the rewrite. `docs:` updates (this file + the GUIDE.md launcher section) follow.
