NotchDrop vendor notice

- Source: https://github.com/Lakr233/NotchDrop
- Version: tag 2.9.26
- License: MIT, preserved in LICENSE
- Local integration:
  - Vendored notch window, drag/drop tray, AirDrop/share, settings, event monitor, assets, and localization-adjacent Swift UI code into Sentinel.
  - Excluded upstream main.swift, AppDelegate.swift, and PublishedPersist.swift so Sentinel owns process lifecycle and persistence.
  - Replaced the upstream ~/Documents/NotchDrop storage root with ~/.cicada/notchdrop.
  - Added a transient notification content mode used by Cicada's notifier socket.
