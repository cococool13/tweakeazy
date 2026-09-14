SECURITY vs PERFORMANCE — READ THIS FIRST
Windows 11 Gaming Optimization Guide
============================================

This is the most impactful single tweak in this entire guide, but it
comes with a real security trade-off. Read this before deciding.

== WHAT IS VBS / MEMORY INTEGRITY? ==

VBS (Virtualization-Based Security) uses hardware virtualization to
create an isolated memory region that protects Windows from
kernel-level attacks. Memory Integrity (HVCI) prevents unsigned
drivers and malicious code from running in the kernel.

In plain English: it's a security wall that protects your PC from
advanced malware that tries to modify Windows at the deepest level.

== WHY DISABLE IT? ==

VBS adds a virtualization layer between your hardware and Windows.
This layer has a measurable performance cost:

  - 5-25% FPS loss in many games (depends on CPU and game)
  - Higher CPU overhead from hypervisor interrupts
  - More noticeable on older CPUs (Intel 10th/11th gen, Ryzen 3000)
  - Less noticeable on newest CPUs (Intel 14th+, Ryzen 7000+)

Multiple independent benchmarks (Tom's Hardware, TechPowerUp,
Hardware Unboxed) have confirmed this performance impact.

== THE HONEST TRADE-OFF ==

  DISABLING VBS:
    + Better FPS (5-25% in many games)
    + Lower CPU overhead
    + Reduced input latency
    - Less protection against kernel exploits
    - Less protection against rootkits
    - LSA Protection also disabled (credential dumping possible)
    - Not recommended for PCs that handle sensitive data (banking, work)

  KEEPING VBS ENABLED:
    + Full Windows security stack active
    + Protection against advanced malware
    - Lower gaming performance

== WHO SHOULD DISABLE IT? ==

  SAFE to disable if:
    - This is a dedicated gaming PC
    - You don't browse sketchy websites
    - You don't download pirated software
    - You have a good antivirus (Windows Defender is fine)
    - You keep Windows and drivers updated

  KEEP ENABLED if:
    - You use this PC for work with sensitive data
    - You handle banking/financial information on this PC
    - You're not comfortable with the security trade-off
    - The FPS difference doesn't matter to you

== HOW TO APPLY ==

  Use configure-vbs.ps1 (elevated PowerShell). Default run is
  report-only; pass a flag to mutate:

  To disable:  .\configure-vbs.ps1 -Disable
               Then REBOOT.

  To re-enable: .\configure-vbs.ps1 -Enable
                Then REBOOT.

  To verify: After reboot, press Win+R, type "msinfo32", Enter.
             Look for "Virtualization-based security" — should say
             "Not enabled" if disabled, or "Running" if enabled.

== QUICK SETTINGS CHECK (no script needed) ==

  You can also toggle Memory Integrity through Windows Settings:
    Settings > Privacy & Security > Windows Security > Device Security
    > Core Isolation Details > Memory Integrity > Off

  This only disables HVCI, not full VBS. The scripts in this folder
  disable both for maximum performance gain.
