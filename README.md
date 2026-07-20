# Jabra Mic Level Blocker

A tiny native macOS app that prevents a **Jabra Elite 85h** headset from muting itself during calls.

## The problem

Our team uses six Jabra Elite 85h headsets. They have an annoying built-in "feature" that disables the microphone on very loud input noise. In practice it triggers false positives almost every day — especially in coworking spaces — and mutes me in the middle of an emotional speech or an important call.

## What this app does

This menu-bar tool keeps the Jabra input gain at a safe minimum level and actively prevents the OS or meeting apps from pulling it down to zero. That way the headset never gets a chance to think it should auto-mute.

## Features

- Menu-bar icon with a popover containing all controls
- Input gain fader from **10% to 100%** — set the mic level in percent, not arbitrary units
- **10% minimum gain is always enforced** — you can never be accidentally muted to zero
- **Unmute on every gain write** — clears the hardware/OS mute flag
- **Lock input level** — re-applies the chosen gain 4× per second so apps like MS Teams, Kumospace, Zoom and Google Meet cannot pull the mic level down
- **No microphone permission required** — gain control uses CoreAudio property writes only

## Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Jabra Elite 85h paired and available as an audio input device
- Bluetooth permission (see [Permissions](#permissions-macos-sequoia--sonoma))

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

# 4. Launch
open /Applications/JabraInputTracker.app
```

On first launch, the app appears in the menu bar. Jabra gain control works immediately — no permission needed. Open the popover and grant Bluetooth permission for the optional connect/disconnect feature (see [Permissions](#permissions-macos-sequoia--sonoma)):

1. Click **Open Settings** in the HUD → System Settings opens to the pane
2. Click `+` → select `JabraInputTracker.app` → toggle on
3. Click back to the app → the badge flips green

For pre-built bundles, permissions persist forever for that exact binary.

### Path B — Build from source

Use this if you want the latest code or are on a Mac without a pre-built bundle.

```bash
# 1. Install Xcode Command Line Tools (one-time, ~200 MB)
xcode-select --install

# 2. Clone
git clone https://github.com/Salobaka/jabra-mic-level-blocker.git jabra-input-tracker
cd jabra-input-tracker

# 3. Build (compiles + generates pixel-art mic icon + ad-hoc signs)
./build.sh

# 4. Launch
open .build/JabraInputTracker.app
```

Then grant Bluetooth permission as in Path A (click **Open Settings**, add via `+`).

> **After each `./build.sh`, the Bluetooth permission must be re-granted** because the ad-hoc signature changes (new cdhash). The previous TCC entry is stale — remove it with `-` and re-add with `+`.

### Path C — Build and install to /Applications

```bash
xcode-select --install
git clone https://github.com/Salobaka/jabra-mic-level-blocker.git jabra-input-tracker
cd jabra-input-tracker
./build.sh
./install.sh
open /Applications/JabraInputTracker.app
```

`install.sh` copies the bundle to `/Applications`, strips quarantine, re-signs, and launches. Then grant Bluetooth permission as in Path A.

## Releasing a signed + notarized build (GitHub distribution)

For a build that **anyone can download from GitHub and run without disabling Gatekeeper**, you must sign with a **Developer ID Application** certificate and notarize it with Apple. This replaces the ad-hoc signing that `build.sh` does.

### One-time setup

1. **Create a Developer ID Application certificate** at <https://developer.apple.com/account/resources/certificates/list>:
   - In Keychain Access: *Certificate Assistant → Request a Certificate from a Certificate Authority* → save the CSR to disk.
   - On the website: **+** → **Developer ID Application** → upload the CSR → download the `.cer` → double-click to install in Keychain.
2. **Generate an app-specific password** at <https://appleid.apple.com> (Sign in → App-Specific Passwords → label it `notarytool`).
3. **Note your Team ID** at <https://developer.apple.com/account> → Membership Details (10-char string).
4. Copy `notarize.env.example` → `notarize.env` and fill in:
   ```bash
   export APPLE_ID="you@example.com"
   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
   export TEAM_ID="XXXXXXXXXX"
   export SIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)"
   ```
   `notarize.env` is gitignored — never commit the filled-in copy.

### Publishing a release

```bash
# 1. Build the app (ad-hoc signed is fine — notarize.sh re-signs)
./build.sh

# 2. Load secrets
source notarize.env

# 3. Sign + notarize + staple + zip (5-30 min)
./notarize.sh                 # version pulled from Info.plist
# or: ./notarize.sh 1.0.0     # explicit version

# 4. Publish to GitHub (command printed by notarize.sh, NOT auto-run)
gh release create v1.0.0 "release/JabraInputTracker-1.0.0-macos.zip" \
  --title "v1.0.0" \
  --generate-notes
```

`notarize.sh` signs with your Developer ID identity, applies `release.entitlements` (hardened runtime + Bluetooth + audio-input), submits to Apple's notarization service, staples the ticket, verifies Gatekeeper acceptance, and zips the final bundle. The output is `release/JabraInputTracker-<version>-macos.zip`.

### Why this matters

The ad-hoc build from `./build.sh` only runs on Macs that either disable Gatekeeper or `xattr -cr` the bundle. A Developer ID + notarized build opens silently on any macOS 10.15+ Mac with Gatekeeper on, which is what GitHub Releases need.

## Permissions (macOS Sequoia / Sonoma)

One permission is used. On Sequoia 15.7, `com.apple.provenance` is system-enforced and **cannot be removed** (not even with `sudo xattr -cr`). TCC modals will not appear automatically. You must manually add the app to the TCC list.

*System Settings → Privacy & Security*

1. Open the HUD popover (click the menu-bar mic icon)
2. Click **Open Settings** next to the permission → System Settings opens to the pane
3. Click `+` → select `JabraInputTracker.app` → toggle on
4. Click back to the app (or click the ↻ refresh button) → the badge flips green

- **Bluetooth** → required for Jabra detection and connect/disconnect

**Microphone permission is NOT required.** Jabra gain control (slider, lock, 10% floor) uses CoreAudio property writes only, which need no TCC permission.

> **The permission resets after every `./build.sh`** because the app is ad-hoc signed (no keychain, no paid cert). The cdhash changes on each build, invalidating previous grants. Remove old entries with `-` and re-add with `+`. This is a macOS security requirement, not a bug.

For pre-built bundles (Path A), the permission persists forever for that exact binary.

### Why TCC modals don't appear (Sequoia 15.7)

On Sequoia 15.7, the kernel attaches `com.apple.provenance` to every file and it cannot be removed — `xattr -cr` reports success but the attribute immediately reappears. When this attribute is present on an ad-hoc signed app, TCC silently refuses to show permission modals and apps never register in the TCC list. The only workaround without a paid Developer ID or a self-signed keychain cert is manual `+` addition in System Settings.

## Manual

### First launch

1. Build or install the app (see [Install a pre-built bundle](#install-a-pre-built-bundle) or [Build from source](#build-from-source)).
2. `open JabraInputTracker.app`.
3. Jabra gain control works immediately — no permission needed.
4. Grant **Bluetooth** via the HUD for the optional connect/disconnect feature (see [Permissions](#permissions-macos-sequoia--sonoma)).
5. A microphone icon appears in the menu bar. No Dock icon is shown (the app is a menu-bar agent).

### Menu bar

- Click the mic icon to open the popover HUD.
- The icon breathes orange while **Lock input level** is on; it is plain white when off.

### Jabra Elite 85h controls

- **Lock input level**: re-applies your chosen gain 4× per second so Teams, Zoom, Meet, and Kumospace cannot pull it down.
- **Gain slider**: sets the input gain from 10% to 100%. The 10% floor is always enforced.
- **Connect / Disconnect Jabra Elite 85h**: pair or unpair over Bluetooth without opening System Settings.

### Daisy One controls

The Daisy One feature has been removed from this build. The app now supports only the Jabra Elite 85h.

### Closing the HUD

- The `×` button on the HUD **hides** the window. It does **not** quit the app.
- To quit: click the menu-bar icon → popover → menu bar `Jabra Input Tracker` → **Quit Jabra Input Tracker** (or `⌘Q` when the popover is key).
- The app keeps running in the background after the HUD is closed.

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| App says "Jabra not found" | Pair the Jabra Elite 85h in Bluetooth Settings and ensure it appears as an audio input device. |
| Gain slider has no effect | The headset is controlling gain internally. Nothing to do; the 10% floor is still enforced where the OS allows it. |
| Permission badge stays yellow/red | On Sequoia 15.7, TCC modals don't appear. Click **Open Settings** in the HUD → add the app via `+` → click back to the app. See [Permissions](#permissions-macos-sequoia--sonoma). |
| App is "damaged" on another Mac | Run `xattr -cr JabraInputTracker.app` to strip Gatekeeper quarantine. No keychain or notarization needed. |
| Permissions reset after every rebuild | Expected: the app is ad-hoc signed, so each rebuild changes the cdhash. Remove old TCC entries with `-` and re-add with `+`. |
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

TCC permissions (Bluetooth) can be revoked in *System Settings → Privacy & Security*.

## How it works

- Enumerates CoreAudio input devices and looks for a device whose name contains **"Jabra"** and **"85h"** or **"Elite"**.
- Writes the device's input-gain scalar using CoreAudio and clears the hardware mute flag.
- A background timer re-applies the selected gain every 250 ms when **Lock input level** is on.
- Even with **Lock input level** off, the app still enforces the 10% floor.

## Notes

- The app does **not** disable AGC inside the Jabra firmware itself; it only keeps the OS-side input gain above the threshold that triggers the headset's auto-mute behavior.
- Some Bluetooth headsets do not expose a software gain scalar. If the fader has no effect, the headset may be controlling gain internally.
- The binary is compiled with `-O -whole-module-optimization` and has no third-party dependencies.
- The app runs as a menu-bar agent (`LSUIElement = true`) — no Dock icon.