# Changelog

All notable changes to this project will be documented here.

## 0.2.1 - 2026-07-23

- Fix the macOS app icon by generating every required icon size instead of a cropped single-size asset.

## 0.2.0 - 2026-07-22

- Rename the user-facing app from Codex Usage to Codex Pulse.
- Add the Codex Pulse macOS application icon and reproducible icon-generation script.
- Preserve the existing `CodeX｜周 xx%` menu-bar format.
- Remove the legacy `Codex Usage.app` bundle after a successful upgrade.

## 0.1.0 - 2026-07-22

- Show weekly remaining Codex usage in the macOS menu bar.
- Show weekly and short-window limits, reset time, plan, and masked account email.
- Refresh usage every five minutes and support manual refresh.
- Read usage through the local Codex App Server without handling login credentials.
- Add source-based install, update, and uninstall scripts.
