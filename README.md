# RachioSense

An iOS app that bridges **SenseCAP soil moisture sensors** with the **Rachio irrigation controller**, giving you rich historical graphs, smart watering automation, and full control over your garden's health.

---

## Features

### 📊 Graphs
- **Historical data** from SenseCAP API — up to 14 days of readings
- **Per-card time range** selector: 1d, 2d, 3d, 4d, 5d, 1w, 2w
- **Single tap** a period → changes only that graph
- **Double tap** a period → syncs all graphs to the same range
- **Three threshold lines** on every graph:
  - 🔴 Red dashed — Auto-water trigger level
  - 🟡 Yellow dashed — Dry level
  - 🔵 Blue dashed — High level
- **Configurable Y-axis** range (Settings → Display → Appearance)
- **Smart data fetching**: 7-day history on first launch, incremental gap-fill on subsequent opens
- **2-week on-demand fetch** when 2w period is selected
- Pull-to-refresh re-fetches full history

### 💧 Sensors
- Lists all SenseCAP devices with live moisture and temperature readings
- **Color-coded status** based on configurable thresholds:
  - 🔴 Red — Below auto-water level (needs water now)
  - 🟡 Yellow — Below dry level (getting dry)
  - 🟢 Green — Below high level (good)
  - 🔵 Blue — Above high level (well watered)
- **Moisture bar** with threshold-aware color
- **Sensor aliases** — set friendly names; original name shown below
- **Disable sensors** — hides from graphs and stops data collection

### 🌿 Zones
- Lists all Rachio irrigation zones
- View zone status and last run time
- Zone-to-sensor linking

### ⚙️ Settings

#### Account
- **SenseCraft** API key + secret (stored in Keychain)
- **Rachio** API key (stored in Keychain)

#### Configuration
- **Sensor-Zone Links** — link soil sensors to Rachio zones; set per-sensor thresholds, auto-water triggers, aliases
- **Zone Display Grouping** — group zones for combined graphs
- **Thresholds** — global defaults for Auto-water, Dry, and High level triggers
- **Notifications** — alerts for dry sensors
- **Weather Integration** — skip watering when rain is forecast

#### Display
- **Graph Default Period** — default time range shown on Graphs tab (default: 3 days)
- **Graph Scale** — configure Y-axis min/max (default: 15%–45%)
- **Appearance** — theme, accent color, haptics, animations
- **Units** — temperature (°F/°C), moisture display

#### Data & Privacy
- **Backup & Restore** — export sensor aliases, links, thresholds, and groups as JSON; restore from backup without losing credentials or readings
- **Export Data** — export sensor readings as CSV or JSON
- **Local Storage** — view storage usage
- **Privacy** — data handling info

#### Support
- **Diagnostics** — API latency, sync status, history API test, reset graph cache
- **Help / FAQ**
- **About**

#### Reset
- Per-service credential reset
- Full app data reset

---

## Architecture

### Data Flow

```
SenseCAP API
    ↓
GraphDataPrefetcher (app launch, background)
    ↓
SwiftData (local store — up to 14 days)
    ↓
GraphsViewModel (reads local store)
    ↓
SensorGraphCard (renders chart)
```

### Key Services

| File | Purpose |
|------|---------|
| `SenseCraftAPI.swift` | SenseCAP HTTP API client — list devices, latest readings, historical data (chunked 24h requests) |
| `RachioAPI.swift` | Rachio REST API client — devices, zones, schedules |
| `GraphDataPrefetcher.swift` | Smart historical fetch — incremental gap-fill, 14-day on-demand, dedup |
| `KeychainService.swift` | Secure credential storage |
| `BackgroundRefreshManager.swift` | iOS background task registration |

### Data Models (SwiftData)

| Model | Fields |
|-------|--------|
| `SensorConfig` | id, name, alias, eui, linkedZoneId, moistureThreshold, autoWaterEnabled, isHiddenFromGraphs, groupId |
| `ZoneConfig` | id, name, deviceId, lastRunAt |
| `SensorReading` | eui, moisture, tempC, recordedAt |
| `ZoneGroup` | id, name, sortOrder, assignedZoneIds |
| `DashboardCardOrder` | cardId, position, isVisible |

### Storage
- **Keychain**: API credentials (survive app deletion)
- **SwiftData**: sensor configs, readings, groups, layout (lost on app deletion — use Backup & Restore)
- **UserDefaults**: display preferences, fetch timestamps

---

## Setup

1. Get your **SenseCAP API credentials** from [sensecap.seeed.cc](https://sensecap.seeed.cc) → Account → Access API Keys
2. Get your **Rachio API key** from the Rachio app → Account → API Access
3. Open RachioSense → Settings → Account → enter both sets of credentials
4. Go to Sensors tab → tap "Load from SenseCraft" to import your devices
5. Go to Settings → Configuration → Sensor-Zone Links → link each sensor to its Rachio zone
6. Open Graphs tab — historical data loads automatically

---

## Requirements

- iOS 17+
- Xcode 15+
- Swift 6
- SenseCAP account with soil moisture sensors
- Rachio irrigation controller

---

## SenseCAP API Notes

The `/list_telemetry_data` endpoint returns data in a nested array format (not standard JSON objects):

```json
{
  "code": "0",
  "data": {
    "list": [
      [[1, "4102"], [1, "4103"]],
      [[[value, isoTimestamp], ...], ...]
    ]
  }
}
```

- Measurement `4102` = temperature (°C)
- Measurement `4103` = soil moisture (%)
- Results are capped per request — app fetches in 24h chunks to get full history

---

## Backup & Restore

Settings are stored in SwiftData and will be lost if the app is deleted. **Before resetting or reinstalling**, go to:

**Settings → Data & Privacy → Backup & Restore → Create Backup**

Save the JSON file to iCloud, Files, or AirDrop it somewhere safe. Restore from the same screen.

---

## Development Notes

- Swift 6 strict concurrency — all SwiftData operations on `@MainActor`
- `TaskGroup` used for parallel sensor fetches — uses `Sendable` structs, not SwiftData models
- `@Observable` for view models (not `ObservableObject`)
- Design system in `DesignSystem.swift` — colors, fonts, spacing, components
