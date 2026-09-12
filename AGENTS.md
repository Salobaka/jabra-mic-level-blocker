# AGENTS.md — repo guide for AI agents

Two native apps sharing one behavioral contract. **Zero shared code** (Swift vs Rust) — what is shared is the *behavior*, documented in `common/spec.md`.

## Repository map

| Path | Platform | What it is |
| --- | --- | --- |
| `macos/` | macOS 12+ | Swift menu-bar agent (`JabraInputTracker.app`), no third-party deps |
| `windows/` | Windows 10/11 x64 | Rust system-tray app (`JabraInputTracker.exe`), `native-windows-gui` + `windows-rs` |
| `common/spec.md` | both | Behavioral contract: gain floor, tick, backoff, device detection, defaults |
| `.github/workflows/` | CI | `windows.yml` (build + smoke + release). No macOS CI yet. |

## Routing rules (read before touching anything)

1. **Platform mentioned in the request?** Work only inside that platform's directory and read its `AGENTS.md` first (`macos/AGENTS.md` / `windows/AGENTS.md`).
2. **No platform mentioned?** Check `common/spec.md` — if the change touches behavior listed there, it is a **parity change**: apply it to the requested platform, note the gap in the other platform's README/AGENTS.md, and tell the user.
3. **Never** put platform-specific files at the repo root or in the other platform's directory. Tools/scripts live in `<platform>/tools/`.
4. Root-level files are limited to: this file, `README.md`, `.gitignore`, `common/`, `.github/`.

## Git / GitHub (repo: `Salobaka/jabra-mic-level-blocker`, public)

- Commit to `main`; tag releases `v<major.minor.patch>` (Windows flow in `windows/AGENTS.md`).
- **Push procedure** (the `$GITHUB_TOKEN` env var holds a fine-grained PAT that cannot push cross-account — always unset it and use the `gh` keyring token):
  ```bash
  unset GITHUB_TOKEN
  TOK=$(gh auth token)
  git -c credential.helper= push "https://x-access-token:${TOK}@github.com/Salobaka/jabra-mic-level-blocker.git" HEAD:main
  git -c credential.helper= push "https://x-access-token:${TOK}@github.com/Salobaka/jabra-mic-level-blocker.git" vX.Y.Z   # tags
  ```
- Never echo or log the token value.
- `gh` API is rate-limited (5000/hr shared); if `gh run list`/`gh release` 403s, check `gh api /rate_limit --jq '.resources.core'` and wait for reset.
- Do not commit secrets; `notarize.env` is gitignored.

## Build verification (always run before committing)

- macOS: `cd macos && ./build.sh` (must compile + sign; launch `.build/JabraInputTracker.app` when behavior changed).
- Windows: `cd windows && cargo fmt && cargo check --target x86_64-pc-windows-msvc && cargo clippy --release --target x86_64-pc-windows-msvc -- -D warnings` — all must be clean; CI enforces them.

## Environment gotchas (this machine)

- Rust toolchain: `export PATH="$HOME/.cargo/bin:$PATH"` first (installed with `--no-modify-path`).
- Prefer the Grep tool over bash `grep` (the local grep wrapper mangles `\|` alternation).
