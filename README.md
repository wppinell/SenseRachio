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

### Pull-to-Refresh Behavior

**Smart Incremental Fetch:**
1. Calculates hours since last stored reading per sensor
2. Fetches only the gap (not full 7 days)
3. Example: If last reading was 2h ago, fetches 2h of data

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
| **Status label** | Only shown for Critical/Dry/High (not OK) |
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

| Setting | Description |
|---------|-------------|
| **Dry Alerts** | Push when sensor drops below dry threshold |
| **Critical Alerts** | Push when sensor drops below auto-water threshold |
| **Sensor Offline** | Push when sensor stops reporting |
| **Zone Started/Stopped** | Push for manual zone runs |
| **Daily Summary** | Configurable hour for daily digest |

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
                    │  • startZone()         │    + NSLock for
                    │  • stopZone()          │    concurrent calls
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
- [ ] **Location-based weather** — Use device GPS or user-set location instead of hardcoded Phoenix
- [ ] **Rachio next scheduled run** — Show "Next run: Tomorrow 6:00 AM" on dashboard and zone rows
- [ ] **Auto-water execution** — Actually trigger Rachio zone when sensor goes critical
- [ ] **Push notifications** — Local alerts for critical sensors and auto-water events

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

## 🐛 Known Issues & Technical Debt

### Active Issues

| Issue | Severity | Description |
|-------|----------|-------------|
| **SwiftData threading** | Medium | `ModelContext` used off main queue in BackgroundRefreshManager — should use `ModelActor` |
| **Weather location hardcoded** | Medium | Open-Meteo coordinates fixed at Phoenix, AZ |
| **Flex schedule runtime** | Low | Rachio flex schedules show estimated 1×/week (inaccurate) |
| **Background refresh untested** | Low | `BGAppRefreshTask` registered but iOS delivery is unpredictable |

### Technical Debt

| Item | Notes |
|------|-------|
| `moistureThreshold` in SwiftData | Field kept for DB compatibility but unused — global thresholds only |
| Duplicate API calls | SensorsViewModel and DashboardViewModel both fetch live readings on load |
| No retry UI | API errors shown as banner but no retry button |
| Debug print statements | `[RachioAPI]`, `[Prefetch]`, etc. should be removed or made conditional |

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
