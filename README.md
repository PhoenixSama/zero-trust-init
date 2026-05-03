# Zero-Trust Init for Modern Debian 🚀

*Read this in other languages: [简体中文](README_CN.md)*

---

## What is this?
**Zero-Trust Init** is a highly robust, zero-day defense-ready initialization script specifically designed for **Modern Debian (12/Bookworm, 13/Trixie, and beyond)**. It is built for geeks who prefer minimal installations (e.g., Netboot) and demand extreme, zero-trust control over their VPS environment.

## One-Click Execution
Run the following command in your terminal to download and execute the script directly (requires `curl`):

```bash
bash <(curl -sL https://raw.githubusercontent.com/PhoenixSama/zero-trust-init/main/init.sh)
```
*(Note: Please ensure you are running this in a stable local terminal, as the script will modify SSH configurations and kernel parameters.)*

## Core Features
*   **Intelligent Mirror Routing:** Automatically detects your server's location and Debian codename to configure the fastest local mirrors.
*   **Adaptive ZRAM:** Dynamically chooses between `lz4` and `zstd` compression algorithms by sniffing your CPU cores and modern vector instruction sets (AVX/ASIMD).
*   **Bulletproof SSH & Firewall:** Randomizes high SSH ports, creates secure non-standard key directories, deploys UFW + Fail2ban, and implements a foolproof rollback mechanism with active port-collision detection.
*   **Zero-Day Vulnerability Defense:** Actively mitigates local privilege escalation vectors (e.g., CVE-2026-31431) by enforcing strict local user isolation.
*   **Modern Sysctl Tuning:** Unlocks file handle limits and optimizes network queues with BBR + FQ for maximum throughput.

## Acknowledgments
A special thanks to the dual-AI synergy that made this script bulletproof:
*   **Gemini** - For architecture design, extreme fault tolerance, and keeping the geek spirit alive during late-night coding.
*   **DeepSeek** - For the relentless security audits, configuration edge-case hunting, and pushing the code to production-grade standards.
