# Installation details

## Ask Codex to install it

Paste this single line into Codex:

```text
请安装这个工具：https://github.com/wanweiLab/codex-usage-menu
```

Codex should clone the repository into a temporary directory, inspect the source and installer, run the tests, execute `./scripts/install.sh`, verify the code signature, and report the result.

## Install manually

```bash
git clone https://github.com/wanweiLab/codex-usage-menu.git
cd codex-usage-menu
swift test
./scripts/install.sh
```

The default destination is `~/Applications/Codex Pulse.app`. To update, pull the latest source and run `./scripts/install.sh` again. The installer removes the legacy `Codex Usage.app` bundle after a successful upgrade.

## Uninstall

```bash
./scripts/uninstall.sh
```

## Installer controls

- `INSTALL_DIR=/some/folder ./scripts/install.sh` changes the install directory.
- `NO_LAUNCH=1 ./scripts/install.sh` installs without launching.
- `CODEX_CLI_PATH=/absolute/path/to/codex ./scripts/install.sh` selects a custom Codex executable.

The installer never uses `sudo` and never downloads a prebuilt executable.
