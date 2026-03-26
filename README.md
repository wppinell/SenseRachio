# RachioSense

An iOS app that bridges **SenseCAP soil moisture sensors** with the **Rachio irrigation controller**, giving you rich historical graphs, smart watering automation, and full control over your garden's health.

---

## Screenshots

*(Add screenshots here)*

---

## Features Overview

- 🏠 **Dashboard** — Sensor status summary, system health, 7-day weather forecast
- 📊 **Graphs** — Historical moisture data with configurable thresholds
- 💧 **Sensors** — Live readings with status filters (Critical/Dry/OK/High)
- 🌿 **Zones** — Rachio zone control with schedule info and weekly runtime
- ⚙️ **Settings** — Comprehensive configuration options

---

## Complete UI Reference

### Tab Bar (Bottom Navigation)

| Tab | Icon | Description |
|-----|------|-------------|
| **Dashboard** | `house.fill` | Status summary, sensor health, weather forecast |
| **Graphs** | `chart.line.uptrend.xyaxis` | Historical moisture graphs by zone group |
| **Sensors** | `sensor.fill` | All sensors with live readings and filters |
| **Zones** | `drop.fill` | Rachio irrigation zones with schedule info |
| **Settings** | `gearshape.fill` | All configuration options |

---

## 🏠 Dashboard Tab

### MOISTURE Card

Shows sensor health at a glance. Hidden sensors are excluded from all counts and lists.

| Element | Description |
|---------|-------------|
| **Critical section** | 🔺 Red — sensors below auto-water threshold, listed with name + moisture % |
| **Dry section** | ⚠️ Yellow — sensors below dry threshold, listed with name + moisture % |
| **High section** | 💧 Blue — sensors above high threshold, listed with name + moisture % |
| **OK summary** | "All 7 sensors OK" or "4 OK" — no individual names needed |
| **See All →** | Navigates to Sensors tab |

### SYSTEM STATUS Card

| Element | Description |
|---------|-------------|
| **SenseCraft** | ● green/red + sensor count + "synced Xm ago" |
| **Rachio** | ● green/red + device name + enabled zone count |

### WEATHER Card

Live 7-day forecast via [Open-Meteo](https://open-meteo.com) (free, no API key required).

| Element | Description |
|---------|-------------|
| **Current** | Weather icon, temperature, humidity % |
| **7-day strip** | TOD / TOM / day labels, icon, high °, low ° |

Weather is fetched once on load and cached in memory — switching tabs doesn't re-fetch.

---

## 📊 Graphs Tab

Historical moisture data in cards organized by zone groups.

### Graph Card

| Element | Description |
|---------|-------------|
| **Title** | Zone group name |
| **Period Picker** | `1d` `2d` `4d` `5d` `1w` — single tap = this card, double tap = sync all |
| **Chart** | Line graph, moisture % over time |
| **X-Axis** | `M/D` date labels centered on grid lines |
| **Y-Axis** | Moisture % ticks |
| **Threshold lines** | 🔴 auto-water · 🟡 dry · 🔵 high (dashed) |
| **Legend** | Colored squares + sensor names |

### Pull-to-Refresh

Smart refresh — only fetches data since the last stored reading. If last reading was 2h ago, fetches 2h of data (not full 7 days). Falls back to cached data if the API fails.

---

## 💧 Sensors Tab

### Filter Chips

| Chip | Color | Criteria |
|------|-------|----------|
| **All** | Accent | All visible sensors |
| **Critical** | 🔴 Red | < auto-water threshold |
| **Dry** | 🟡 Yellow | between auto-water and dry threshold |
| **OK** | 🟢 Green | between dry and high threshold |
| **High** | 🔵 Blue | > high threshold |
| **[Group Name]** | Muted | Sensors in that zone group |

### Sensor Row

| Element | Description |
|---------|-------------|
| **Status dot** | Color matches moisture level |
| **Name** | Alias if set, else original name |
| **Moisture %** | Current reading |
| **Temperature** | °F or °C |
| **Last updated** | Relative time |
| **Moisture bar** | Horizontal color bar |
| **Status label** | Only shown for Critical / Dry / High — nothing for OK |
| **Auto badge** | "Auto at 20%" shown for OK sensors with auto-water enabled |

Sensor readings never go blank on refresh — app falls back to last cached reading if API fails.

---

## 🌿 Zones Tab

### Zone Row

| Element | Description |
|---------|-------------|
| **Number badge** | Green if running, accent if idle |
| **Zone name** | Rachio zone name |
| **Last watered** | "Watered 3h ago · 15m" |
| **Weekly schedule** | 📅 "40 min/week · Column Ficus" |
| **Run button** | Opens duration picker (5/10/15/20/30 min) |
| **Stop button** | Stops running zone immediately |

**Weekly minutes logic:**

| Schedule type | Runs/week |
|---------------|-----------|
| `INTERVAL_1` | 7× (daily) |
| `INTERVAL_2` | 3.5× (every 2 days) |
| `INTERVAL_N` | 7÷N |
| `DAY_OF_WEEK_N` | Count of specific days |

Displayed as minutes if < 90min, hours+minutes if ≥ 90min.

### Zone Detail View

| Section | Contents |
|---------|----------|
| **Header** | Zone number, status badge, last watered |
| **Control** | Duration picker + Start/Stop |
| **Run History** | Recent watering events |
| **Schedule** | All schedules using this zone: name, summary, start time, run duration |
| **Linked Sensors** | Sensors assigned to this zone |
| **Group** | Which zone group |

---

## ⚙️ Settings Tab

### Account

| Service | Fields |
|---------|--------|
| **SenseCraft** | API Key + Secret, Test Connection button |
| **Rachio** | API Key, Test Connection button |

### Configuration

#### Sensor-Zone Links

| Field | Description |
|-------|-------------|
| **Alias** | Custom display name |
| **Zone Picker** | Link to Rachio zone |
| **Auto-water** | Enable auto-irrigation when critical |
| **Show in Graphs** | Toggle visibility |
| **Remove Link** | Unlink from zone |

#### Zone Groups

Group zones for combined graph display. Drag to reorder, swipe to delete.

#### Thresholds

| Threshold | Default | Color |
|-----------|---------|-------|
| **High Level** | 40% | 🔵 Blue |
| **Dry Level** | 25% | 🟡 Yellow |
| **Auto-water Trigger** | 20% | 🔴 Red |

All thresholds are **global** — used throughout the app including sensors, dashboard, notifications, and background refresh.

#### Notifications

Dry alerts and critical alerts when sensors drop below thresholds.

#### Weather Integration

Rain skip and freeze skip toggles for Rachio scheduling.

### Display

| Setting | Options |
|---------|---------|
| **Theme** | System / Light / Dark |
| **Default Graph Period** | 1d – 1w |
| **Graph Y-Axis** | Min / Max % |
| **Sensor Labels** | Primary / secondary label, status indicator style |
| **Temperature Units** | °F / °C |

### Data & Privacy

| Feature | Description |
|---------|-------------|
| **Backup** | Export aliases, links, groups, settings as JSON |
| **Restore** | Import from JSON backup |
| **Export Data** | CSV or JSON for a date range |
| **Clear Old Data** | Delete readings > 7 days |

### Support

| Tool | Description |
|------|-------------|
| **API Latency** | Measure SenseCraft + Rachio response times |
| **History API Test** | Fetch 7d history for first sensor |
| **Copy Debug Log** | Full diagnostic report to clipboard |
| **Reset Graph Cache** | Delete all readings, force full re-fetch |

### Reset

| Button | Clears |
|--------|--------|
| **Reset SenseCraft** | Credentials only |
| **Reset Rachio** | Credentials only |
| **Clear Sensor Links** | Zone links + auto-water |
| **Reset Settings** | Display preferences |
| **Reset Everything** | All data, returns to onboarding |

---

## Architecture

### Data Flow

```
SenseCAP API
    ↓ (batched, rate-limited)
GraphDataPrefetcher ──► SwiftData (7 days local) ──► GraphsViewModel ──► Graphs UI
    ↓ (fallback)
Last cached reading ──────────────────────────────► SensorsViewModel ──► Sensors UI

Rachio API ──► device + scheduleRules (single call) ──► ZonesViewModel ──► Zones UI

Open-Meteo ──────────────────────────────────────────► DashboardViewModel ──► Weather UI
```

### Services

| File | Purpose |
|------|---------|
| `SenseCraftAPI.swift` | SenseCAP HTTP client — devices, readings, chunked 24h history |
| `RachioAPI.swift` | Rachio client — devices, zones, schedules (embedded in device response), zone control |
| `GraphDataPrefetcher.swift` | Smart incremental fetch, dedup, rate limiting, 7-day pruning |
| `WeatherAPI.swift` | Open-Meteo 7-day forecast, no API key needed |
| `KeychainService.swift` | Secure credential storage (survives app reinstall) |
| `BackgroundRefreshManager.swift` | iOS BGAppRefresh task for background moisture checks |

### Data Models (SwiftData)

| Model | Key Fields |
|-------|------------|
| `SensorConfig` | id, name, alias, eui, linkedZoneId, autoWaterEnabled, isHiddenFromGraphs |
| `ZoneConfig` | id, name, deviceId, lastRunAt |
| `SensorReading` | eui, moisture, tempC, recordedAt |
| `ZoneGroup` | id, name, sortOrder, assignedZoneIds |
| `DashboardCardOrder` | cards, hiddenCards |

### Rate Limiting & Resilience

- Sensors fetched **2 at a time** (not all parallel) to avoid 429s
- **30-second cooldown** between full graph refreshes
- **Fallback to cached readings** — sensors never go blank on API failure
- Dashboard **seeds from SwiftData immediately** before hitting the API

---

## Setup Guide

1. **SenseCAP credentials** — [sensecap.seeed.cc](https://sensecap.seeed.cc) → Account → Access API Keys
2. **Rachio API key** — Rachio app → Account → API Access
3. Open RachioSense → **Settings → Account** → enter credentials → Test Connection
4. **Settings → Configuration → Sensor-Zone Links** → link each sensor to its zone
5. **Settings → Configuration → Thresholds** → adjust for your soil type
6. Open **Graphs tab** — data loads automatically

---

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 6
- SenseCAP soil moisture sensors + account
- Rachio irrigation controller + account

---

## 🔮 Planned Features (Next Up)

### High Priority
- [ ] **Location-based weather** — use device GPS or user-set location instead of hardcoded Phoenix coordinates
- [ ] **SenseCraft subscription expiry alert** — check device metadata for expiry date and warn when < 30 days remaining
- [ ] **Rachio next scheduled run** — show "Next run: Tomorrow 6:00 AM" on dashboard and zone rows
- [ ] **Auto-water execution** — when a sensor drops below auto-water threshold, actually trigger the linked Rachio zone
- [ ] **Notifications** — local push alerts when sensors go critical or auto-water fires

### Medium Priority
- [ ] **Widget support** — iOS home screen widget showing moisture summary
- [ ] **Sensor detail history chart** — use stored SwiftData readings instead of re-fetching from API
- [ ] **Zone group reordering** — drag to reorder groups on Graphs tab
- [ ] **Flex schedule support** — better weekly minutes estimate for Rachio flex schedules
- [ ] **Multiple Rachio devices** — UI currently shows first device only
- [ ] **iCloud sync** — sync sensor aliases, links, and groups across devices

### Nice to Have
- [ ] **Apple Watch complication** — glanceable moisture summary
- [ ] **Siri shortcuts** — "Hey Siri, water the tomatoes for 10 minutes"
- [ ] **Historical watering log** — correlate Rachio run history with moisture trends
- [ ] **CSV import** — bulk import sensor aliases from spreadsheet
- [ ] **Share graph** — export graph as image

---

## 🐛 Known Issues & Technical Debt

### Active Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| **SwiftData off-main-thread warning** | Low | `ModelContext` used off main queue in BackgroundRefreshManager — should use `ModelActor` |
| **Rate limiting during initial load** | Medium | First-ever 7-day fetch hits SenseCAP 429 if app is opened repeatedly; cooldown helps but first-run can be slow |
| **Flex schedule weekly minutes** | Low | Rachio flex schedules don't have fixed days — currently shows 1×/week estimate which is inaccurate |
| **Weather location hardcoded** | Medium | Open-Meteo coordinates are hardcoded to Phoenix, AZ (`33.4484, -112.0740`) |
| **Background refresh not tested** | Low | `BGAppRefreshTask` registered but iOS background task delivery is unpredictable |

### Technical Debt

| Item | Notes |
|------|-------|
| **Duplicate zone detail navigation** | `ZoneDetailView` appears in both ZonesView and potentially other contexts — ensure device is always passed |
| **`moistureThreshold` field in SwiftData** | Field kept for DB backward compatibility but no longer used — can be migrated away in a future schema version |
| **SensorsViewModel fetches live readings** | Sensors tab always hits the API on load; should use cached SwiftData readings like GraphsViewModel does |
| **DashboardViewModel fetches live sensor readings** | Same issue as SensorsViewModel — creates duplicate API calls when both tabs load |
| **No error recovery UI** | API errors are shown as banner text but there's no retry button or offline mode indicator |
| **Graph period picker uses local state** | `localPeriod` in `SensorGraphCard` resets to default on card re-render; should persist per-card via AppStorage |

### SenseCAP API Limitations

| Limitation | Impact |
|------------|--------|
| **Rate limiting** | ~50 req/min; 7-sensor × 7-chunk parallel fetch triggers 429s |
| **No push/webhook** | Must poll for new data; no real-time updates |
| **24h chunk limit** | `/list_telemetry_data` returns limited results per call; must page in 24h windows |
| **No expiry field exposed** | Subscription/license expiry not available via public API |

---

## Backup Reminder

Settings are stored locally and **will be lost if the app is deleted**.

Before uninstalling: **Settings → Data & Privacy → Backup & Restore → Create Backup**

Save the JSON file to Files, iCloud, or AirDrop somewhere safe.

---

## License

MIT License — see LICENSE file
