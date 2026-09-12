# Jabra Mic Level Blocker

A tiny native app that prevents a **Jabra Elite 85h** headset from muting itself during calls.

## The problem

Our team uses six Jabra Elite 85h headsets. They have an annoying built-in "feature" that disables the microphone on very loud input noise. In practice it triggers false positives almost every day — especially in coworking spaces — and mutes someone in the middle of an emotional speech or an important call.

## What it does

Keeps the Jabra input gain at a safe minimum level and actively prevents the OS or meeting apps (Teams, Zoom, Meet, Kumospace) from pulling it down to zero — so the headset never gets a chance to think it should auto-mute.

## Platforms

This is a monorepo with two independent native apps sharing one behavioral contract:

| Directory | Platform | Docs |
| --- | --- | --- |
| [`macos/`](macos/) | macOS 12+ menu-bar app (Swift) | [macos/README.md](macos/README.md) |
| [`windows/`](windows/) | Windows 10/11 x64 tray app (Rust) | [windows/README.md](windows/README.md) |
| [`common/spec.md`](common/spec.md) | Behavioral contract both apps follow | — |

## Download

- **Windows**: grab `JabraInputTracker-<version>-windows-x64.zip` from [Releases](https://github.com/Salobaka/jabra-mic-level-blocker/releases). Unsigned — SmartScreen: **More info → Run anyway**.
- **macOS**: build from source, see [macos/README.md](macos/README.md).

## For AI agents / contributors

> **STOP — read [AGENTS.md](AGENTS.md) before changing anything.** It defines which directory you are allowed to edit:
>
> - **macOS task** → work only in [`macos/`](macos/) (Swift). Never touch `windows/`.
> - **Windows task** → work only in [`windows/`](windows/) (Rust). Never touch `macos/`.
> - **Shared behavior** → [`common/spec.md`](common/spec.md); a change there is a parity change for both apps.
>
> Each platform directory has its own `AGENTS.md` and `README.md` with backlinks — follow them. Writing Swift for a Windows request (or Rust for a macOS request) means you are in the wrong codebase: stop and re-read the routing rules.
