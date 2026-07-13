NotchDrop vendor notice

- Source: https://github.com/Lakr233/NotchDrop
- Version: tag 2.9.26
- Baseline commit: b4ddec566169ea78ea0e1616f3e500228c19d8f7
- License: MIT, preserved in LICENSE
- Local source mapping:
  - Upstream `NotchDrop/*.swift` is selectively integrated into `../../Sentry/NotchDrop/` and compiled as part of the Cicada app.
  - Sentinel owns the app lifecycle and shared persistence helpers in `../../Sentry/`; no NotchDrop executable target or SPM dependency is used.
  - `ThirdParty/NotchDrop/` contains provenance and the upstream license, not the production Swift source.
- Local integration:
  - Vendored notch window, drag/drop tray, AirDrop/share, settings, event monitor, assets, and localization-adjacent Swift UI code into Sentinel.
  - Did not import upstream `main.swift`, `AppDelegate.swift`, or `PublishedPersist.swift` as separate NotchDrop lifecycle files; equivalent shared lifecycle and persistence responsibilities remain owned by Sentinel.
  - Replaced the upstream ~/Documents/NotchDrop storage root with ~/.cicada/notchdrop.
  - Added a transient notification content mode used by Cicada's notifier socket.

The entries above are the maintained local-change inventory. Generate an exact source diff before an update with:

```bash
pnpm run vendor:audit
bash apps/agent/scripts/audit-vendored.sh --diff notchdrop > /tmp/cicada-notchdrop-vendor.diff
```

Review and selectively port upstream commits into the integrated source. Do not replace this integration with an SPM dependency or overwrite Sentinel lifecycle files wholesale.
