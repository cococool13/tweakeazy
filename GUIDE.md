# Windows 11 Gaming Optimization Guide

This repo is a Windows optimization toolkit with one primary path:

1. Read this guide.
2. Launch `launcher.ps1`.
3. Run only the phases that match your machine and your tolerance for trade-offs.

`APPLY-EVERYTHING.ps1` is still available, but it is the aggressive path, not the default recommendation.

## Before You Start

- Run PowerShell scripts as Administrator.
- If PowerShell blocks local scripts, run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` in an elevated shell.
- Create a backup first. The toolkit has a checkpoint path for a reason.
- Laptops, hybrid-GPU systems, and work-managed PCs need extra care.
- Not every change is perfectly reversible. The manifest improves rollback, but removed apps and some system policies can still require manual recovery.

## Choose Your Path

### Recommended path: launcher first

Run:

```powershell
.\launcher.ps1
```

Use the launcher as the main entrypoint. The header reports admin
state, OS build, and how many entries the toolkit manifest has
recorded. Below the header are three sections:

**Quick actions** — `[A]` Apply All, `[V]` Verify status, `[R]` Revert
All. These call `APPLY-EVERYTHING.ps1`, `10 verify\verify-tweaks.ps1`,
and `REVERT-EVERYTHING.ps1` directly.

**Categories** — `[0]` through `[10]` open per-folder submenus that
list every tweak script in that folder. Each category shows a risk
tier (`Safe` / `Advanced` / `Trade-off`) and, when the manifest knows,
a status indicator: `[OK] applied` if a tweak from this category is
recorded, or `! drift` if a tracked tweak's underlying registry value
has reverted to its pre-toolkit state outside the toolkit.

**Tools** — `[M]` opens `manifest.json` in the default editor; `[L]`
tails the newest log under `%ProgramData%\Win11GamingToolkit\logs`;
`[B]` regenerates the baseline manifest after a typed `YES` confirm;
`[?]` shows full help; `[Q]` quits.

The launcher refuses to run as a non-admin and exits clean. It is
PowerShell 5.1 compatible; no external modules are required. In
PowerShell ISE or in narrow terminals it falls back to ASCII box
characters automatically.

### Aggressive path: full-stack apply

Run:

```powershell
.\APPLY-EVERYTHING.ps1
```

Use this only when you already understand the trade-offs. It includes:

- power and Windows tuning
- service and registry changes
- startup cleanup
- GPU MSI mode and network tuning
- Windows Update suppression (opt-in: `-IncludeSecurityTradeoffs`)
- VBS / HVCI / LSA trade-offs (opt-in: `-IncludeSecurityTradeoffs`)
- shell customization
- Defender exclusions
- app debloat and temp cleanup

### Rollback path

Run:

```powershell
.\REVERT-EVERYTHING.ps1
```

This restores tracked settings first, then falls back to sensible defaults where no captured state exists.

### Verification path

Run:

```powershell
.\10 verify\verify-tweaks.ps1
```

This checks the same phases exposed by the launcher and the full apply flow so you can see what is still applied, what drifted, and what was already present.

## Primary Entry Points

| Entry point | When to use it | Main risk | Undo |
| --- | --- | --- | --- |
| `launcher.ps1` | You want the guided menu | Low by itself | N/A |
| `1 backup/create-backup.ps1` | You want a restore point and registry backup first | Low | Restore point and exported registry files |
| `0 prerequisites/install-runtimes.ps1` | Games are missing VC++ or legacy DirectX runtimes | Low | Uninstall from Apps / Features |
| `2 power plan/configure-power.ps1` | You want the performance power baseline only | Low to medium | Switch back to Balanced |
| `4 services/disable-services.ps1` | You want service changes without the full stack | Medium | `4 services/revert-all.bat` or full revert |
| `5 registry tweaks/apply-all.reg` | You want the raw registry pack | Medium | `5 registry tweaks/revert-all.reg` or full revert |
| `6 gpu/install-gpu-driver.ps1` | You want the clean GPU driver path | Medium to high | DDU + reinstall / full revert for tracked settings |
| `8 security vs performance/configure-vbs.ps1` | You want the security trade-off step only | High | Re-enable via the same folder or full revert |
| `APPLY-EVERYTHING.ps1` | You want the whole stack in one run | High | `REVERT-EVERYTHING.ps1` |

## Phase Reference

### Setup

#### Backup and restore

- What it changes: creates a restore point and exports key registry areas.
- Why run it: gives you the safest rollback point before tuning.
- Main risk: restore-point creation can be throttled or unavailable by Windows policy.
- Undo: use System Restore or import the exported `.reg` files.

#### Runtime prep

- What it changes: installs Visual C++ runtimes and the legacy DirectX June 2010 redistributable.
- Why run it: fixes missing runtime dependencies for older games and launchers.
- Main risk: low; this is standard dependency installation.
- Undo: uninstall from Windows apps settings if needed.

### Optimize

#### Power plan

- What it changes: activates Ultimate Performance and tunes detailed power settings.
- Why run it: reduces power-saving latency and background throttling.
- Main risk: worse idle power usage, worse battery behavior on laptops.
- Undo: switch back to Balanced or run the full revert.

#### Services

- What it changes: disables selected background services.
- Why run it: reduces unnecessary background work on gaming-focused systems.
- Main risk: features like printing, search indexing, Offline Files / Sync Center, and telemetry-related components may stop working as expected.
- Undo: `4 services/revert-all.bat` or the full revert script.

#### Registry pack

- What it changes: latency, Game Bar, Explorer, privacy, sound, and visual-effect related registry settings.
- Why run it: applies many common Windows gaming tweaks in one place.
- Main risk: broadest surface area in the repo; some changes are preference-driven, not universally better.
- Undo: `5 registry tweaks/revert-all.reg` for the raw pack, or `REVERT-EVERYTHING.ps1` for the tracked path.

#### Edge background policies

- What it changes: disables Microsoft Edge Startup Boost and background mode through machine policy.
- Why run it: stops Edge from preloading at sign-in or continuing background work after close.
- Main risk: Edge can cold-start more slowly; background Edge apps/extensions stop when Edge is closed.
- Undo: `5 registry tweaks/individual/enable-edge-background.ps1` or `REVERT-EVERYTHING.ps1`.

#### NTFS last-access updates

- What it changes: disables NTFS Last Access timestamp updates.
- Why run it: reduces avoidable file metadata writes during directory and file access.
- Main risk: backup, indexing, or audit tools that rely on access timestamps can see stale times.
- Undo: `5 registry tweaks/individual/enable-ntfs-last-access.ps1` or `REVERT-EVERYTHING.ps1`.

#### Timer service

- What it changes: installs a service to request lower timer resolution.
- Why run it: can reduce input latency on some systems.
- Main risk: more wakeups and power cost.
- Undo: `REVERT-EVERYTHING.ps1` removes the toolkit-managed timer service.

#### Cleanup

- What it changes: removes bundled apps and clears temp/cache folders.
- Why run it: trims non-essential software and stale files.
- Main risk: some removed apps may need manual reinstall.
- Undo: reinstall apps from Microsoft Store or winget; temp-file cleanup is not reversible.

#### Security trade-off

- What it changes: disables VBS, HVCI, and related protections.
- Why run it: removes security features that can affect latency or compatibility for aggressive tuning.
- Main risk: reduced Windows hardening.
- Undo: use the same folder scripts or `REVERT-EVERYTHING.ps1`.

### GPU and Network

#### GPU MSI mode

- What it changes: enables MSI mode for detected display devices.
- Why run it: lowers interrupt latency on supported hardware.
- Main risk: misbehaving drivers or hardware-specific instability.
- Undo: rerun the relevant GPU flow or use full revert.

#### GPU driver flow

- What it changes: stages a DDU-backed clean driver install and optional hidden vendor settings.
- Why run it: cleanest path when troubleshooting or redoing GPU drivers.
- Main risk: highest-risk path in the repo if interrupted mid-clean/install.
- Undo: use DDU again and reinstall a known-good driver.

#### GPU vendor opt-ins

- What it changes: optional FR33THY-derived NVIDIA P0 state and AMD ULPS registry settings under `6 gpu/`.
- Why run it: use only for benchmark consistency or AMD multi-GPU hitch troubleshooting.
- Main risk: higher idle GPU power, heat, and driver-specific behavior.
- Undo: `REVERT-EVERYTHING.ps1` restores the manifest-backed registry values.

#### Network

- What it changes: TCP settings, adapter properties, Nagle-related flags, and DNS.
- Why run it: reduces avoidable network latency on gaming systems.
- Main risk: adapter-specific compatibility differences and changed DNS behavior.
- Undo: `7 network/revert-network.bat` or `REVERT-EVERYTHING.ps1`.

### Safety and Verify

#### Apply Everything

- What it changes: runs the aggressive full stack across all phases.
- Why run it: fastest route to the maximum scripted tuning pass.
- Main risk: aggressive Safe + Advanced stack; Security Trade-offs stay behind `-IncludeSecurityTradeoffs`.
- Undo: `REVERT-EVERYTHING.ps1`.

#### Revert Everything

- What it changes: restores manifest-backed state where available and applies default-based rollback elsewhere.
- Why run it: fastest supported return path from the full-stack flow.
- Main risk: app removals and some broad defaults still need manual follow-up.
- Undo: this is the undo path.

#### Verify

- What it changes: nothing.
- Why run it: shows whether tracked changes are applied, preexisting, unsupported, drifted, or failed.
- Main risk: none.
- Undo: not applicable.

## Repo Map

Use this map when you want to open folders directly instead of using the launcher:

- `0 prerequisites/` runtime installers
- `1 backup/` restore point and registry backup
- `2 power plan/` power and sleep behavior
- `4 services/` service toggles
- `5 registry tweaks/` raw registry packs and timer service
- `6 gpu/` MSI mode, DDU, and driver flows
- `7 network/` adapter and TCP tuning
- `8 security vs performance/` VBS / HVCI trade-off scripts
- `9 cleanup/` debloat, temp cleanup, WinUtil wrapper
- `10 verify/` state inspection and health checks
- `lib/` shared PowerShell helpers and manifest/state tracking

## Troubleshooting

### The launcher or scripts say Administrator is required

Open PowerShell as Administrator, then run the script again.

### PowerShell refuses to run local scripts

Run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### A tweak applied, but Verify says it drifted

Windows, OEM utilities, enterprise policy, or driver software may have overwritten it. Use Verify to find the phase, then re-run only that area instead of the whole stack.

### A laptop behaves worse after tuning

Undo the power and GPU-focused phases first. The toolkit does not automatically downgrade itself for battery-capable systems.

### Revert finished, but the PC still feels off

Reboot first. Then run Verify. If the remaining issue is an app removal or an external tool side effect, that requires manual follow-up.

### Windows Update keeps re-enabling itself on 24H2 / 25H2

`disable-windows-update.ps1` writes `Start = 4` to `HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc`. On Windows 11 24H2 and newer, the DACL on this key blocks even SYSTEM from setting `Start`, so the change is rejected. The script detects this and prints a warning rather than failing silently.

Recovery options if you need WaaSMedicSvc actually disabled:

1. Run an elevated CMD and take ownership manually:
   ```
   takeown /f HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc
   icacls "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /grant Administrators:F
   ```
   Then re-run `disable-windows-update.ps1`. The toolkit does not do this automatically because mis-applied DACL changes on protected services can break Windows Update permanently.
2. Live with the warning. The other update-suppression policies (`NoAutoUpdate`, `NoAutoRebootWithLoggedOnUsers`, service `Start = 4` for `wuauserv` / `UsoSvc` / `DoSvc`) are still applied. WaaSMedicSvc may periodically re-enable Windows Update; you can re-run the script to put things back.

## Credits

The toolkit's tweak set is informed by these communities and people. Where a script was directly derived from upstream work, the source is named in a header comment in that file.

- **FR33THY** — <https://github.com/FR33THYFR33THY/Ultimate>. Source for MPO disable, MMAgent tuning, NIC power-savings disable, IPv6 unbind, Spectre / Meltdown override, DEP toggle, NVIDIA P0 state, AMD ULPS disable, and Offline Files / Sync Center disable. See `docs/freethy-integration.md` for the full inventory.
- **Khorvie Tech** — original lineage credit retained in `Notice.txt`.
- **Chris Titus Tech** — <https://github.com/ChrisTitusTech/winutil>. Wrapped by `9 cleanup/chris-titus-winutil.bat`.
- **Wagnardsoft** — Display Driver Uninstaller (DDU). Wrapped by `DduManual.ps1` / `DduAuto.ps1`.
