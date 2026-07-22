# Codex Pulse repository instructions

This is a standalone macOS menu-bar app, not a Codex plugin.

When a user explicitly asks Codex to install this repository:

1. Confirm the machine is running macOS 13 or later.
2. Read `README.md`, `SECURITY.md`, and `scripts/install.sh` before executing it.
3. Run `swift test`.
4. Run `./scripts/install.sh` from the repository root.
5. Verify that `~/Applications/Codex Pulse.app` exists and passes `codesign --verify --deep --strict`.
6. Report the installed path and whether the app launched.

Never request or copy a Codex token, API key, browser cookie, Keychain item, or auth file. Never use `sudo` for this project. The installer builds entirely from the checked-out source.
