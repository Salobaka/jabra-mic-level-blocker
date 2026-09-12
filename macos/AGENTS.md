# AGENTS.md — macOS app

Swift menu-bar agent (`LSUIElement`, no Dock icon). Pure `swiftc` build — no Xcode project, no third-party dependencies.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/` | All app code (AppKit + SwiftUI HUD + CoreAudio) |
| `Sources/main.swift` | Entry point |
| `Sources/AudioDeviceManager.swift` | Core gain enforcement engine (singleton `shared`) |
| `Sources/AudioDeviceDiscovery.swift` | CoreAudio device enumeration/matching |
| `Sources/HUDView.swift` | Popover UI (SwiftUI) |
| `Sources/MenuBarManager.swift` | Status-item, menu, popover wiring |
| `Sources/AppLogger.swift` | Rotating log → `~/Library/Logs/JabraInputTracker/app.log` |
| `Sources/LoginItemManager.swift` | Launch-at-login via SMAppService (macOS 13+); ON by default, UserDefaults opt-out |
| `build.sh` | Compile + generate icon + ad-hoc sign → `.build/JabraInputTracker.app` |
| `install.sh` | Copy bundle to `/Applications`, strip quarantine, re-sign, launch |
| `rebuild.sh` | build + install + relaunch |
| `notarize.sh` + `release.entitlements` + `notarize.env.example` | Developer ID sign + notarize + staple + zip (release flow) |
| `tools/generate_icon.swift` | Pixel-art mic icon generator (called by build.sh) |

## Build / verify

```bash
./build.sh                                # compile + icon + ad-hoc sign
open .build/JabraInputTracker.app         # run
tail -f ~/Library/Logs/JabraInputTracker/app.log
```

- SwiftLint config: `.swiftlint.yml` (run `swiftlint` if installed).
- Bundle id: `jabra-mic-level-handler` (see `Info.plist`).

## Conventions & gotchas

- **Ad-hoc signing**: every `./build.sh` changes the cdhash → Bluetooth TCC grant is invalidated; user must remove (`-`) and re-add (`+`) the app in System Settings. Pre-built zips keep grants for that exact binary.
- **Sequoia 15.7**: `com.apple.provenance` suppresses TCC modals — permissions are granted manually via `+` in System Settings (HUD has an **Open Settings** button).
- **No microphone permission needed** — gain control is CoreAudio property writes. Only Bluetooth permission (connect/disconnect buttons) is TCC-gated.
- HUD design follows Apple HIG; keep the popover compact, standard controls only.
- Log file is 1 MB-rotating; icon assets cached (do not regenerate per frame — CPU cost).
- Behavior contract shared with Windows: see `../common/spec.md`.
