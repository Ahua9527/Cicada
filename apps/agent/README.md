# CicadaAgent

Native macOS agent components for Cicada. The SwiftPM package under `swift/`
builds the CLI, daemon, and shared IPC/system modules. Notification rendering is
served by the Sentinel app over the existing Unix socket contract.

## Sentinel App

The vendored Sentinel UI lives in `native/sentinel-app` and is built from the
Sentry macOS project. Agent scripts include it in local validation:

The Sentry source baseline is `Ahua9527/Sentry` at
`7961a0365f39d1e72ba4e587c79f6ef147fd613e`; local Cicada adaptations are
recorded in `native/sentinel-app/ThirdParty/Sentry/VENDOR.md`.

```bash
pnpm run lint:agent
pnpm run test:agent
```

`scripts/build.sh` installs the app to `~/.cicada/apps/Sentry.app`. Runtime
control is exposed through the daemon/CLI commands `sentry_start`,
`sentry_stop`, `sentry_status`, `sentry_unlock`, and `sentry_open`. The app also
hosts the notifier socket at `~/.cicada/run/notifier.sock` and stores NotchDrop
tray files under `~/.cicada/notchdrop`.
