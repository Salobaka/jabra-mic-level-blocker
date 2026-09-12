# Behavioral contract — both platforms

The macOS (Swift) and Windows (Rust) apps share no code, but must behave the same. When you change any behavior listed here on one platform, treat it as a **parity change**: flag the other platform's gap in its `AGENTS.md`/README and tell the user.

## Device detection

- Enumerate active audio **capture** endpoints.
- Match the Jabra Elite 85h by name: contains **"Jabra"** and (**"85h"** or **"Elite"**), case-insensitive.
- Fallback (Windows): default capture endpoint if no name match (status `Active (fallback)`); macOS has no fallback.
- Re-scan on device add/remove/state change (CoreAudio listener / `IMMNotificationClient`).

## Gain enforcement

| Rule | Value |
| --- | --- |
| Tick | every **250 ms** (4×/second) |
| Minimum floor | **10 %** — always enforced, even unlocked; never allow mute-to-zero |
| Unmute | clear the mute flag on **every** gain write |
| Tolerance | **0.005** — skip write/verify when |current − target| is within it |
| Write verification | read back after write; **3 consecutive failures** → mark gain not writable (`NoGainControl` / "no gain control") and stop hammering |
| Rearm | moving the slider resets the failure counter and retries |

## Defaults (agreed cross-platform norm)

| Setting | Default |
| --- | --- |
| Target mic level at app start | **100 %** |
| Lock | **ON** (enforcement active from launch) |
| Launch at login | **ON by default**, opt-out checkbox in UI |

Current parity status:

- **Windows** (v1.2.1): target defaults to 100 % but lock starts **OFF** (floor only); "Start with Windows" checkbox starts **OFF** (opt-in).
- **macOS**: target 100 % at first discovery, lock ON, launch-at-login ON by default (SMAppService, HUD opt-out checkbox) — **fully aligned** with the norm.

## Platform-explicit differences (not parity gaps)

- Bluetooth connect/disconnect buttons: macOS only (Windows manages BT audio profiles natively).
- Permissions: macOS needs a Bluetooth TCC grant for the BT buttons; Windows needs none.
- UI surface: macOS menu-bar popover; Windows system-tray icon + control window.
- Logs: 1 MB rotation both platforms; `~/Library/Logs/JabraInputTracker/app.log` (macOS) / `%LOCALAPPDATA%\JabraInputTracker\app.log` (Windows).
- Single instance: enforced on Windows; macOS relies on LaunchServices single-instance behavior for .app bundles.
