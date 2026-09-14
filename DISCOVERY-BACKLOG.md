# Discovery Backlog

Audit target: `CC/hardcore-rubin-7d2584`
Audit date: 2026-05-06

Status values:
- `Implemented`: shipped by this audit branch.
- `Planned`: accepted for implementation in the follow-up commits from this audit.
- `Backlog`: real candidate, but not safe enough or not reversible enough for this pass.
- `Rejected`: does not pass the rubric for this toolkit.

## Implemented

### Disable Edge Background Mode and Startup Boost

- Sources: <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/startupboostenabled>, <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled>
- Mechanism: set `HKLM:\SOFTWARE\Policies\Microsoft\Edge\StartupBoostEnabled=0` and `HKLM:\SOFTWARE\Policies\Microsoft\Edge\BackgroundModeEnabled=0`.
- Tier: `Safe`
- Proposed path: `5 registry tweaks/individual/disable-edge-background.ps1`
- Proof not covered: `rg -n "StartupBoostEnabled|BackgroundModeEnabled|Microsoft\\Edge" .` only found older `Windows\EdgeUI` privacy keys, not Chromium Edge policies.
- Risk note: Edge may cold-start more slowly and background Edge apps/extensions stop when Edge closes.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=yes, Tierable=yes.
- Status: `Implemented`

### Disable NTFS Last-Access Updates

- Sources: <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-behavior>, <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-8dot3name>
- Mechanism: set `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\NtfsDisableLastAccessUpdate=1`.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/disable-ntfs-last-access.ps1`
- Proof not covered: `rg -n "NtfsDisableLastAccessUpdate|disablelastaccess|NtfsDisable8dot3|MftZone" .` returned no matches.
- Risk note: legacy backup, indexing, or audit tools that rely on last-access timestamps may see stale access times.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=yes, Tierable=yes.
- Status: `Implemented`

### Audio MMCSS Task Tuning

- Path: `5 registry tweaks/individual/tune-mmcss-audio.ps1` + `restore-mmcss-audio.ps1`
- Status: `Implemented`

### DWM Hardware Flip Model Overrides

- Path: `5 registry tweaks/individual/dwm-flip-model.reg` + `revert-dwm-flip-model.reg`
- Status: `Implemented`

## Backlog

### NVIDIA Profile Inspector Automation

- Sources: <https://github.com/Orbmu2k/nvidiaProfileInspector>, <https://github.com/FR33THYFR33THY/Ultimate>
- Mechanism: runtime-download NVIDIA Profile Inspector and apply profile settings through its CLI or import profile.
- Tier: `Advanced`
- Proposed path: `6 gpu/nvidia/configure-profile-inspector.ps1`
- Proof not covered: `rg -n "nvidiaProfileInspector|Profile Inspector|setProfileSetting" .` returned no matches.
- Risk note: external binary versioning, profile setting IDs, and driver behavior are brittle; a rollback needs a profile backup/restore format.
- Rubric: Real=yes, Current=likely, Not covered=yes, Automatable=yes, Reversible=unclear, Tierable=yes.
- Status: `Backlog`

### Kernel Timer Boot Parameters

- Sources: <https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set>, <https://github.com/djdallmann/GamingPCSetup>
- Mechanism: `bcdedit /set disabledynamictick yes`, `bcdedit /set useplatformclock yes|no`, `bcdedit /set tscsyncpolicy Enhanced`.
- Tier: `Advanced`
- Proposed path: `8 security vs performance/configure-kernel-timers.ps1`
- Proof not covered: `rg -n "disabledynamictick|useplatformclock|tscsyncpolicy" .` returned no matches.
- Risk note: timer source changes are hardware-dependent and can hurt latency or stability.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=yes, Tierable=yes.
- Status: `Backlog`

### Broad Memory Manager Tweaks

- Sources: <https://github.com/djdallmann/GamingPCSetup>, <https://github.com/undergroundwires/privacy.sexy>
- Mechanism: `ClearPageFileAtShutdown`, `LargeSystemCache`, `DisablePagingExecutive`, `IoPageLockLimit`, `PoolUsageMaximum`.
- Tier: `Advanced` or `Security Trade-off`
- Proposed path: `5 registry tweaks/individual/configure-memory-manager.ps1`
- Proof not covered: `rg -n "ClearPageFileAtShutdown|LargeSystemCache|DisablePagingExecutive|IoPageLockLimit|PoolUsageMaximum" .` returned no matches.
- Risk note: these keys are workload- and memory-pressure-dependent; several can reduce performance on modern Windows.
- Rubric: Real=yes, Current=mixed, Not covered=yes, Automatable=yes, Reversible=yes, Tierable=mixed.
- Status: `Backlog`

### NTFS 8.3, MFT Zone, and NTFS Memory Usage

- Sources: <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-8dot3name>, <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-behavior>
- Mechanism: `NtfsDisable8dot3NameCreation`, `NtfsMftZoneReservation`, `NtfsMemoryUsage`.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/optimize-ntfs-advanced.ps1`
- Proof not covered: `rg -n "NtfsDisable8dot3|MftZone|NtfsMemoryUsage|memoryusage" .` returned no matches.
- Risk note: 8.3 changes can break old installers and MFT zone tuning is disk/workload-specific.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=partial, Tierable=yes.
- Status: `Backlog`

### Keyboard and Mouse Class Queue Sizes

- Sources: <https://github.com/djdallmann/GamingPCSetup>, <https://github.com/FR33THYFR33THY/Ultimate>
- Mechanism: `HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters\MouseDataQueueSize` and `kbdclass\Parameters\KeyboardDataQueueSize`.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/configure-input-queues.ps1`
- Proof not covered: `rg -n "MouseDataQueueSize|KeyboardDataQueueSize|mouclass|kbdclass" .` returned no matches.
- Risk note: evidence is mostly community benchmarking; bad values can cause input buffering side effects.
- Rubric: Real=partial, Current=unclear, Not covered=yes, Automatable=yes, Reversible=yes, Tierable=yes.
- Status: `Backlog`

### Telemetry Scheduled Task Disabling

- Sources: <https://github.com/undergroundwires/privacy.sexy>, <https://github.com/hellzerg/optimizer>
- Mechanism: disable tasks such as Compatibility Appraiser, ProgramDataUpdater, Consolidator, and UsbCeip.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/disable-telemetry-tasks.ps1`
- Proof not covered: `rg -n "Compatibility Appraiser|ProgramDataUpdater|Customer Experience|Consolidator|UsbCeip" .` returned no matches.
- Risk note: disabling compatibility diagnostics can reduce Microsoft telemetry but may affect upgrade readiness checks.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=requires new scheduled-task helper, Tierable=yes.
- Status: `Backlog`

### Vendor-Specific NIC Advanced Properties

- Sources: <https://github.com/djdallmann/GamingPCSetup>, <https://github.com/FR33THYFR33THY/Ultimate>
- Mechanism: `Set-NetAdapterAdvancedProperty` for Intel, Killer, and Realtek display names such as interrupt moderation and flow control.
- Tier: `Advanced`
- Proposed path: `7 network/configure-vendor-nic.ps1`
- Proof not covered: `rg -n "Interrupt Moderation|Flow Control|\\*FlowControl|\\*InterruptModeration|Killer|Realtek" .` returned no generic vendor tuning coverage.
- Risk note: advanced property names vary by driver, language, and adapter vendor; defaults are hard to restore without snapshot helpers.
- Rubric: Real=yes, Current=yes, Not covered=partial, Automatable=partial, Reversible=requires new helper, Tierable=yes.
- Status: `Backlog`

### MSIX / Store Package Removal Expansion

- Sources: <https://github.com/bmrf/tron>, <https://github.com/hellzerg/optimizer>, <https://github.com/ChrisTitusTech/winutil>
- Mechanism: remove additional inbox packages such as Phone Link, Cross Device, Clipchamp, or Cortana-era leftovers.
- Tier: `Advanced`
- Proposed path: `9 cleanup/debloat.ps1`
- Proof not covered: current `debloat.ps1` package list does not include every package named in those catalogs.
- Risk note: app removal is noisy across Windows builds and Store reinstall behavior is inconsistent.
- Rubric: Real=yes, Current=yes, Not covered=partial, Automatable=yes, Reversible=weak, Tierable=yes.
- Status: `Backlog`

### Standby List Automation

- Sources: <https://www.wagnardsoft.com/forums/viewtopic.php?t=1256>, <https://github.com/FR33THYFR33THY/Ultimate>
- Mechanism: download ISLC or EmptyStandbyList and schedule periodic standby-list clearing.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/install-standby-list-cleaner.ps1`
- Proof not covered: `rg -n "ISLC|Intelligent standby|EmptyStandbyList|standby list" .` returned no matches.
- Risk note: external binary dependency and scheduled memory clearing can hide rather than fix memory pressure.
- Rubric: Real=yes, Current=yes, Not covered=yes, Automatable=yes, Reversible=partial, Tierable=yes.
- Status: `Backlog`

### Rainbow Six Siege Config Templates

- Sources: <https://www.ubisoft.com/en-us/help/rainbow-six-siege>, community configuration discussions from R6S players.
- Mechanism: edit `GameUserSettings.ini` and `Settings.ini` under the user's R6S profile.
- Tier: `Advanced`
- Proposed path: `5 registry tweaks/individual/configure-r6s-settings.ps1`
- Proof not covered: `rg -n "Rainbow|R6S|GameUserSettings|Settings.ini" .` returned no matches.
- Risk note: game-specific settings are preference-heavy and can be overwritten by patches, cloud sync, or anti-cheat expectations.
- Rubric: Real=partial, Current=unclear, Not covered=yes, Automatable=yes, Reversible=requires per-user backup, Tierable=yes.
- Status: `Backlog`

## Rejected

### Disable Core Security Features Beyond Existing VBS / DEP / Spectre Choices

- Sources: <https://github.com/Atlas-OS/Atlas>, <https://github.com/FR33THYFR33THY/Ultimate>
- Mechanism: disable BitLocker, firewall, driver signing, SmartScreen / Mark-of-the-Web, or Defender outright.
- Tier: `Security Trade-off`
- Proposed path: none
- Proof not covered: some adjacent choices exist, but these exact aggressive disables are intentionally absent.
- Risk note: these are clear attack-surface increases and do not fit default-on gaming optimization.
- Rubric: Real=yes, Current=yes, Not covered=partial, Automatable=yes, Reversible=partial, Tierable=yes.
- Status: `Rejected`
