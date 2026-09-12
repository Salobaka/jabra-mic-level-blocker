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

### Wrong-codebase guard — STOP check

Before writing any file, verify the file path against the request:

- macOS request → paths must start with `macos/` (Swift). If you are about to write Rust (`windows/`), you are in the **wrong codebase** — stop and re-read the request.
- Windows request → paths must start with `windows/` (Rust). If you are about to write Swift (`macos/`), you are in the **wrong codebase** — stop and re-read the request.
- Docs/CI/spec requests → only `README.md`, `AGENTS.md`, `common/`, `.github/` at root, plus the matching platform docs.
- A parity change is the **only** reason to touch the other platform, and even then you only add a gap note to its `AGENTS.md`/README — never its code, unless the user explicitly asked for both platforms.

### Backlink convention

Every directory doc links back here so an agent landing anywhere gets routed correctly:

- `macos/README.md`, `macos/AGENTS.md` → link to this file, `../windows/`, `../common/spec.md`.
- `windows/README.md`, `windows/AGENTS.md` → link to this file, `../macos/`, `../common/spec.md`.
- `common/spec.md` → links to this file.

Keep these backlinks in place when editing docs.

## Git / GitHub (repo: `Salobaka/jabra-mic-level-blocker`, public)

- Commit to `main`; tag releases `v<major.minor.patch>` (Windows flow in `windows/AGENTS.md`).
- **Release titles are platform-marked**: `Windows vX.Y.Z` (set by `windows.yml`) and `macOS X.Y` (old manual releases). Tags: `v*` = Windows, bare `1.0/1.1/1.2` = legacy macOS builds. If macOS ever gets CI releases, mark them `macOS vX.Y.Z` in the title.
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
