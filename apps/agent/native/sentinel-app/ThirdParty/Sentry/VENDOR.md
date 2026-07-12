Sentry vendor notice

- Source: https://github.com/Ahua9527/Sentry
- Baseline commit: 7961a0365f39d1e72ba4e587c79f6ef147fd613e
- License: MIT, preserved in ../../LICENSE
- Imported surface:
  - Sentry macOS app source, resources, project files, README, LICENSE, and .gitignore.
  - Upstream Sentry localization keys are preserved exactly; Cicada adds extra keys for the integrated NotchDrop surface.
- Local integration:
  - Changed bundle identity/signing metadata to the Cicada Sentinel app.
  - Added Sentinel menu bar lifecycle, daemon/CLI IPC, notifier Unix socket server, and NotchDrop notification/tray integration.
  - Replaced the upstream external SleepHold HTTP client path with Cicada daemon power assertion IPC.
  - Added local regression tests and small testability/stability seams around startup diagnostics, runtime state, recording, and notification handling.
