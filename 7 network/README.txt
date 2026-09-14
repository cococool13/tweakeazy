NETWORK OPTIMIZATION
Windows 11 Gaming Optimization Guide
============================================

What this does:
  Optimizes TCP/IP settings and DNS to reduce network latency in online games.
  The biggest impact comes from disabling Nagle's Algorithm, which
  normally batches small packets together (adds ~200ms delay).

Scripts included:
  optimize-network.ps1                  — Apply all network tweaks (tracked)
  revert-network.bat                    — Restore all defaults
                                          (no .ps1 revert: REVERT-EVERYTHING.ps1
                                          handles tracked-state restore)
  disable-adapter-power-savings.ps1     — Per-NIC power savings + WoL off
                                          (paired with enable-adapter-power-savings.ps1)
  disable-ipv6-binding.ps1              — IPv4-only operation
                                          (paired with enable-ipv6-binding.ps1)
                                          TIER: Security Trade-off — read header.

What it changes:
  - Disables Nagle's Algorithm (reduces packet batching delay)
  - Disables Large Send Offload (CPU handles packets instead of NIC)
  - Disables TCP Timestamps (reduces packet overhead)
  - Enables RSS (spreads network load across CPU cores)
  - Enables Direct Cache Access (reduces memory latency for packets)
  - Sets DNS to Cloudflare Gaming (1.1.1.1 / 1.0.0.1) with IPv6
  - Flushes DNS cache

== DNS OPTIMIZATION ==

  The script sets DNS to Cloudflare (1.1.1.1) by default. This can
  shave 10-50ms off game server lookups compared to ISP DNS.

  Alternative DNS providers you can set manually:
    Cloudflare:  1.1.1.1 / 1.0.0.1       (fastest, privacy-focused)
    Google:      8.8.8.8 / 8.8.4.4       (reliable, global)
    Quad9:       9.9.9.9 / 149.112.112.112 (security-focused)

  To change DNS manually:
    Settings > Network & internet > Your adapter > DNS server assignment > Edit
    Set to "Manual" and enter your preferred DNS addresses.

  Note on DNS over HTTPS (DoH):
    Windows 11 supports DoH for encrypted DNS. It adds ~5ms latency.
    For competitive gaming: leave DoH off (latency matters more).
    For casual gaming: DoH is fine and more private.

== ROUTER / NETWORK TIPS ==

  QoS (Quality of Service):
    Most modern routers support QoS. Log into your router admin page
    and prioritize your gaming PC's traffic. Methods vary by router:
    - Some let you prioritize by device (MAC address)
    - Some let you prioritize by application/port
    - Some have a "Gaming" or "Multimedia" preset

  Port Forwarding for Common Games:
    If you're behind strict NAT, forwarding these ports can help:
    - Xbox Live / Microsoft:  TCP 3074, UDP 3074, 88, 500, 3544, 4500
    - PlayStation Network:    TCP 80, 443, 3478-3480 / UDP 3074, 3478-3479
    - Steam:                  TCP 27015-27030 / UDP 27000-27031, 4380
    - Valorant:               TCP 443 / UDP 7000-7500, 8180-8181
    - Fortnite:               TCP 80, 443, 5222, 5795-5847 / UDP 5222, 5795-5847
    - Call of Duty:           TCP 3074, 27014-27050 / UDP 3074, 3478, 4379-4380

    How to port forward: log into your router (usually 192.168.1.1),
    find "Port Forwarding" or "Virtual Server", and add rules for your PC's
    local IP address.

  WiFi Optimization (Laptops):
    - Use 5GHz band (not 2.4GHz) — less interference, lower latency
    - Disable "WiFi scanning while connected" if available in adapter settings:
      Device Manager > Network Adapters > Your WiFi > Properties > Advanced
      Look for "Scan when associated" or "Roaming Aggressiveness" — set to lowest
    - Disable Bluetooth if not using it (shares the 2.4GHz antenna)
    - Sit close to your router or use a WiFi 6/6E mesh system

Recommended third-party tool:
  TCP Optimizer by SpeedGuide.net
    Download: https://www.speedguide.net/downloads.php
    What it does: GUI tool that applies hundreds of TCP/IP tweaks.
      Use the "Optimal" preset for a good starting point.
    DO NOT bundle this tool — download it fresh from the official site.
