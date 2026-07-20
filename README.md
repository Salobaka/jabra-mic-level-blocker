# Jabra Mic Level Blocker

A tiny native macOS app that prevents a **Jabra Elite 85h** headset from muting itself during calls, with additional support for **Daisy One** headsets.

## The problem

Our team uses six Jabra Elite 85h headsets. They have an annoying built-in "feature" that disables the microphone on very loud input noise. In practice it triggers false positives almost every day — especially in coworking spaces — and mutes me in the middle of an emotional speech or an important call.

## What this app does

This menu-bar tool keeps the Jabra input gain at a safe minimum level and actively prevents the OS or meeting apps from pulling it down to zero. That way the headset never gets a chance to think it should auto-mute.

## Features

- Menu-bar icon with a popover containing all controls
- Floating HUD with live mic level meter (Jabra Elite 85h)
- Input gain fader from **10% to 100%** — set the mic level in percent, not arbitrary units
- **10% minimum gain is always enforced** — you can never be accidentally muted to zero
- **Unmute on every gain write** — clears the hardware/OS mute flag
- **Lock input level** — re-applies the chosen gain 4× per second so apps like MS Teams, Kumospace, Zoom and Google Meet cannot pull the mic level down
- Restores the previous default input device when the meter is turned off or the app quits
- Explicit microphone permission handling for macOS
- **Daisy One** support: detects the headset, intercepts the Play/Pause media key to toggle mute, and plays a feedback sound

## Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Jabra Elite 85h and/or Daisy One paired and available as an audio input device
- Microphone, Bluetooth, and Input Monitoring permissions (the app prompts on first launch)

## Tested on

- Apple Silicon M3 Max / M3 Ultra / M4
- macOS Sonoma 14.x
- macOS Sequoia 15.x
- macOS Tahoe 26.3.1

## Quick start (macOS Sequoia / Sonoma)

End-to-end setup for any macOS user on Sonoma 14 or Sequoia 15 / Tahoe 26. No keychain actions, no paid developer account, no notarization.

### Path A — Install a pre-built bundle (easiest)

Use this if you received `JabraInputTracker.zip` and do not want to build from source.

```bash
# 1. Unzip
unzip JabraInputTracker.zip

# 2. Strip Gatekeeper quarantine (one-time, no admin password)
xattr -cr JabraInputTracker.app

# 3. (Optional) Move to /Applications
mv JabraInputTracker.app /Applications/

# 4. Sequoia 15 only: strip provenance so the app appears in TCC lists
sudo xattr -cr /Applications/JabraInputTracker.app

# 5. Launch
open /Applications/JabraInputTracker.app
```

On first launch, macOS prompts for:
- **Microphone** → Allow
- **Bluetooth** → Allow
- **Input Monitoring** → Open *System Settings* → toggle **JabraInputTracker** on

> Sequoia / Sonoma path: *System Settings → Privacy & Security → Input Monitoring*.
> If the toggle is missing, click the `+` and add the `.app` manually.

Done. The menu-bar mic icon appears. Permissions persist for this exact binary.

### Path B — Build from source

Use this if you want the latest code or are on a Mac without a pre-built bundle.

```bash
# 1. Install Xcode Command Line Tools (one-time, ~200 MB)
xcode-select --install

# 2. Clone
git clone https://github.com/Salobaka/jabra-mic-level-blocker.git jabra-input-tracker
cd jabra-input-tracker

# 3. Build (compiles + ad-hoc signs + auto-strips Sequoia provenance with sudo)
./build.sh

# 4. Launch
open .build/JabraInputTracker.app
```

`build.sh` automatically runs `sudo xattr -cr` to strip the Sequoia provenance attribute, which is required for TCC permission modals to appear. Enter your password when prompted during build.

On first launch, grant Microphone, Bluetooth, and Input Monitoring as in Path A.

> **After each `./build.sh`, ALL THREE permissions must be re-granted** because the ad-hoc signature changes (new cdhash). Click **Grant** on Microphone and Bluetooth in the HUD popover, and **Open Settings** for Input Monitoring.

### Path C — Build and install to /Applications

```bash
xcode-select --install
git clone https://github.com/Salobaka/jabra-mic-level-blocker.git jabra-input-tracker
cd jabra-input-tracker
./build.sh
./install.sh
open /Applications/JabraInputTracker.app
```

`install.sh` copies the bundle to `/Applications`, strips quarantine, re-signs, and launches. On Sequoia 15, run `sudo xattr -cr /Applications/JabraInputTracker.app` after install.

## Permissions (macOS Sequoia / Sonoma)

All three permissions are granted once per Mac. Path:

*System Settings → Privacy & Security*

- **Microphone** → *Microphone* → toggle **JabraInputTracker** on. **Resets after every rebuild** (ad-hoc signature changes).
- **Bluetooth** → *Bluetooth* → toggle **JabraInputTracker** on. **Resets after every rebuild** (ad-hoc signature changes).
- **Input Monitoring** → *Input Monitoring* → toggle **JabraInputTracker** on. **Resets after every rebuild** (ad-hoc signature changes).

> **Important:** the Daisy One mute button requires **Input Monitoring**, not Accessibility. Accessibility is not used by this app. If you granted Accessibility by mistake, it has no effect — grant Input Monitoring instead.

> **All three permissions reset after every `./build.sh`** because the app is ad-hoc signed (no keychain, no paid cert). The cdhash changes on each build, invalidating previous grants. This is a macOS security requirement, not a bug.

If a toggle is missing from the list, click `+` and add the `.app` manually.

For pre-built bundles (Path A), all three permissions persist forever for that exact binary.

### Sequoia 15: app not in TCC permission lists

On Sequoia 15, ad-hoc signed apps are tagged with `com.apple.provenance` on first launch, which blocks TCC registration. The app then never appears in Microphone, Bluetooth, or Input Monitoring lists. Fix:

```bash
sudo xattr -cr /Applications/JabraInputTracker.app
open /Applications/JabraInputTracker.app
```

- `xattr -cr` removes the provenance tag (needs `sudo` on Sequoia — it's system-managed).
- `spctl --add` is **no longer supported** on Sequoia 15.7+; stripping provenance is the only required step.
- After this, the app appears in all three TCC lists and you can grant permissions normally.

Run this once per Mac after install, and again after each rebuild (Path B).

## Manual

### First launch

1. Build or install the app (see [Install a pre-built bundle](#install-a-pre-built-bundle) or [Build from source](#build-from-source)).
2. `open JabraInputTracker.app`.
3. macOS prompts for **Microphone**, **Bluetooth**, and **Input Monitoring**. Grant all three.
   - If you skip Input Monitoring, the Daisy One mute button will not work. Re-grant later in *System Settings → Privacy & Security → Input Monitoring*.
4. A microphone icon appears in the menu bar. No Dock icon is shown (the app is a menu-bar agent).

### Menu bar

- Click the mic icon to open the popover HUD.
- The icon breathes orange while **Lock input level** is on; it is plain white when off.

### Jabra Elite 85h controls

- **Show mic level**: toggles the live input level meter. The default input device is temporarily switched to the Jabra while metering is on.
- **Lock input level**: re-applies your chosen gain 4× per second so Teams, Zoom, Meet, and Kumospace cannot pull it down.
- **Gain slider**: sets the input gain from 10% to 100%. The 10% floor is always enforced.
- **Connect / Disconnect Jabra Elite 85h**: pair or unpair over Bluetooth without opening System Settings.

### Daisy One controls

The Daisy section appears in the HUD when a paired Daisy One is detected.

- **Play/Pause button on the headset** toggles mute. An audible feedback sound confirms each toggle.
- **Mute / Unmute button** in the HUD does the same thing on screen, for testing or when the headset is off-ear.
- If the button does not work, Input Monitoring permission is missing or was reset after a rebuild. See [Permissions](#permissions).

### Closing the HUD

- The `×` button on the HUD **hides** the window. It does **not** quit the app.
- To quit: click the menu-bar icon → popover → menu bar `Jabra Input Tracker` → **Quit Jabra Input Tracker** (or `⌘Q` when the popover is key).
- The app keeps running in the background after the HUD is closed.

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| App says "Jabra not found" | Pair the Jabra Elite 85h in Bluetooth Settings and ensure it appears as an audio input device. |
| Gain slider has no effect | The headset is controlling gain internally. Nothing to do; the 10% floor is still enforced where the OS allows it. |
| Daisy mute button does nothing | Grant **Input Monitoring** (not Accessibility): *System Settings → Privacy & Security → Input Monitoring → JabraInputTracker*. Then click the app icon in the menu bar to reactivate the tap. |
| App not in TCC permission list (Sequoia 15) | Run `sudo xattr -cr <bundle>`, then relaunch. See [Sequoia 15: app not in TCC permission lists](#sequoia-15-app-not-in-tcc-permission-lists). |
| App is "damaged" on another Mac | Run `xattr -cr JabraInputTracker.app` to strip Gatekeeper quarantine. No keychain or notarization needed. |
| Permissions reset after every rebuild | Expected: the app is ad-hoc signed, so each rebuild changes the signature. Re-grant Input Monitoring. Microphone and Bluetooth persist. On Sequoia 15, also re-run `sudo xattr -cr`. |
| No menu-bar icon | The app crashed or was killed. Relaunch from Terminal to see stderr: `open .build/JabraInputTracker.app`. Check `~/Library/Logs/JabraInputTracker/app.log`. |

### Logs

Application log: `~/Library/Logs/JabraInputTracker/app.log`.

To watch live:
```bash
tail -f ~/Library/Logs/JabraInputTracker/app.log
```

### Uninstall

```bash
# Quit the app
pkill -x JabraInputTracker

# Remove from /Applications (if installed there)
rm -rf /Applications/JabraInputTracker.app

# Remove saved state and logs (optional)
rm -rf ~/Library/Logs/JabraInputTracker
defaults delete com.salobaka.jabrainputtracker 2>/dev/null || true
```

TCC permissions (Microphone, Bluetooth, Input Monitoring) can be revoked in *System Settings → Privacy & Security*.

## How it works

- Enumerates CoreAudio input devices and looks for a device whose name contains **"Jabra"** and **"85h"** or **"Elite"**.
- When metering is enabled, it temporarily switches the default input device to the Jabra headset and reads the audio stream via `AVAudioEngine`.
- Writes the device's input-gain scalar using CoreAudio and clears the hardware mute flag.
- A background timer re-applies the selected gain every 250 ms when **Lock input level** is on.
- Even with **Lock input level** off, the app still enforces the 10% floor.
- For Daisy One, a `CGEventTap` intercepts `NX_KEYTYPE_PLAY` (the headset's Play/Pause button) and toggles mute with an audible feedback sound.

## Notes

- The app does **not** disable AGC inside the Jabra firmware itself; it only keeps the OS-side input gain above the threshold that triggers the headset's auto-mute behavior.
- Some Bluetooth headsets do not expose a software gain scalar. If the fader has no effect, the headset may be controlling gain internally.
- The binary is compiled with `-O -whole-module-optimization` and has no third-party dependencies.
- The app runs as a menu-bar agent (`LSUIElement = true`) — no Dock icon.