# BIOS Optimization Checklist for Gaming

> These settings can't be scripted — you must change them manually in your motherboard's BIOS/UEFI.
> To enter BIOS: restart your PC and press **DEL** or **F2** repeatedly during boot (varies by brand).

---

## WARNING: What NOT to Touch

- **DO NOT** change CPU voltage/Vcore unless you know exactly what you're doing
- **DO NOT** flash your BIOS unless you have a specific reason (and a backup method)
- **DO NOT** enable overclocking profiles you don't understand
- **DO NOT** change memory timings manually (just enable XMP/DOCP/EXPO)
- If something goes wrong: clear CMOS (check your motherboard manual for the jumper or button)

---

## The Checklist

### 1. Enable XMP / DOCP / EXPO (RAM Speed)

**Impact: 10-30% FPS boost in CPU-bound games**

Your RAM likely runs at 2133 MHz by default, even if you bought 3200/3600/6000 MHz sticks.
Enabling the memory profile makes it run at its rated speed.

- [ ] Find the XMP / DOCP / EXPO setting (see vendor sections below)
- [ ] Enable **Profile 1** (the default profile)
- [ ] Save and reboot — verify in Task Manager > Performance > Memory

| Brand | Name |
|-------|------|
| Intel platforms | XMP (Extreme Memory Profile) |
| AMD Ryzen (DDR4) | DOCP (Direct Over Clock Profile) |
| AMD Ryzen (DDR5) | EXPO (Extended Profiles for Overclocking) |

### 2. Enable Resizable BAR / Above 4G Decoding

**Impact: 5-15% FPS in supported games**

Allows the CPU to access the full GPU VRAM at once instead of in 256MB chunks.

- [ ] Enable **Above 4G Decoding** (required first)
- [ ] Enable **Resizable BAR** (may be called Re-Size BAR Support)
- [ ] **Disable CSM** (Compatibility Support Module) — required for ReBAR to work
- [ ] Verify in Windows: `12 hardware/check-rebar.ps1` (read-only), GPU-Z, or NVIDIA Control Panel > System Info > "Resizable BAR: Yes". Opt-in force when firmware enumerated it off: `6 gpu/force-rebar.ps1`.

> **Note:** Requires NVIDIA RTX 3000+, AMD RX 5000+, or Intel Arc. Older GPUs don't support it.

### 3. Set PCIe Link Speed

- [ ] Find PCIe slot configuration (usually under "Advanced" or "Chipset")
- [ ] Set your primary GPU slot to **Gen 4** or **Gen 5** (not Auto)
- [ ] Auto can sometimes negotiate down to Gen 3, wasting bandwidth

> **Note:** Only set to Gen 5 if both your GPU and motherboard support it. Gen 4 is fine for all current GPUs.

### 4. Disable CSM (Use UEFI Only)

- [ ] Set **CSM** to **Disabled**
- [ ] This is required for Resizable BAR and Secure Boot
- [ ] If you dual-boot with a legacy OS, you may need CSM — skip this step

> **Warning:** If your Windows was installed in Legacy/MBR mode, disabling CSM will prevent booting.
> Check first: open CMD as Admin, run `bcdedit` — if it shows "winload.efi" you're on UEFI (safe to disable CSM).

### 5. CPU Fan Profile

- [ ] Set CPU fan curve to **Performance** or **Turbo** (not Silent)
- [ ] Cooler temps = higher boost clocks = better FPS
- [ ] If you have an AIO/liquid cooler, set pump to 100% always

### 6. Disable Unused Onboard Devices

Saves IRQ/DMA resources and can reduce latency:

- [ ] **Onboard audio** — disable if you use a USB/PCIe sound card
- [ ] **Onboard WiFi/Bluetooth** — disable if you use a PCIe WiFi card or Ethernet only
- [ ] **Serial/Parallel ports** — disable (nobody uses these)
- [ ] **Onboard LAN #2** — disable if you only use one Ethernet port
- [ ] **RGB/LED controller** — disable if you don't use motherboard RGB

---

## Where to Find These Settings (by Vendor)

### ASUS

| Setting | Location |
|---------|----------|
| XMP/DOCP/EXPO | AI Tweaker > AI Overclock Tuner > XMP I / DOCP |
| Resizable BAR | Advanced > PCI Subsystem > Re-Size BAR Support |
| Above 4G Decoding | Advanced > PCI Subsystem > Above 4G Decoding |
| CSM | Boot > CSM > Launch CSM: Disabled |
| PCIe Speed | Advanced > PCI Subsystem > PCIe Speed |
| Fan Profile | Monitor > Q-Fan Configuration |

### MSI

| Setting | Location |
|---------|----------|
| XMP/DOCP/EXPO | OC > DRAM Settings > XMP / A-XMP / EXPO |
| Resizable BAR | Settings > Advanced > PCI Subsystem > Re-Size BAR Support |
| Above 4G Decoding | Settings > Advanced > PCI Subsystem > Above 4G Decoding |
| CSM | Settings > Advanced > Windows OS Configuration > CSM/UEFI |
| PCIe Speed | Settings > Advanced > PCI Subsystem > PEG0 Gen |
| Fan Profile | Hardware Monitor > Fan Control |

### Gigabyte

| Setting | Location |
|---------|----------|
| XMP/DOCP/EXPO | Tweaker > Extreme Memory Profile (XMP) / EXPO |
| Resizable BAR | Settings > IO Ports > Re-Size BAR Support |
| Above 4G Decoding | Settings > IO Ports > Above 4G Decoding |
| CSM | Boot > CSM Support: Disabled |
| PCIe Speed | Settings > IO Ports > PCIEX16 Slot Configuration |
| Fan Profile | Smart Fan 5 (or 6) |

### ASRock

| Setting | Location |
|---------|----------|
| XMP/DOCP/EXPO | OC Tweaker > DRAM Configuration > Load XMP Setting |
| Resizable BAR | Advanced > PCI Configuration > Re-Size BAR Support |
| Above 4G Decoding | Advanced > PCI Configuration > Above 4G Decoding |
| CSM | Boot > CSM: Disabled |
| PCIe Speed | Advanced > PCI Configuration > PCIE Link Speed |
| Fan Profile | H/W Monitor > Fan Configuration |

---

## After BIOS Changes

1. Save and exit BIOS (usually F10)
2. Let Windows boot normally
3. Verify RAM speed: **Task Manager > Performance > Memory** (should show rated speed)
4. Verify Resizable BAR: `12 hardware/check-rebar.ps1`, **GPU-Z**, or the driver control panel. Opt-in force: `6 gpu/force-rebar.ps1`.
5. If system won't boot: clear CMOS (reset to defaults) and try again with fewer changes

---

## Quick Impact Summary

| Setting | Impact | Risk |
|---------|--------|------|
| XMP/DOCP/EXPO | 10-30% FPS (CPU-bound games) | Very Low (uses rated specs) |
| Resizable BAR | 5-15% FPS (game-dependent) | None |
| PCIe Gen 4/5 | 0-5% (prevents downgrade) | None |
| Disable CSM | Required for ReBAR | Low (check UEFI boot first) |
| Fan: Performance | 2-5% (higher boost clocks) | None (louder fans) |
| Disable unused devices | 0-2% (reduces latency) | None |

---

## Diagnostic Tools

These tools are not bundled with the toolkit, but they are the standard kit for verifying BIOS settings, monitoring temps under load, and capturing baseline benchmarks before and after tuning. Install whichever you need from the upstream source.

The Codex audit also added software-only Edge background and NTFS last-access tweaks under `5 registry tweaks/individual/`. They do not require BIOS/UEFI changes.

| Tool | What it tells you | Source |
|------|-------------------|--------|
| HWInfo64 | Sensor readout: per-core clocks, package temps, VRM telemetry, RAM speed and timings | <https://www.hwinfo.com> |
| GPU-Z | GPU clocks, memory speed, ReBAR status, BIOS version, sensor log | <https://www.techpowerup.com/gpuz> |
| CPU-Z | CPU model and stepping, cache topology, RAM SPD profiles | <https://www.cpuid.com/softwares/cpu-z.html> |
| MemTest86 | RAM stability test (boot from USB, hours-long burn-in) | <https://www.memtest86.com> |
| CrystalDiskInfo | SMART health, drive temps, total host writes | <https://crystalmark.info> |
| LatencyMon | DPC latency profiling — diagnoses driver-induced stutter | <https://www.resplendence.com/latencymon> |
| Furmark / OCCT | Synthetic GPU / PSU stress tests | <https://www.ozone3d.net> / <https://www.ocbase.com> |

After applying BIOS changes:

1. Verify RAM speed: **Task Manager > Performance > Memory**. Should show rated speed, not 2133 / 2400 MHz default.
2. Verify ReBAR: `12 hardware/check-rebar.ps1`, or **GPU-Z** main tab (`Resizable BAR: Enabled`). Opt-in force: `6 gpu/force-rebar.ps1`.
3. Profile DPC latency: **LatencyMon** for 5 minutes idle, then 5 minutes in-game. Anything > 1000 µs warrants driver investigation.
