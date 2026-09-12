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

Read [AGENTS.md](AGENTS.md) first — it explains the repo layout, the platform routing rules, and the release procedures.
