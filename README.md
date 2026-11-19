# Vortex / Nexus free-download loop

This is a local PowerShell + Windows UI Automation script. It uses no LLM, API, browser extension, credentials, or third-party package.

## What it does

- Reads the current mod name and counter from Vortex's manual-download dialog.
- Clicks only **Download manually** in Vortex.
- Waits until the active Opera page title matches that mod, then clicks only **Slow download**.
- Waits for Vortex to advance automatically or for **Open Vortex** to appear; it does not change the always-allow setting.
- Verifies the Vortex mod name changed after the handoff.
- If the mod remains stalled, tries the browser's **Start download manually** link up to three times and retries through Vortex once; it stops if progress is still unverified.
- Stops rather than guessing if a control is missing, the page/mod names do not match, or an unexpected login/CAPTCHA/error appears.

It does not click Premium, skip a mod, endorse, install, or change browser permissions.

## Run

Open Vortex and Opera to the collection/download workflow, then open PowerShell in this folder:

```powershell
# Read current state only; no clicks
.\vortex-nexus-loop.ps1

# Do one item
.\vortex-nexus-loop.ps1 -Once

# Continue until the Vortex manual-download dialog is gone
.\vortex-nexus-loop.ps1 -Run
```

Press **Ctrl+C** to stop a continuous run. Each wait is condition-based, with a 90-second timeout (`-TimeoutSeconds 90` by default). If Vortex has no manual-download dialog, the script stops without touching other controls.

## Verification / current limitation

Experimental: the loop has completed multiple real downloads, but can stop if browser controls are off-screen or a handoff cannot be verified. Vortex or Opera may change focus during operation. Inspect the applications before restarting a stopped run; a download may still be in progress. An absent Vortex manual-download dialog does not necessarily mean the installation is complete.

Run the offline name-matching and retry-policy tests with `.\vortex-loop-core.Tests.ps1`.
