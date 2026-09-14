# FR33THY/Ultimate Integration Inventory

Source: <https://github.com/FR33THYFR33THY/Ultimate>

This is the canonical record of which FR33THY artifacts were ported into this toolkit, which were merged into existing files, and which were declined. Decisions follow the rules in `GUIDE.md` and `BIOS-CHECKLIST.md`:

- Automatable only. Manual UI / control-panel toggles go to `BIOS-CHECKLIST.md` or are skipped.
- Additive only. We do not duplicate registry keys, services, or commands we already manage.
- Tracked via `lib/toolkit-state.ps1`. Untracked writes break revert and verify.
- Three risk tiers: `Safe`, `Advanced`, `Security Trade-off`. No new tiers.
- No bundled binaries. Tools download at runtime with SHA-256 verification.

## Inventory table

| FR33THY file | Type | What it changes | Already covered by us? | Action | Target file |
| --- | --- | --- | --- | --- | --- |
| `1 Check/1-9 *.ps1` | .ps1 | Diagnostic checks (disk space, RAM, GPU, BIOS, CPU/RAM/GPU stress tests, HWInfo) | Partial — `11 hardware checks/` + `12 hardware/` | **Partial port** | `11 hardware checks/`, `12 hardware/` |
| `2 Refresh/1-7 *.ps1` | .ps1 | Factory reset, autounattend.xml, reinstall, network driver bootstrap | No (out of scope — bare-metal flow) | Decline | `KNOWN-ISSUES.md` |
| `3 Setup/1 BitLocker.ps1` | .ps1 | BitLocker disable | No | Decline (security-sensitive, manual decision) | `KNOWN-ISSUES.md` |
| `3 Setup/2 Memory Compression.ps1` | .ps1 | `Disable-MMAgent -MemoryCompression` | No | Merge into `configure-mmagent.ps1` (Phase B group 1) | `5 registry tweaks/individual/configure-mmagent.ps1` |
| `3 Setup/3-12 *.ps1` | .ps1 | Convert Home→Pro, language/region, Edge/Store settings, Updates Pause | Partial (Updates Pause overlaps `disable-windows-update.ps1`) | Decline rest | `KNOWN-ISSUES.md` |
| `4 Installers/*` | .ps1 | MSI Afterburner / NV Profile Inspector / MoreClockTool / CRU installers | No | Decline (no bundled binaries) | `KNOWN-ISSUES.md` |
| `5 Graphics/1 Driver Clean.ps1` | .ps1 | DDU clean | Yes (`DduManual.ps1`, `DduAuto.ps1`) | Decline | — |
| `5 Graphics/2 Driver Install Latest.ps1` | .ps1 | Latest driver install | Yes (`6 gpu/install-gpu-driver.ps1`) | Decline | — |
| `5 Graphics/3 Driver Install Debloat & Settings.ps1` | .ps1 | Driver-debloat + post-install settings | Partial (we have post-install settings) | Decline (overlap) | `KNOWN-ISSUES.md` |
| `5 Graphics/4 Nvidia Settings.ps1` | .ps1 | NVIDIA driver registry settings | Yes (`6 gpu/nvidia/configure-nvidia.ps1`) | Decline | — |
| `5 Graphics/5 Amd Settings.ps1` | .ps1 | AMD driver registry settings | Yes (`6 gpu/amd/configure-amd.ps1`) | Decline | — |
| `5 Graphics/6 Intel Settings.ps1` | .ps1 | Intel driver registry settings | Yes (`6 gpu/intel/configure-intel.ps1`) | Decline | — |
| `5 Graphics/7 Hdcp.ps1` | .ps1 | HDCP toggle | No (display-quality concern, not gaming-perf) | Decline | `KNOWN-ISSUES.md` |
| `5 Graphics/8 P0 State.ps1` | .ps1 | Force NVIDIA P0 state via registry | No | **Port** | `6 gpu/nvidia/force-p0-state.ps1` |
| `5 Graphics/9 Msi Mode.ps1` | .ps1 | MSI mode + `DevicePriority` for GPU/NVMe/audio | Partial (we set `MSISupported` only on GPU) | **Merge GPU MSI only**; NVMe/audio priority remains backlog | `6 gpu/enable-msi-mode.ps1` |
| `5 Graphics/10 DirectX.ps1` | .ps1 | DirectX runtime install | Yes (`0 prerequisites/install-runtimes.ps1`) | Decline | — |
| `5 Graphics/11 C++.ps1` | .ps1 | VC++ redist install | Yes (`0 prerequisites/install-runtimes.ps1`) | Decline | — |
| `5 Graphics/12 Resolution Refresh Rate.ps1` | .ps1 | Manual UI step | No | Decline (manual) | `BIOS-CHECKLIST.md` |
| `5 Graphics/13 Hags Windowed.ps1` | .ps1 | Manual UI step | Partial (HAGS already enabled) | Decline (manual) | — |
| `6 Windows/1 Start Menu Taskbar.ps1` | .ps1 | Start/taskbar config | Partial (we cover taskbar basics) | Decline (preference, not perf) | — |
| `6 Windows/2 Start Menu Layout.ps1` | .ps1 | Start menu layout JSON | No | Decline (preference) | — |
| `6 Windows/3 Start Menu Shortcuts.ps1` | .ps1 | Start shortcuts | No | Decline (preference) | — |
| `6 Windows/4 Context Menu.ps1` | .ps1 | Restore classic right-click | Yes (apply step "Restore classic right-click menu") | Decline | — |
| `6 Windows/5 Theme Black.ps1` | .ps1 | Dark mode + black theme | Yes (apply step "Enable dark mode") | Decline | — |
| `6 Windows/6-7 *.ps1` | .ps1 | Lock screen / user pictures | No | Decline (cosmetic) | — |
| `6 Windows/8 Widgets.ps1` | .ps1 | Disable widgets | Yes (apply step "Disable Widgets") | Decline | — |
| `6 Windows/9 Copilot.ps1` | .ps1 | Disable Copilot | Yes (apply step "Disable Copilot") | Decline | — |
| `6 Windows/10 Gamemode.ps1` | .ps1 | Game Mode toggle | Yes (`AutoGameModeEnabled`) | Decline | — |
| `6 Windows/11-12 *.ps1` | .ps1 | Pointer precision / display scaling | Partial (mouse acceleration disabled) | Decline (preference) | — |
| `6 Windows/13 Bloatware.ps1` | .ps1 | Bloatware removal | Yes (`9 cleanup/debloat.ps1`) | Decline | — |
| `6 Windows/14-18 Bloatware * Check.ps1` | .ps1 | Diagnostic checks for bloat | No | Decline (diagnostic) | — |
| `6 Windows/19 Gamebar.ps1` | .ps1 | Game Bar lockdown (more keys than we have) | Partial | **Merge** missing keys | `APPLY-EVERYTHING.ps1` Game Bar step |
| `6 Windows/20 Edge & WebView.ps1` | .ps1 | Edge config | No | Decline (preference) | — |
| `6 Windows/21 Notepad Settings.ps1` | .ps1 | Notepad config | No | Decline (preference) | — |
| `6 Windows/22 Control Panel Settings.ps1` | .ps1 | Bulk control panel registry (108KB) | Partial (many overlap) | Decline (too broad to safely port wholesale) | `KNOWN-ISSUES.md` |
| `6 Windows/23 Sound.ps1` | .ps1 | Sound stub | Yes (sound scheme = None) | Decline | — |
| `6 Windows/24 Loudness EQ.ps1` | .ps1 | Manual UI step | No | Decline (manual) | — |
| `6 Windows/25 Device Manager Power Savings & Wake.ps1` | .ps1 | Disable USB selective suspend | Partial (covered by power plan) | Decline | — |
| `6 Windows/26 Network Adapter Power Savings & Wake.ps1` | .ps1 | Disable NIC power savings + WoL | No | **Port** | `7 network/disable-adapter-power-savings.ps1` |
| `6 Windows/27 Network IPv4 Only.ps1` | .ps1 | Disable IPv6 binding | No | **Port** as Security Trade-off | `7 network/disable-ipv6-binding.ps1` |
| `6 Windows/28 Write Cache Buffer Flushing.ps1` | .ps1 | Per-disk cache flush off | No | **Port opt-in** (data-loss risk) | `5 registry tweaks/individual/disable-write-cache-flush.ps1` |
| `6 Windows/29 Power Plan.ps1` | .ps1 | Power plan tuning (18KB) | Yes (we tune Ultimate Performance) | Decline (overlap) | — |
| `6 Windows/30 Timer Resolution.ps1` | .ps1 | `GlobalTimerResolutionRequests` policy | Yes (covered by `install-timer-resolution-service.ps1`) | Decline | — |
| `6 Windows/31 UAC.ps1` | .ps1 | Lower UAC | No | Decline (security) | `KNOWN-ISSUES.md` |
| `6 Windows/32 Core Isolation.ps1` | .ps1 | HVCI off | Yes (`8 security vs performance/configure-vbs.ps1`) | Decline | — |
| `6 Windows/33 Defender Optimize.ps1` | .ps1 | Defender lockdown | Partial (we have exclusions) | Decline (crosses safety line) | `KNOWN-ISSUES.md` |
| `6 Windows/34 Autoruns Startup Tasks & Apps Check.ps1` | .ps1 | Diagnostic | Partial | **Port launcher** | `13 external tools/launch-autoruns.ps1` |
| `6 Windows/35 Cleanup.ps1` | .ps1 | Temp cleanup | Yes (`9 cleanup/cleanup-temp.{bat,ps1}`) | Decline | — |
| `6 Windows/36 Restore Point.ps1` | .ps1 | Restore point | Yes (`1 backup/create-backup.ps1`) | Decline | — |
| `7 Hardware/1-8 *.ps1` | .ps1 | Polling rate / monitor tests / build guides | Partial — `12 hardware/` | **Partial port** | `12 hardware/` |
| `8 Advanced/1 Defender.ps1` | .ps1 | Defender disable | Partial (we have exclusions) | Decline (overlap with `6 Windows/33`) | `KNOWN-ISSUES.md` |
| `8 Advanced/2 Firewall.ps1` | .ps1 | Firewall config | No | Decline (security) | `KNOWN-ISSUES.md` |
| `8 Advanced/3 Spectre Meltdown.ps1` | .ps1 | Disable speculative-execution mitigations | No | **Port** as Security Trade-off | `5 registry tweaks/individual/disable-spectre-meltdown.ps1` |
| `8 Advanced/4 Data Execution Prevention.ps1` | .ps1 | DEP `bcdedit /set nx OptOut` | No | **Port** as Security Trade-off | `8 security vs performance/disable-dep.ps1` |
| `8 Advanced/5 File Download Security Warning.ps1` | .ps1 | Disable Mark of the Web SmartScreen warnings | No | Decline (security) | — |
| `8 Advanced/6 MMAgent Features.ps1` | .ps1 | Page combining / OperationAPI / SuperFetch | No | **Port** | `5 registry tweaks/individual/configure-mmagent.ps1` |
| `8 Advanced/7 ReBar Force.ps1` | .ps1 | Force-enable Resizable BAR via NVIDIA Profile Inspector | Partial (BIOS-CHECKLIST covers ReBAR) | Decline (relies on bundled tool) | `BIOS-CHECKLIST.md` |
| `8 Advanced/8 Smt Ht.ps1` | .ps1 | Disable SMT/HT | No | Decline (workload-specific, breaks productivity) | `KNOWN-ISSUES.md` |
| `8 Advanced/9 Core 1 Thread 1.ps1` | .ps1 | Single-core CPU affinity for explorer | No | Decline (breaks multithreading) | `KNOWN-ISSUES.md` |
| `8 Advanced/10 Priority.ps1` | .ps1 | Process priority registry | Partial (we set Game priority MMCSS) | Decline (overlap) | — |
| `8 Advanced/11 Mpo.ps1` | .ps1 | DWM Multiplane Overlay disable | No | **Port** | `5 registry tweaks/individual/disable-mpo.ps1` |
| `8 Advanced/12 Hardware Legacy Flip.ps1` | .ps1 | DWM legacy flip mode | Yes (combined with 13) | **Port** | `5 registry tweaks/individual/dwm-flip-model.reg` |
| `8 Advanced/13 Hardware Composed Independent Flip.ps1` | .ps1 | DWM composed-independent flip | Yes (combined with 12) | **Port** | `5 registry tweaks/individual/dwm-flip-model.reg` |
| `8 Advanced/14 Ulps.ps1` | .ps1 | AMD ULPS disable | No | **Port** AMD-only | `6 gpu/configure-amd-ulps.ps1` |
| `8 Advanced/15 Driver Whql Secure Boot Bypass.ps1` | .ps1 | Disable WHQL signing enforcement | No | Decline (real attack-surface increase) | `KNOWN-ISSUES.md` |
| `8 Advanced/16 Keyboard Shortcuts.ps1` | .ps1 | Disable keyboard shortcuts | No | Decline (preference) | — |
| `8 Advanced/17 Services.ps1` | .ps1 | Wholesale service disable list (57KB) | Partial | **Cherry-pick** WerSvc / RemoteRegistry / Browser | `4 services/disable-services.ps1` |
| `8 Advanced/18 Start Search Shell Mobsync.ps1` | .ps1 | Disable mobsync + search/shell tweaks | Partial (search tweaks already covered) | **Port** Offline Files / Sync Center only | `4 services/individual/mobsync-disable.ps1` |
| `8 Advanced/19 NVME Faster Driver.ps1` | .ps1 | Force-install Microsoft inbox `stornvme` | No | Decline (compatibility regression risk) | `KNOWN-ISSUES.md` |
| `IWR.ps1` | .ps1 | Bootstrapper that downloads + iex | n/a | N/A (their entrypoint, not portable) | — |
| `AllowScripts.cmd` | .cmd | Set ExecutionPolicy | n/a | Already documented in our `GUIDE.md` | — |

## Net additions

Ported and declined items are listed in the table above. Follow-up items after this inventory are tracked in `KNOWN-ISSUES.md`; shipped fixes are in `CHANGELOG.md`.

## Crediting

- `Notice.txt` (Khorvie Tech) — unchanged.
- `GUIDE.md` — gains a `## Credits` section listing FR33THY, Khorvie Tech, Chris Titus Tech, Wagnardsoft (DDU).
- Every ported file carries a `# Source: FR33THYFR33THY/Ultimate — <relative path>` header.
