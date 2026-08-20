# Changelog

All notable changes to this project will be documented here.

## 0.4.8 - 2026-08-20

- Keep reset countdown text updating as time passes instead of freezing at the last rendered minute.
- Recreate the countdown immediately when a refreshed quota snapshot returns a different absolute `resetsAt` value.

## 0.4.7 - 2026-08-20

- Update the weekly and short-window reset countdown together with each refreshed quota snapshot.
- Keep the countdown aligned with the absolute `resetsAt` value returned by Codex.

## 0.4.6 - 2026-08-10

- Fix an AppKit constraint-update loop that could crash the app when leaving settings.
- Keep the menu window at a stable size while switching between usage and settings.
- Remove the default Return-key action from the settings completion button.

## 0.4.5 - 2026-08-07

- Replace the fully transparent reminder overlay with an ultra-thin frosted glass surface.
- Restore a subtle border and window shadow while keeping the popup translucent.
- Remove reminder preview buttons from settings for the release build.

## 0.4.3 - 2026-08-07

- Remove the bottom close button from reminder popups.
- Make reminder popup windows fully transparent without card borders or shadows.
- Recenter reminder content in the transparent square overlay.

## 0.4.2 - 2026-08-07

- Redesign reminder popups as centered square cards.
- Replace the horizontal progress bar with a prominent circular 60-second countdown.

## 0.4.1 - 2026-08-07

- Fix the settings panel overflowing into its footer on shorter displays.
- Keep settings actions in a fixed footer while the settings content scrolls independently.
- Align reminder controls and simplify each reminder row for a cleaner compact layout.

## 0.4.0 - 2026-08-07

- Add independently configurable sedentary and hydration reminders with 1–720 minute intervals.
- Show large, topmost reminder popups in the center of the current screen with a 60-second countdown and manual close controls.
- Add immediate reminder previews from settings and persist reminder configuration locally.

## 0.3.3 - 2026-07-23

- Use the Codex Pulse app logo in the menu header instead of the generic code symbol.

## 0.3.2 - 2026-07-23

- Enforce the eight-character menu-bar prefix limit directly in the text field.

## 0.3.1 - 2026-07-23

- Add a locally persisted menu-bar prefix setting with live preview, blank mode, and reset to default.

## 0.3.0 - 2026-07-23

- Keep one serialized Codex App Server connection alive and reconnect once after transport failures.
- Coalesce overlapping manual and scheduled refreshes.
- Preserve the last successful usage snapshot and show a stale-data warning after refresh failures.
- Add copyable, credential-free diagnostics for troubleshooting.
- Move protocol samples into fixture files and test current, legacy, error, and malformed responses.
- Run CI on both macOS 14 and macOS 15.

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
