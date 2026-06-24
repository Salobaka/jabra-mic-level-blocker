# Jabra Mic Level Blocker

A tiny native macOS app that prevents a **Jabra Elite 85h** headset from muting itself during calls.

## The problem

Our team uses six Jabra Elite 85h headsets. They have an annoying built-in "feature" that disables the microphone on very loud input noise. In practice it triggers false positives almost every day — especially in coworking spaces — and mutes me in the middle of an emotional speech or an important call.

## What this app does

This menu-bar tool keeps the Jabra input gain at a safe minimum level and actively prevents the OS or meeting apps from pulling it down to zero. That way the headset never gets a chance to think it should auto-mute.

## Features

- Menu-bar icon with a popover containing all controls
- Floating HUD with live mic level meter (Jabra Elite 85h)
- Input gain fader from **10% to 100%**
- **10% minimum gain is always enforced** — you can never be accidentally muted to zero
- **Unmute on every gain write** — clears the hardware/OS mute flag
- **Lock input level** — re-applies the chosen gain 4× per second so apps like MS Teams, Kumospace, Zoom and Google Meet cannot pull the mic level down
- Restores the previous default input device when the meter is turned off or the app quits
- Explicit microphone permission handling for macOS

## Requirements

- macOS 12+
- Jabra Elite 85h paired and available as an audio input device
- Microphone permission (the app prompts on first launch)

## Tested on

- Apple Silicon M3 Max / M3 Ultra / M4
- macOS Sequoia
- macOS Tahoe 26.3.1

## Build

```bash
./build.sh
```

This produces `.build/JabraInputTracker.app`.

## Run

```bash
open .build/JabraInputTracker.app
```

Or move it to `/Applications`:

```bash
cp -R .build/JabraInputTracker.app /Applications/
open /Applications/JabraInputTracker.app
```

## How it works

- Enumerates CoreAudio input devices and looks for a device whose name contains **"Jabra"** and **"85h"** or **"Elite"**.
- When metering is enabled, it temporarily switches the default input device to the Jabra headset and reads the audio stream via `AVAudioEngine`.
- Writes the device's input-gain scalar using CoreAudio and clears the hardware mute flag.
- A background timer re-applies the selected gain every 250 ms when **Lock input level** is on.
- Even with **Lock input level** off, the app still enforces the 10% floor.

## Notes

- The app does **not** disable AGC inside the Jabra firmware itself; it only keeps the OS-side input gain above the threshold that triggers the headset's auto-mute behavior.
- Some Bluetooth headsets do not expose a software gain scalar. If the fader has no effect, the headset may be controlling gain internally.
- The binary is compiled with `-O -whole-module-optimization` and has no third-party dependencies.
