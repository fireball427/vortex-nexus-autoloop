# Vortex / Nexus free-download loop

This is a local PowerShell + Windows UI Automation script. It uses no LLM, API, browser extension, credentials, or third-party package.

## What it does

- Reads the current mod name and counter from Vortex's manual-download dialog.
- Clicks only **Download manually** in Vortex.
- Detects the Windows default HTTPS browser (Chrome or Opera/Opera GX) and selects its browser window before clicking anything.
- Waits until the selected browser page title matches that mod, then clicks only **Slow download**.
- Waits for Vortex to advance automatically or for **Open Vortex** to appear; it does not change the always-allow setting.
- Verifies both a changed Vortex mod name and an increased collection queue counter after the handoff.
- If the mod remains stalled, tries the browser's **Start download manually** link up to three times using mouse-style messages at its current on-screen position. The first attempt sends up to three rapid clicks; later attempts send one. If the link changes during those clicks, it stops clicking and checks for handoff. After those attempts it retries through Vortex once. If the mod still matches and the link is visible, it makes one final browser retry, then stops if progress is still unverified. Repeated clicks may create duplicate requests.
- Stops rather than guessing if a control is missing, the page/mod names do not match, or an unexpected login/CAPTCHA/error appears.

The default flow does not click **Skip mod**. Neither flow clicks Premium, endorses, installs, or changes browser permissions.

## Setup

1. Use Windows with Vortex, PowerShell, and Chrome or Opera/Opera GX. Set your chosen supported browser as the Windows default for HTTPS, open it, and sign in to Nexus yourself. The script does not handle credentials or CAPTCHA.
2. Download or clone this repository and keep all its files together in one folder.
3. Start installing a collection in Vortex and wait for its **Download mod** dialog with the **Download manually** button. This project has been tested with a Cyberpunk 2077 collection; other games are not verified.
4. If you have multiple windows of the default browser, keep a Nexus page active in exactly one window. The script selects that window by title and stops if selection is ambiguous. Keep the browser and Vortex windows available; the script uses their accessibility controls, not fixed recorded coordinates.
5. If the browser asks to open Vortex, you can handle the prompt manually. You may choose the browser's **Always allow** option for Nexus yourself; it is a persistent permission and the script does not enable it. Chrome's automatic prompt click was not reliable in initial testing; inspect and handle it manually if needed.

## Run

Open PowerShell in the project folder and use:

```powershell
# Read current state only; no clicks
.\vortex-nexus-loop.ps1

# Do one item
.\vortex-nexus-loop.ps1 -Once

# Continue until the Vortex manual-download dialog is gone
.\vortex-nexus-loop.ps1 -Run
```

Press **Ctrl+C** to stop a continuous run. Some waits use `-TimeoutSeconds` (90 seconds by default), while the handoff retry checks use shorter bounded waits. If Vortex has no manual-download dialog, the script stops without touching other controls. If PowerShell blocks scripts, a one-run alternative is `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\vortex-nexus-loop.ps1 -Once`; use `-Run` only after checking the one-item result.

## Experimental skip flow (Opera)

```powershell
# Inspect without clicking
.\vortex-nexus-loop.ps1 -Browser opera -SkipAfterSlowDownload

# Try one item, then verify its archive in Vortex Downloads
.\vortex-nexus-loop.ps1 -Browser opera -Once -SkipAfterSlowDownload

# Only after the one-item check succeeds
.\vortex-nexus-loop.ps1 -Browser opera -Run -SkipAfterSlowDownload
```

This mode clicks **Skip mod** after detecting the Nexus countdown, without waiting for it to finish or clicking **Open Vortex**. If the browser click cannot be verified, the script asks you to check it manually. It never skips on an unconfirmed browser action.

- **New mod name:** Start the next item with **Download manually**, even if the queue counter is unchanged.
- **Same mod name and counter:** After up to 10 seconds, retry **Download manually** once if both controls are available. If the retry still stalls on the same item, the script offers one manual **Skip mod** click.
- **Stopping:** The script stops if there is no **Download manually** button at the start of a cycle or if it confirms the final dialog closed. Unresolved errors stop skip mode rather than restarting it.

Queue progress or closure does not prove that the archive finished downloading or the mod installed.

## Tested environment

On 20 November 2026, a Cyberpunk 2077 collection was tested on Windows 11 with Vortex 2.11.0, Opera GX 136.0.6008.76 and Google Chrome 157.0.8103.79. Chrome was tested for a one-item handoff with Nexus's always-allow permission enabled; its manual-start fallback and unticked-permission flow need more testing. Nexus, Vortex and browser interfaces can change; these results do not guarantee compatibility.

## Verification / current limitation

Experimental: the loop has completed multiple real downloads, but can stop if browser controls are off-screen or a handoff cannot be verified. Vortex or Opera may change focus during operation. Inspect the applications before restarting a stopped run; a download may still be in progress. An absent Vortex manual-download dialog does not necessarily mean the installation is complete.

If Opera opens the correct mod page but the script cannot detect **Slow download**, try restarting Opera, then inspect the current Vortex and browser state before starting the script again. A restart restored the controls in one observed case; it may not fix every cause.

Run the name-matching and retry-policy tests with `.\vortex-loop-core.Tests.ps1`. Run `.\vortex-mouse.Tests.ps1` to test mouse-message delivery to a local test window (the window briefly appears). These tests do not prove that Nexus accepted a download.
