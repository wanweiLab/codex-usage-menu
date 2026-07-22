# Contributing

Issues and pull requests are welcome.

## Local development

Requirements: macOS 13+, Swift 5.10+, and a locally installed, logged-in Codex or ChatGPT app.

```bash
swift test
swift run
```

Build the app bundle with:

```bash
./scripts/build-app.sh
```

The live integration test uses the current local Codex login and is disabled by default:

```bash
CODEX_USAGE_LIVE_TEST=1 swift test --filter testLiveClientReadsAccountThenRateLimits
```

Do not include credentials, logs containing personal account data, generated build products, or a bundled Codex executable in commits.
