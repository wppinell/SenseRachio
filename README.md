# SenseRachio

A native iOS app that connects [Seeed SenseCraft](https://sensecap.seeed.cc) soil sensors with [Rachio](https://rachio.com) smart irrigation zones — no backend, no database, no server required.

## Features

- 📡 **Live soil moisture & temperature** from Seeed SenseCAP sensors via SenseCraft cloud API
- 💧 **Rachio zone control** — view zones, start/stop watering directly from your phone
- 🔗 **Sensor-zone linking** — map a sensor to a zone and set moisture thresholds
- 🔔 **Local notifications** — get alerted when a sensor drops below your threshold
- 📴 **Works offline** — last readings cached locally via SwiftData
- 🔒 **Keychain credential storage** — API keys never stored in plaintext

## Modes

SenseRachio works in any of three configurations:

| Mode | Description |
|------|-------------|
| SenseCraft only | Monitor soil sensors, no irrigation control |
| Rachio only | Control irrigation zones, no sensor data |
| Both | Full integration — sensors + zones + linking |

## Requirements

- iOS 17+
- Xcode 15+
- SenseCraft account with API key (optional)
- Rachio account with API key (optional)

## Getting Started

1. Clone the repo and open `SenseRachio.xcodeproj` in Xcode
2. Build and run on your device or simulator
3. On first launch, enter your credentials in **Settings**:
   - **SenseCraft**: API Key + API Secret (from [SenseCraft console](https://sensecap.seeed.cc))
   - **Rachio**: API Key (from [Rachio app](https://app.rach.io) → Account → API)
4. Tap **Test Connection** to verify each service
5. Your sensors and zones will appear automatically

## Architecture

```
SenseRachio/
├── Models/
│   ├── APIModels.swift          # SenseCraft + Rachio API response types
│   └── SwiftDataModels.swift    # Local persistence (SensorConfig, ZoneConfig, SensorReading)
├── Services/
│   ├── SenseCraftAPI.swift      # SenseCraft cloud API client
│   ├── RachioAPI.swift          # Rachio cloud API client
│   ├── KeychainService.swift    # Secure credential storage
│   └── NotificationService.swift # Local moisture alerts
├── ViewModels/
│   ├── AppState.swift           # Global credential/setup state
│   ├── DashboardViewModel.swift
│   ├── SensorsViewModel.swift
│   └── ZonesViewModel.swift
├── Views/
│   ├── MainTabView.swift        # 3-tab root (Dashboard / Sensors / Zones)
│   ├── Dashboard/
│   ├── Sensors/
│   ├── Zones/
│   └── Settings/
└── Background/
    └── BackgroundRefreshManager.swift  # 10-min background polling
```

## API Notes

**SenseCraft (SenseCAP):**
- Base URL: `https://sensecap.seeed.cc/openapi`
- Auth: HTTP Basic (API Key : API Secret)
- Measurement IDs: `4103` = soil moisture (%), `4102` = soil temperature (°C)

**Rachio:**
- Base URL: `https://api.rach.io/1/public`
- Auth: `Authorization: Bearer <api_key>`

## Sensor Colors

| Color | Moisture |
|-------|----------|
| 🟢 Green | > 40% |
| 🟡 Yellow | 25–40% |
| 🔴 Red | < 25% |

## License

MIT
