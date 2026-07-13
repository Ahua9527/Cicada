Sentry vendor notice

- Source: https://github.com/Ahua9527/Sentry
- Baseline commit: 7961a0365f39d1e72ba4e587c79f6ef147fd613e
- License: MIT, preserved in ../../LICENSE
- Local source mapping:
  - Upstream `Sentry/` is integrated into `../../Sentry/` and compiled directly by the Xcode filesystem-synchronized `Sentry` group.
  - Upstream project metadata is represented by `../../Sentry.xcodeproj`, with Cicada bundle, signing, test, and package changes.
  - `ThirdParty/Sentry/` contains provenance only; the production source is not an SPM dependency and is not stored in this directory.
- Imported surface:
  - Sentry macOS app source, resources, project files, README, LICENSE, and .gitignore.
  - Upstream Sentry localization keys are preserved exactly; Cicada adds extra keys for the integrated NotchDrop surface.
- Local integration:
  - Changed bundle identity/signing metadata to the Cicada Sentinel app.
  - Added Sentinel menu bar lifecycle, daemon/CLI IPC, notifier Unix socket server, and NotchDrop notification/tray integration.
  - Replaced the upstream external SleepHold HTTP client path with Cicada daemon power assertion IPC.
  - Added local regression tests and small testability/stability seams around startup diagnostics, runtime state, recording, and notification handling.

The entries above are the maintained local-change inventory. Generate an exact source diff before an update with:

```bash
pnpm run vendor:audit
bash apps/agent/scripts/audit-vendored.sh --diff sentry > /tmp/cicada-sentry-vendor.diff
```

Review and selectively port upstream commits into the integrated source. Do not replace this integration with an SPM dependency or overwrite Cicada-specific files wholesale.
