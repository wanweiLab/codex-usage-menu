# Security

## Data flow

Codex Usage starts the locally installed Codex executable with `codex app-server --stdio` and calls only:

- `account/read`, once when the app starts
- `account/rateLimits/read`, at startup, every five minutes, and on manual refresh

The Codex child process uses its existing login. This app does not read, copy, transmit, or save tokens, API keys, browser cookies, Keychain items, or Codex authentication files. Account email is masked before display. No analytics or telemetry is included.

The installer builds from the checked-out Swift source, ad-hoc signs the local app bundle, installs it in `~/Applications`, and does not use `sudo`.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting feature on this repository. Include affected versions, reproduction steps, and expected impact.

## Compatibility notice

The local Codex App Server interface may evolve. Install updates only from this repository and review source changes before running scripts.
