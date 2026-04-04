# RachioSense

An iOS app that bridges **SenseCAP soil moisture sensors** with the **Rachio irrigation controller**, giving you rich historical graphs, smart watering automation, and full control over your garden's health.

---

## Screenshots

*(Add screenshots here)*

---

## Features Overview

- 🏠 **Dashboard** — Weather forecast, sensor alerts, system health status
- 📊 **Graphs** — Historical moisture data with configurable thresholds
- 💧 **Sensors** — Live readings with status filters (Critical/Dry/OK/High)
- 🌿 **Zones** — Rachio zone control with schedule info and weekly runtime
- ⚙️ **Settings** — Comprehensive configuration options

---

## Navigation Map

```
RachioSense
│
├── TAB: Dashboard (house.fill)
│   ├── WEATHER card — 7-day Open-Meteo forecast
│   ├── ALERTS card — Critical / Dry / High / Subscription expiry / Rate limit
│   └── SYSTEM STATUS card — SenseCraft + Rachio connectivity + API call counter
│
├── TAB: Graphs (chart.line.uptrend.xyaxis)
│   └── Per-group sensor graph cards
│       ├── Period picker (1d / 2d / 4d / 5d / 1w) — single tap = this card, double tap = all cards
│       ├── Line chart with threshold lines (critical / dry / high)
│       └── Rachio watering event overlay (teal shaded regions)
│
├── TAB: Sensors (sensor.fill)
│   ├── Filter chips: All / Critical / Dry / OK / High / [Group]
│   ├── Sensor rows: status dot, name, moisture %, temp, bar, timestamp, predictive dry date
│   └── Sensor Detail
│       ├── Header: moisture %, temperature, status badge, last updated
│       ├── Subscription expiry countdown (if known)
│       ├── Linked zone + quick-run button
│       └── Settings: alias, zone picker, auto-water toggle, hide-from-graphs toggle
│
├── TAB: Zones (drop.fill)
│   ├── Sort toolbar: Moisture / Name / Next Run / Last Watered / Weekly Watering
│   ├── Zone cards: number badge, name, last watered, weekly schedule, run button
│   └── Zone Detail
│       ├── Header: zone number, name, status, last watered
│       ├── Duration picker + Start / Stop buttons
│       ├── Run history (recent watering events)
│       ├── Schedules (all rules that include this zone)
│       └── Linked sensors
│
└── TAB: Settings (gearshape.fill)
    │
    ├── ACCOUNT
    │   ├── SenseCraft — API key/secret, test connection, sign out
    │   └── Rachio — API key, device info, test connection, sign out
    │
    ├── CONFIGURATION
    │   ├── Sensor-Zone Links — alias, zone picker, auto-water toggle, hide toggle
    │   ├── Zone Groups — create / reorder / delete groups; assign sensors and zones
    │   ├── Thresholds — High / Dry / Auto-water sliders; subscription alert days
    │   ├── Notifications — see Notification Settings below
    │   ├── Weather Integration — rain/freeze skip toggles and thresholds
    │   └── Refresh Rate — foreground (15s–5m) + background (10m–1h)
    │
    ├── DISPLAY
    │   ├── Appearance — theme, accent color, animations, haptics, icon style
    │   ├── Units — temperature (°F/°C), moisture (% / raw), duration, volume
    │   ├── Dashboard Layout — card order + visibility
    │   └── Sensor Labels — primary / secondary / status indicator style
    │
    ├── DATA & PRIVACY
    │   ├── Local Storage — usage stats, retention picker, clear old readings
    │   ├── Export Data — CSV or JSON for a date range
    │   ├── Backup & Restore — JSON backup of settings (excludes credentials and readings)
    │   └── Privacy — permission statuses, data deletion
    │
    ├── SUPPORT
    │   └── Diagnostics — API latency test, history test, copy debug log, reset graph cache
    │
    └── RESET
        ├── Reset SenseCraft / Reset Rachio — clears credentials
        ├── Clear Sensor Links — removes zone links, aliases, auto-water settings
        ├── Reset Settings — restores display preferences and thresholds to defaults
        └── Reset Everything — full wipe, returns to onboarding
```

---

## Complete UI Reference

### Tab Bar (Bottom Navigation)

| Tab | Icon | Description |
|-----|------|-------------|
| **Dashboard** | `house.fill` | Weather, alerts, system status |
| **Graphs** | `chart.line.uptrend.xyaxis` | Historical moisture graphs by zone group |
| **Sensors** | `sensor.fill` | All sensors with live readings and filters |
| **Zones** | `drop.fill` | Rachio irrigation zones with schedule info |
| **Settings** | `gearshape.fill` | All configuration options |

---

## 🏠 Dashboard Tab

The dashboard is organized into three cards, displayed top-to-bottom:

### 1. WEATHER Card (Top)

Live 7-day forecast via [Open-Meteo](https://open-meteo.com) (free, no API key required).

| Element | Description |
|---------|-------------|
| **Current conditions** | Weather icon + temperature + humidity % |
| **7-day forecast strip** | Horizontal scroll showing: |
| | • Day label (TOD / TOM / Mon / Tue / etc.) |
| | • Weather condition icon |
| | • High temperature |
| | • Low temperature |

**Behavior:**
- Fetched once on app load
- Cached in memory — switching tabs doesn't re-fetch
- Location: Phoenix, AZ (hardcoded at `33.4484, -112.0740`)

---

### 2. ALERTS Card (Middle)

Shows actionable sensor alerts only. Hidden sensors (`isHiddenFromGraphs = true`) are excluded from all counts.

| Alert Type | Icon | Color | Trigger Condition |
|------------|------|-------|-------------------|
| **Critical** | `exclamationmark.triangle.fill` | 🔴 Red | Moisture < auto-water threshold (default 20%) |
| **Dry** | `exclamationmark.circle.fill` | 🟡 Yellow | Moisture between auto-water and dry threshold |
| **High** | `drop.fill` | 🔵 Blue | Moisture > high threshold (default 40%) |
| **Subscription Expiring** | `calendar.badge.exclamationmark` | 🟡 Yellow | Sensor subscription expires within configured days |
| **Rachio Rate Limited** | `exclamationmark.icloud.fill` | 🔴 Red | API rate limit hit (0/3500 daily calls remaining) |

**Alert Display Format:**

For moisture alerts (Critical/Dry/High):
```
🔺 Critical
  Tomato Bed          18%
  Herb Garden         19%
```

For subscription expiry:
```
📅 Subscription Expiring
  Soil Sensor #1      14d
  Soil Sensor #2      14d
```

For rate limiting:
```
☁️ Rachio API Rate Limited
   Resets in 1h 58m
```

**When All OK:**
- If no alerts of any type, shows: `✓ All 7 sensors OK`

**What's NOT shown:**
- Individual OK sensors (no list, no count when other alerts exist)
- "See All" link (removed)

---

### 3. SYSTEM STATUS Card (Bottom)

Shows connectivity and health for both services.

#### SenseCraft Row

| Element | Description |
|---------|-------------|
| **Icon** | `sensor.fill` with accent background |
| **Title** | "SenseCraft" |
| **Status dot** | 🟢 green = connected, 🔴 red = disconnected |
| **Status text** | "Connected" or "Disconnected" |
| **Details line** | `7 sensors · synced 5m ago` |

#### Rachio Row

| Element | Description |
|---------|-------------|
| **Icon** | `drop.fill` with accent background |
| **Title** | "Rachio" |
| **Status dot** | 🟢 green = connected, 🔴 red = disconnected |
| **Status text** | "Connected" or "Disconnected" |
| **Details line** | `Pinellos · 9 zones · 3498/3500 API` |

**API Counter Behavior:**
- Shows `remaining/total API` calls for current day
- Turns 🟡 yellow when < 100 remaining
- Resets daily at midnight UTC (5 PM MST)

---

## 📊 Graphs Tab

Historical moisture data displayed in cards organized by zone groups.

### Graph Card Structure

| Element | Description |
|---------|-------------|
| **Title** | Zone group name (e.g., "Garden Beds", "Citrus Trees") |
| **Period Picker** | Segmented control: `1d` `2d` `4d` `5d` `1w` |
| **Chart Area** | Line graph with moisture % over time |
| **Threshold Lines** | Dashed horizontal lines at configured thresholds |
| **Legend** | Colored squares with sensor names |

### Period Picker Behavior

| Action | Result |
|--------|--------|
| Single tap | Changes period for this card only |
| Double tap | Syncs all cards to this period |

### X-Axis Label Format

| Period | Interval | Format | Example |
|--------|----------|--------|---------|
| 1 day | 6 hours | Hour only | `8 AM`, `2 PM` |
| 2 days | 12 hours | Day + Hour | `Wed 8 AM` |
| 4+ days | Daily | Month + Day | `Mar 26` |

### Threshold Lines

| Threshold | Color | Line Style | Default |
|-----------|-------|------------|---------|
| Auto-water | 🔴 Red | Dashed | 20% |
| Dry | 🟡 Yellow/Orange | Dashed | 25% |
| High | 🔵 Blue | Dashed | 40% |

### Watering Event Overlay

Rachio watering history is fetched and overlaid directly on each graph card:

| Element | Description |
|---------|-------------|
| **Start line** | Teal dashed vertical line at zone start time |
| **End line** | Teal dashed vertical line at zone stop time |
| **Fill** | Light teal shaded region between start and end (runs ≥ 5 min only) |

Events are matched to graph cards by zone name. Each card shows only events for its own zone.

### Double-Tap Period Sync

| Action | Result |
|--------|--------|
| Single tap | Changes period for this card only |
| Double tap | Syncs all cards — brief blue border flashes on all cards |

### Pull-to-Refresh Behavior

**Smart Incremental Fetch:**
1. Calculates hours since last stored reading per sensor
2. Fetches only the gap (not full 7 days) — concurrent for short fetches, sequential for 7-day history
3. Example: If last reading was 2h ago, fetches 2h of data for all sensors simultaneously

**Cooldown:**
- 30-second minimum between full refreshes
- Prevents API hammering on repeated pull-to-refresh

**Fallback:**
- If API fails, displays cached data from SwiftData
- Never shows blank graphs on network error

---

## 💧 Sensors Tab

### Filter Chips (Horizontal Scroll)

| Chip | Color | Count | Filter Criteria |
|------|-------|-------|-----------------|
| **All** | Accent | Total visible | No filter |
| **Critical** | 🔴 Red | Count | `moisture < autoWaterThreshold` |
| **Dry** | 🟡 Yellow | Count | `autoWaterThreshold ≤ moisture < dryThreshold` |
| **OK** | 🟢 Green | Count | `dryThreshold ≤ moisture ≤ highThreshold` |
| **High** | 🔵 Blue | Count | `moisture > highThreshold` |
| **[Group Name]** | Muted | Count | Sensors in that zone group |

### Sensor Row Layout

```
┌─────────────────────────────────────────────────────┐
│ 🟢  Tomato Bed                           32% · 78°F │
│     ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░  2m ago │
│     Auto at 20%                                     │
└─────────────────────────────────────────────────────┘
```

| Element | Description |
|---------|-------------|
| **Status dot** | Colored circle matching moisture status |
| **Name** | Alias if set, otherwise original sensor name |
| **Moisture %** | Current reading, right-aligned |
| **Temperature** | °F or °C based on settings |
| **Moisture bar** | Horizontal gradient bar showing level |
| **Timestamp** | Relative time since last reading |
| **Status label** | Critical/Dry/High badges (hidden for disabled sensors) |
| **Moisture %** | Displayed in threshold color (red/yellow/green/blue) |
| **Predictive dry date** | "Dries in 6h / tomorrow / in 3 days" when trending downward |
| **Auto badge** | "Auto at 20%" shown for OK sensors with auto-water enabled |

### Sensor Detail View

Accessed by tapping a sensor row.

#### Header Section
- Large moisture percentage display
- Temperature reading
- Status badge (Critical/Dry/OK/High)
- Last updated timestamp

#### Subscription Section (if expiry known)

| Days Remaining | Icon | Color | Text |
|----------------|------|-------|------|
| ≤ 0 | `exclamationmark.triangle.fill` | 🔴 Red | "Subscription expired" |
| 1 | `exclamationmark.triangle.fill` | 🔴 Red | "Expires tomorrow" |
| 2-7 | `exclamationmark.triangle.fill` | 🔴 Red | "Expires in X days" |
| 8-30 | `calendar.badge.clock` | 🟡 Yellow | "Expires in X days" |
| > 30 | `calendar.badge.clock` | Gray | "Expires in X days" |

Also shows the actual expiry date (e.g., "Apr 9, 2026").

#### Linked Zone Section
- Shows linked Rachio zone name and number
- Auto-water threshold indicator
- Quick-run button

#### Settings Section
- Alias text field
- Zone picker
- Auto-water toggle
- Hide from graphs toggle

---

## 🌿 Zones Tab

### Zone Sort Options

Tap the ↑↓ icon in the toolbar to sort zone tiles:

| Sort | Order | Description |
|------|-------|-------------|
| **Moisture** | Low → High | Driest zones first (default) |
| **Name** | A → Z | Alphabetical |
| **Next Run** | Soonest first | Uses same schedule logic as zone card display |
| **Last Watered** | Most recent first | Zones watered most recently at top |
| **Weekly Watering** | Most → Least | Zones with most scheduled weekly minutes first |

Sort preference is persisted across sessions.

### Zone Row Layout

```
┌─────────────────────────────────────────────────────┐
│ [1]  Front Lawn                              [▶ 10] │
│      Watered 3h ago · 15m                           │
│      📅 40 min/week · Garden Morning                │
└─────────────────────────────────────────────────────┘
```

| Element | Description |
|---------|-------------|
| **Number badge** | Zone number (green if running, accent if idle) |
| **Zone name** | From Rachio |
| **Run button** | Opens duration picker (5/10/15/20/30 min) |
| **Last watered** | "Watered 3h ago · 15m" |
| **Weekly schedule** | 📅 icon + estimated weekly runtime + schedule name |

### Weekly Runtime Calculation

| Schedule Type | Pattern | Runs/Week | Example |
|---------------|---------|-----------|---------|
| `INTERVAL_1` | Every day | 7.0× | 10 min × 7 = 70 min/week |
| `INTERVAL_2` | Every 2 days | 3.5× | 10 min × 3.5 = 35 min/week |
| `INTERVAL_N` | Every N days | 7÷N | N=3 → 2.33×/week |
| `DAY_OF_WEEK_0` | No specific days | 0× | (flex schedule) |
| `DAY_OF_WEEK_3` | 3 specific days | 3× | Mon/Wed/Fri |

**Display Format:**
- Under 90 minutes: `40 min/week`
- 90+ minutes: `1h 30m/week`

### Zone Detail View

| Section | Contents |
|---------|----------|
| **Header** | Zone number, name, status badge, last watered |
| **Control** | Duration picker + Start/Stop buttons |
| **Run History** | Recent watering events with duration |
| **Schedules** | All schedules that include this zone |
| **Linked Sensors** | Sensors assigned to this zone |
| **Group** | Which zone group contains this zone |

---

## ⚙️ Settings Tab

### Account Section

#### SenseCraft Configuration
| Field | Description |
|-------|-------------|
| **API Key** | From sensecap.seeed.cc → Account → Access API Keys |
| **API Secret** | Paired with API Key |
| **Test Connection** | Validates credentials and shows sensor count |

#### Rachio Configuration
| Field | Description |
|-------|-------------|
| **API Key** | From Rachio app → Account → API Access |
| **Test Connection** | Validates and discovers devices |

---

### Configuration Section

#### Sensor-Zone Links

Per-sensor settings:

| Field | Description |
|-------|-------------|
| **Alias** | Custom display name (shown everywhere instead of original) |
| **Linked Zone** | Picker to associate with a Rachio zone |
| **Auto-water** | Enable automatic watering when critical |
| **Show in Graphs** | Toggle visibility in graphs and dashboard |
| **Remove Link** | Unlink from zone |

#### Zone Groups

- Create groups to organize zones (e.g., "Front Yard", "Garden Beds")
- Drag to reorder groups
- Swipe to delete
- Groups determine graph card organization

#### Thresholds

| Threshold | Default | Color | Slider Range | Purpose |
|-----------|---------|-------|--------------|---------|
| **High Level** | 40% | 🔵 Blue | 30-60% | Above this = "High" status |
| **Dry Level** | 25% | 🟡 Yellow | 15-40% | Below this = "Dry" status |
| **Auto-water Trigger** | 20% | 🔴 Red | 10-30% | Below this = "Critical" + auto-water |
| **Subscription Alert** | 30 days | 🟡 Yellow | 7-90 days | Alert when sensor expires within |

**Slider colors are fixed** (don't change based on value):
- High slider = always blue
- Dry slider = always yellow/orange  
- Auto-water slider = always red

#### Notifications

**Sensor Alerts**

| Setting | Default | Description |
|---------|---------|-------------|
| **Critical Alerts** | On | Fires when moisture drops below the auto-water threshold (default 20%) |
| **Low Alerts** | On | Fires when moisture is between the auto-water and dry thresholds |
| **Sensor Offline** | On | Fires when a sensor hasn't reported in 3+ hours |
| **Predictive Alerts** | On | Fires when the decay model predicts critical/dry within the alert window |
| **Alert window** | 6h | How far ahead predictive alerts fire (2 / 4 / 6 / 12h) |

**Cooldown**

| Setting | Default | Description |
|---------|---------|-------------|
| **Alert cooldown** | 4h | Minimum time between repeated alerts for the same sensor (2 / 4 / 6 / 12 / 24h) |

**Zone Activity**

| Setting | Default | Description |
|---------|---------|-------------|
| **Zone Finished** | Off | Fires when a zone's last-watered timestamp changes (polling-based) |
| **Scheduled Run Soon** | Off | Fires when a zone's next run is within 2 hours |
| **Zone Skipped** | On | Fires when Rachio's Weather Intelligence skips a run (rain, freeze, or wind) |

**Service Alerts**

| Setting | Default | Description |
|---------|---------|-------------|
| **Service Disconnected** | On | Fires when SenseCraft or Rachio hasn't been reachable for 2+ hours (6h cooldown) |

**Summaries**

| Setting | Default | Description |
|---------|---------|-------------|
| **Daily Summary** | Off | "N healthy · N low · driest: X at Y%" at a configured time each day |
| **Weekly Report** | Off | Aggregate health summary on a configured day of the week |

**Quiet Hours**

| Setting | Default | Description |
|---------|---------|-------------|
| **Quiet Hours** | Off | Suppresses all alerts between configured hours (default 10 PM – 7 AM) |

**How notifications fire:**
Background refresh runs every ~15–60 min (iOS controls actual cadence). Each cycle: saves new sensor readings → evaluates predictive alerts → evaluates threshold alerts → checks sensor offline → checks zone changes → checks zone skips → checks service connectivity → checks daily/weekly summaries. Cooldown is tracked per sensor per alert type in UserDefaults so a dry sensor never spams across multiple refresh cycles. Service disconnected alerts use per-service last-success timestamps and only fire if a prior successful connection has been recorded (no false alarms on first launch).

#### Weather Integration

| Setting | Description |
|---------|-------------|
| **Rain Skip** | Let Rachio skip watering when rain expected |
| **Freeze Skip** | Let Rachio skip watering when freezing expected |

---

### Display Section

| Setting | Options | Default |
|---------|---------|---------|
| **Theme** | System / Light / Dark | System |
| **Default Graph Period** | 1d / 2d / 4d / 5d / 1w | 2d |
| **Graph Y-Axis Min** | 0-30% | 15% |
| **Graph Y-Axis Max** | 40-100% | 45% |
| **Temperature Units** | °F / °C | °F |
| **Sensor Primary Label** | Name / EUI / Group | Name |
| **Sensor Secondary Label** | Moisture+Temp / Moisture / Last Updated / Group | Moisture+Temp |
| **Status Indicator Style** | Colored Dot / Colored Background / None | Colored Dot |

---

### Data & Privacy Section

#### Backup & Restore

| Action | Description |
|--------|-------------|
| **Create Backup** | Exports JSON with: sensor aliases, zone links, groups, thresholds, display settings |
| **Restore from Backup** | Imports JSON backup file |

**Backup does NOT include:**
- API credentials (stored in Keychain)
- Historical sensor readings (too large)
- Per-sensor `moistureThreshold` (deprecated, global only)

#### Export Data

| Option | Description |
|--------|-------------|
| **Format** | CSV or JSON |
| **Date Range** | Start and end date pickers |
| **Output** | All sensor readings within range |

#### Clear Old Data

| Action | Description |
|--------|-------------|
| **Delete readings > 7 days** | Removes old readings to save space |

---

### Support Section

| Tool | Description |
|------|-------------|
| **API Latency Test** | Measures response time for SenseCraft + Rachio |
| **History API Test** | Fetches 7-day history for first sensor |
| **Copy Debug Log** | Full diagnostic report to clipboard |
| **Reset Graph Cache** | Deletes all readings, forces full re-fetch |

---

### Reset Section

| Button | Clears | Keeps |
|--------|--------|-------|
| **Reset SenseCraft** | API credentials | Everything else |
| **Reset Rachio** | API credentials | Everything else |
| **Clear Sensor Links** | Zone links + aliases + auto-water | Credentials, groups, settings |
| **Reset Settings** | Display preferences + thresholds | Credentials, data |
| **Reset Everything** | All data | Returns to onboarding |

---

## Architecture

### Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         SenseCAP Cloud                           │
│                  https://sensecap.seeed.cc/openapi               │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │    SenseCraftAPI       │
                    │  • listDevices()       │
                    │  • getLatestReadings() │
                    │  • getHistory()        │◄── Batched 2 at a time
                    │  • 24h chunk limit     │    to avoid 429
                    └────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                      GraphDataPrefetcher                         │
│  • Smart incremental fetch (only fetches gap since last reading) │
│  • Deduplication (skips existing readings)                       │
│  • 30-second cooldown between full refreshes                     │
│  • 7-day data pruning                                            │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                         SwiftData                                │
│  • SensorConfig (id, alias, eui, linkedZoneId, autoWater, etc.) │
│  • SensorReading (eui, moisture, tempC, recordedAt)             │
│  • ZoneConfig (id, name, deviceId, lastRunAt)                   │
│  • ZoneGroup (id, name, sortOrder, assignedZoneIds)             │
└──────────────────────────────────────────────────────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 ▼               ▼               ▼
          ┌───────────┐   ┌───────────┐   ┌───────────┐
          │ Dashboard │   │  Graphs   │   │  Sensors  │
          │ ViewModel │   │ ViewModel │   │ ViewModel │
          └───────────┘   └───────────┘   └───────────┘


┌──────────────────────────────────────────────────────────────────┐
│                         Rachio Cloud                             │
│                   https://api.rach.io/1/public                   │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │      RachioAPI         │
                    │  • getDevices()        │◄── 5-min cache
                    │  • startZone()         │    actor-isolated
                    │  • stopZone()          │    (Swift actor)
                    │  • Rate limit tracking │
                    └────────────────────────┘
                                 │
                                 ▼
                         ┌─────────────┐
                         │    Zones    │
                         │  ViewModel  │
                         └─────────────┘


┌──────────────────────────────────────────────────────────────────┐
│                         Open-Meteo                               │
│          https://api.open-meteo.com/v1/forecast                  │
│                    (Free, no API key)                            │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │      WeatherAPI        │
                    │  • fetchForecast()     │◄── Cached in memory
                    │  • 7-day forecast      │
                    └────────────────────────┘
```

### Service Files

| File | Purpose | Rate Limiting |
|------|---------|---------------|
| `SenseCraftAPI.swift` | SenseCAP HTTP client — devices, readings, 24h-chunked history | 2 sensors/batch |
| `RachioAPI.swift` | Rachio client — devices, zones, schedules, zone control | 5-min cache, 3500/day limit |
| `WeatherAPI.swift` | Open-Meteo 7-day forecast | Memory cache |
| `GraphDataPrefetcher.swift` | Smart incremental fetch, dedup, pruning | 30s cooldown |
| `KeychainService.swift` | Secure credential storage | N/A |
| `BackgroundRefreshManager.swift` | iOS BGAppRefresh for background checks | N/A |

### SwiftData Models

| Model | Key Fields | Notes |
|-------|------------|-------|
| `SensorConfig` | `id`, `name`, `alias`, `eui`, `linkedZoneId`, `autoWaterEnabled`, `isHiddenFromGraphs`, `subscriptionExpiryDate` | `moistureThreshold` kept for DB compat but unused |
| `SensorReading` | `eui`, `moisture`, `tempC`, `recordedAt` | ~8000+ readings stored |
| `ZoneConfig` | `id`, `name`, `deviceId`, `lastRunAt` | |
| `ZoneGroup` | `id`, `name`, `sortOrder`, `assignedZoneIds` | |
| `DashboardCardOrder` | `cards`, `hiddenCards` | For future card reordering |

### Rate Limiting Implementation

#### SenseCAP
```swift
// Sensors fetched 2 at a time in sequential batches
for batch in sensors.chunked(into: 2) {
    await fetchBatch(batch)
}
```

#### Rachio
```swift
// 5-minute cache with NSLock for thread safety
private var cachedDevices: [RachioDevice]?
private var cacheTimestamp: Date?
private let cacheTTL: TimeInterval = 300

// Rate limit headers parsed:
// X-RateLimit-Limit: 3500
// X-RateLimit-Remaining: 3498
// X-RateLimit-Reset: 2026-03-27T00:00:00Z

// On 429: backoff until reset time (not fixed duration)
```

---

## Setup Guide

### 1. Get SenseCAP Credentials

1. Go to [sensecap.seeed.cc](https://sensecap.seeed.cc)
2. Log in to your account
3. Navigate to **Account → Access API Keys**
4. Create or copy your **API Key** and **API Secret**

### 2. Get Rachio API Key

1. Open the Rachio mobile app
2. Go to **Account → API Access** (or **More → Settings → API Access**)
3. Copy your API key

### 3. Configure RachioSense

1. Open RachioSense
2. Go to **Settings → Account**
3. Enter SenseCraft credentials → **Test Connection**
4. Enter Rachio API key → **Test Connection**

### 4. Link Sensors to Zones

1. Go to **Settings → Configuration → Sensor-Zone Links**
2. For each sensor:
   - Set a friendly **Alias** (e.g., "Tomato Bed")
   - Select the **Linked Zone** (Rachio zone that waters this sensor)
   - Enable **Auto-water** if desired

### 5. Create Zone Groups

1. Go to **Settings → Configuration → Zone Groups**
2. Create groups to organize your sensors (e.g., "Garden", "Trees", "Lawn")
3. Groups determine how graphs are organized

### 6. Adjust Thresholds

1. Go to **Settings → Configuration → Thresholds**
2. Adjust for your soil type:
   - Sandy soil: lower thresholds (dries faster)
   - Clay soil: higher thresholds (retains water)

### 7. View Your Data

1. Go to **Graphs tab** — data loads automatically
2. Pull-to-refresh for latest readings

---

## Requirements

| Requirement | Version |
|-------------|---------|
| iOS | 17.0+ |
| Xcode | 15+ |
| Swift | 6 |
| SenseCAP sensors | Any soil moisture sensor with SenseCAP account |
| Rachio controller | Any Rachio model with API access |

---

## API Reference

### SenseCAP OpenAPI

| Endpoint | Purpose | Rate Limit |
|----------|---------|------------|
| `/list_devices` | Get all sensors + expiry dates | Shared |
| `/view_latest_telemetry_data` | Current readings | Shared |
| `/list_telemetry_data` | Historical data (24h chunks) | ~50 req/min |

**Key fields from `/list_devices`:**
```json
{
  "device_eui": "2CF7F1C0627000A8",
  "device_name": "Soil Sensor #8",
  "expired_time": "2026-04-09T00:00:00.000Z"
}
```

### Rachio Public API

| Endpoint | Purpose | Rate Limit |
|----------|---------|------------|
| `/person/info` | Get person ID | 3500/day |
| `/person/{id}` | Get device IDs | 3500/day |
| `/device/{id}` | Get device + zones + schedules | 3500/day |
| `/zone/start` | Start a zone | 3500/day |
| `/zone/stop` | Stop a zone | 3500/day |

**Rate limit headers:**
```
X-RateLimit-Limit: 3500
X-RateLimit-Remaining: 3498
X-RateLimit-Reset: 2026-03-27T00:00:00Z
```

### Open-Meteo

| Endpoint | Purpose | Rate Limit |
|----------|---------|------------|
| `/v1/forecast` | 7-day weather forecast | Unlimited (free) |

---

## 🔮 Planned Features

### High Priority
- [x] **Location-based weather** — CoreLocation with fallback chain to hardcoded coordinates
- [x] **Rachio next scheduled run** — Shown on dashboard and zone rows
- [x] **Push notifications** — Full local notification system: critical/low/predictive/offline/zone/summary
- [ ] **Auto-water execution** — Toggle exists but doesn't yet trigger Rachio

### Medium Priority
- [ ] **iOS Widget** — Home screen widget showing moisture summary
- [ ] **Sensor detail history chart** — Use SwiftData readings instead of re-fetching
- [ ] **Zone group reordering** — Drag to reorder groups on Graphs tab
- [ ] **Flex schedule support** — Better weekly minutes estimate for Rachio flex schedules
- [ ] **Multiple Rachio devices** — Currently shows first device only
- [ ] **iCloud sync** — Sync settings across devices

### Nice to Have
- [ ] **Apple Watch complication** — Glanceable moisture summary
- [ ] **Siri shortcuts** — "Hey Siri, water the tomatoes for 10 minutes"
- [ ] **Historical watering log** — Correlate Rachio runs with moisture trends
- [ ] **CSV import** — Bulk import sensor aliases
- [ ] **Share graph as image** — Export for sharing

---

## 🚀 Future Enhancements

### Smart Automation
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **Predictive watering** | ML model predicts when soil will go dry based on weather + historical data | High |
| **Weather-adjusted thresholds** | Auto-lower dry threshold when rain is forecast | Medium |
| **Seasonal profiles** | Different thresholds for summer vs winter | Low |
| **Multi-zone auto-water** | Water multiple linked zones when any sensor goes critical | Medium |
| **Watering windows** | Only auto-water during specific hours (e.g., early morning) | Low |
| **Cooldown periods** | Prevent auto-water from running too frequently | Low |

### Advanced Analytics
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **Moisture trends** | Weekly/monthly trend charts with averages | Medium |
| **Water usage tracking** | Estimate gallons used per zone based on flow rate | Medium |
| **Correlation analysis** | Show how watering events affect moisture levels | High |
| **Anomaly detection** | Alert when sensor readings are unusual | High |
| **Soil health score** | Composite score based on moisture consistency | Medium |
| **Export to CSV/PDF** | Generate reports for date ranges | Low |

### User Experience
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **Onboarding wizard** | Guided setup for first-time users | Medium |
| **Quick actions** | 3D Touch / long-press shortcuts on sensor cards | Low |
| **Customizable dashboard** | Drag-to-reorder cards, hide/show sections | Medium |
| **Dark mode graphs** | Optimized colors for dark theme | Low |
| **Accessibility** | VoiceOver support, Dynamic Type | Medium |
| **Localization** | Spanish, French, German translations | Medium |

### Platform Expansion
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **iPad layout** | Multi-column layout for larger screens | Medium |
| **macOS app** | Native Mac app via Catalyst or SwiftUI | Medium |
| **Apple Watch app** | Full app with complications and glances | High |
| **Home Assistant integration** | MQTT or REST API for HA sensors | Medium |
| **Shortcuts app actions** | Expose actions for iOS Shortcuts | Low |
| **Live Activities** | Lock screen widget showing active watering | Medium |

### Integrations
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **Additional controllers** | Support for Hunter, Rain Bird, Orbit | High |
| **Additional sensors** | Support for Ecowitt, Ambient Weather | High |
| **Weather services** | Options for Weather.com, OpenWeatherMap | Low |
| **Calendar integration** | Show watering schedule in iOS Calendar | Medium |
| **HomeKit** | Expose sensors and zones to Home app | High |
| **Matter support** | Future-proof smart home standard | High |

### Backend & Sync
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **CloudKit sync** | Sync settings and data across devices | High |
| **Shared households** | Multiple users managing same garden | High |
| **Offline mode** | Full functionality without internet | Medium |
| **Background fetch** | Reliable background data refresh | Medium |
| **Push notifications via APNs** | Server-triggered alerts | High |
| **Web dashboard** | View-only web interface | High |

### Developer & Power User
| Enhancement | Description | Complexity |
|-------------|-------------|------------|
| **Debug console** | In-app log viewer | Low |
| **API playground** | Test API calls in-app | Medium |
| **Custom thresholds per sensor** | Override global thresholds | Low |
| **Webhook support** | POST to URL on events | Medium |
| **IFTTT integration** | Trigger applets on sensor events | Medium |
| **Scriptable actions** | JavaScript automation | High |

---

## 🐛 Known Issues & Technical Debt

### Active Issues

| Issue | Severity | Description |
|-------|----------|-------------|
| **Flex schedule runtime** | Low | Rachio flex schedules show estimated 1×/week (inaccurate) |
| **Zone started/stopped** | Low | Detected by polling `lastWateredDate` — not real-time; requires webhook pipeline for accuracy |
| **Background refresh cadence** | Low | iOS throttles BGAppRefresh based on battery and usage — actual intervals vary widely |

### Technical Debt

| Item | Notes |
|------|-------|
| `moistureThreshold` in SwiftData | Field kept for DB compatibility but unused — global thresholds only |
| No retry UI | API errors shown as banner but no retry button |
| Auto-water execution | Toggle and threshold exist but don't yet call Rachio |

### API Limitations

#### SenseCAP
| Limitation | Impact |
|------------|--------|
| Rate limiting | ~50 req/min; batching required |
| No push/webhook | Must poll for new data |
| 24h chunk limit | Must page through history in windows |
| Expiry only at device level | All sensors on account share same expiry |

#### Rachio
| Limitation | Impact |
|------------|--------|
| 3500 calls/day | Generous but finite; cached to minimize |
| No WebSocket | Must poll for running zone status |
| Schedule info embedded | Must fetch full device to get schedules |

---

## Troubleshooting

### "Rachio API returned HTTP 429"

**Cause:** Hit daily rate limit (3500 calls).

**Solution:** Wait until midnight UTC (5 PM MST) for reset. The app will show remaining time in the Alerts card.

**Prevention:** Don't force-quit and reopen repeatedly. The 5-minute cache prevents excessive calls in normal use.

### Sensors show "No readings yet"

**Cause:** SenseCAP credentials invalid or sensors not reporting.

**Solution:**
1. Settings → Account → Test Connection for SenseCraft
2. Verify sensors are online at sensecap.seeed.cc
3. Pull-to-refresh on Sensors tab

### Graphs are blank

**Cause:** No historical data fetched yet.

**Solution:**
1. Go to Graphs tab and wait (initial fetch takes 30-60 seconds)
2. Pull-to-refresh
3. Check Settings → Support → History API Test

### Intermittent crashes

**Possible causes:**
1. SwiftData threading issues
2. Force unwrap on nil values

**Debug:**
1. In Xcode: Edit Scheme → Run → Diagnostics → Enable Thread Sanitizer
2. Check crash logs in Window → Devices and Simulators → View Device Logs

---

## Backup Reminder

⚠️ **Settings are stored locally and will be lost if the app is deleted.**

Before uninstalling or getting a new device:

1. Go to **Settings → Data & Privacy → Backup & Restore**
2. Tap **Create Backup**
3. Save the JSON file to Files, iCloud, or AirDrop

---

## License

MIT License — see LICENSE file

---

## Changelog

### 2026-04 (Claude Refactor)

**Notification System (fully implemented):**
- Notification permission requested on first foreground launch
- Background refresh properly submitted to iOS scheduler at launch and on each background transition
- Per-sensor cooldown (default 4h) tracked in UserDefaults — no more repeated alerts while moisture stays low
- Quiet hours respected across all alert types
- Critical vs. low severity distinction ("⚠️ Critical Soil Moisture" vs. "Soil Moisture Low")
- Predictive alerts: exponential decay model predicts hours until critical/dry threshold; fires "⚠️ Going Critical Soon — ~3h" when within configurable window (default 6h)
- Sensor offline detection: fires after 3+ hours without a reading (12h cooldown)
- Zone ran detection: polling-based via Rachio `lastWateredDate` comparison
- Upcoming run alert: fires when next scheduled run is within 2 hours
- Zone Skipped alert: detects Rachio Weather Intelligence skip events within the last 30 minutes and reports reason (rain / freeze / wind) — 23h cooldown per skip ID
- Service Disconnected alert: fires when SenseCraft or Rachio hasn't been reached for 2+ hours; only fires if a prior successful connection exists; 6h cooldown per service
- Daily summary: fires once per day after configured time
- Weekly report: fires once per week on configured day
- All toggles in Settings → Notifications wired to actual code
- Settings: Alert window picker, Cooldown picker, Zone Skipped toggle (default on), Service Alerts toggle (default on)

**Code Quality (Claude Refactor):**
- `RachioAPI` converted from `final class` + manual locking to Swift `actor`
- `KeychainService.deleteAll()` fixed to also clear `rachioDeviceIds`
- `ZonesViewModel.stopAllZones()` now collects and reports per-zone errors
- `@MainActor` added to `AppState` and `ZonesViewModel`
- `SenseCraftAPI` measurement IDs replaced with named `MeasurementID` enum
- `GraphDataPrefetcher` pruning uses predicate-based `FetchDescriptor` instead of full table scan
- `WeatherAPI` force unwrap fixed; `URLSession` configured with 30s timeout; `WeatherError` enriched
- All `print()` calls replaced with `os.Logger`

### 2026-03-26

**New Features:**
- Subscription expiry tracking from SenseCAP API
- Dashboard shows sensors expiring within configurable window (default 30 days)
- Sensor detail shows expiry countdown
- Rachio API rate limit tracking with visual countdown
- System Status shows API calls remaining (e.g., 3498/3500)
- Configurable subscription alert threshold (7-90 days)

**Dashboard Changes:**
- Moved WEATHER card to top of dashboard
- Renamed MOISTURE card to ALERTS
- ALERTS only shows Critical/Dry/High/Expiring sensors (no OK count)
- Removed "See All" link

**API Improvements:**
- 5-minute cache for Rachio getDevices() with thread-safe locking
- Cached personId and deviceIds to reduce API calls (3 calls → 1 on cache hit)
- Rate limit backoff uses server-provided reset time (not fixed duration)
- Parse X-RateLimit-Limit/Remaining/Reset headers
