# Jabra Input Tracker

A tiny native macOS app with a Dock icon that shows a floating mic level meter and input-level fader for the **Jabra Elite 85h** Bluetooth headset.

## Features
- Menu-bar icon (🎙) with a dropdown popover containing all controls.
- Floating HUD with live mic level meter (Jabra Elite 85h only).
- Fader to set the Jabra input gain from 0–100%.
- **Lock input level** — re-applies the chosen gain 4× per second so apps like Kumospace/Teams/Zoom can’t pull the mic level down.
- Enable/disable meter toggle.
- Quit from the popover, the HUD, or the Dock menu.
- Restores your previous default input device when the meter is turned off or the app quits.

## Requirements
- macOS 12+
- Jabra Elite 85h paired and available as an audio input device.
- Microphone permission (macOS will prompt the first time you enable the meter).

## Build

```bash
./build.sh
```

This produces `.build/JabraInputTracker.app`.

## Run

```bash
open .build/JabraInputTracker.app
```

Or move it to `/Applications` first:

```bash
cp -R .build/JabraInputTracker.app /Applications/
open /Applications/JabraInputTracker.app
```

## How it works
- The app enumerates CoreAudio input devices and looks for a device whose name contains **“Jabra”** and **“85h”** or **“Elite”**.
- When you enable the meter, the app temporarily switches the default input device to the Jabra headset and reads the audio stream via `AVAudioEngine`.
- The fader writes the device’s input-gain scalar using CoreAudio.
- When the meter is disabled or the app quits, the previous default input device is restored.

## Project structure
```
Sources/
├── main.swift              # App entry point
├── AppDelegate.swift       # Menu, Dock lifecycle, controllers
├── AudioDeviceManager.swift# CoreAudio device discovery + gain control
├── LevelMeter.swift        # AVAudioEngine tap + RMS level calculation
├── FloatingPanel.swift     # Always-on-top NSPanel
├── MenuBarManager.swift    # Status-bar icon + popover
└── HUDView.swift           # SwiftUI toggle, meter, slider, quit
Info.plist                  # Bundle metadata + mic usage description
build.sh                    # One-step build script
```

## Notes
- The app does **not** disable AGC in other apps by itself; it only sets a fixed input gain for the Jabra device.
- Some Bluetooth headsets do not expose a software gain scalar. If the fader has no effect, the headset may be controlling gain internally.
- The binary is compiled with `-O -whole-module-optimization` and has no third-party dependencies.
