# RachioSense

An iOS app that bridges **SenseCAP soil moisture sensors** with the **Rachio irrigation controller**, giving you rich historical graphs, smart watering automation, and full control over your garden's health.

---

## Screenshots

*(Add screenshots here)*

---

## Features Overview

- 📊 **Graphs** — Historical moisture data with configurable thresholds
- 💧 **Sensors** — Live readings with status filters
- 🌿 **Zones** — Rachio zone control and monitoring
- ⚙️ **Settings** — Comprehensive configuration options

---

## Complete UI Reference

### Tab Bar (Bottom Navigation)

| Tab | Icon | Description |
|-----|------|-------------|
| **Dashboard** | `house.fill` | Overview cards showing moisture summary, zones, weather |
| **Graphs** | `chart.line.uptrend.xyaxis` | Historical moisture graphs organized by zone groups |
| **Sensors** | `sensor.fill` | List of all soil sensors with live readings |
| **Zones** | `drop.fill` | Rachio irrigation zones with run controls |
| **Settings** | `gearshape.fill` | All configuration options |

---

## 📊 Graphs Tab

The Graphs tab displays historical moisture data in card format, organized by zone groups.

### Graph Card Components

| Element | Description |
|---------|-------------|
| **Card Title** | Zone group name (e.g., "Raised Beds", "Citrus Trees") |
| **Period Picker** | `1d` `2d` `4d` `5d` `1w` buttons in top-right corner |
| **Chart Area** | Line graph showing moisture % over time |
| **Threshold Lines** | Three horizontal dashed lines (see below) |
| **Legend** | Colored squares with sensor names below chart |
| **X-Axis Labels** | Date labels in `M/D` format (e.g., "3/24"), centered on grid lines |
| **Y-Axis Labels** | Moisture percentage (e.g., "20%", "30%", "40%") |

### Period Picker Buttons

| Button | Range | Behavior |
|--------|-------|----------|
| `1d` | 1 day | Shows last 24 hours |
| `2d` | 2 days | Shows last 48 hours |
| `4d` | 4 days | Shows last 4 days (default) |
| `5d` | 5 days | Shows last 5 days |
| `1w` | 1 week | Shows last 7 days |

**Interactions:**
- **Single tap** — Changes only THIS card's time range
- **Double tap** — Syncs ALL cards to the same time range (shows "Synced" badge briefly)

### Threshold Lines (Dashed Horizontal Lines)

| Color | Threshold | Meaning |
|-------|-----------|---------|
| 🔴 Red | Auto-water | Below this = irrigation triggers automatically (if enabled) |
| 🟡 Yellow/Orange | Dry | Below this = soil is getting dry, needs attention |
| 🔵 Blue | High | Above this = soil is well-watered |

*Threshold values are configured globally in Settings → Configuration → Thresholds*

### Graph Interactions

| Action | Result |
|--------|--------|
| **Pull down** | Refreshes data (fetches only new readings since last fetch) |
| **Scroll** | Scroll to see more graph cards |

---

## 💧 Sensors Tab

Lists all SenseCAP soil moisture sensors with live readings and filtering.

### Filter Chips (Horizontal Scroll at Top)

| Chip | Icon | Color | Filter Criteria |
|------|------|-------|-----------------|
| **All** | — | Accent | Shows all sensors |
| **Critical** | ⚠️ triangle | Red | Moisture < auto-water threshold |
| **Dry** | ❗ circle | Yellow | Moisture between auto-water and dry threshold |
| **OK** | ✓ circle | Green | Moisture between dry and high threshold |
| **High** | 💧 drop | Blue | Moisture > high threshold |

**Additional Group Chips** (if zone groups exist):
- `All Groups` — Show sensors from all groups
- `[Group Name]` — Filter to sensors linked to zones in that group

### Sensor Row Components

| Element | Description |
|---------|-------------|
| **Status Dot** | Colored circle (red/yellow/green/blue) based on moisture level |
| **Sensor Name** | Display name (alias if set, otherwise original name) |
| **Original Name** | Shown in smaller text if alias is set |
| **Moisture %** | Current reading (e.g., "32%") |
| **Temperature** | Current temp (e.g., "72°F" or "22°C") |
| **Last Updated** | Relative time (e.g., "5m ago") |
| **Moisture Bar** | Horizontal colored bar showing moisture level |
| **Threshold Indicator** | Shows "Auto-water: 20%" or "Dry alert: 25%" |
| **Auto Badge** | 💧 "Auto" label if auto-water is enabled |

### Sensor Row Interactions

| Action | Result |
|--------|--------|
| **Tap row** | Opens Sensor Detail view |
| **Pull down** | Refreshes all sensor readings |

### Sensor Detail View

| Section | Contents |
|---------|----------|
| **Hero Card** | Large moisture %, temperature, trend indicator |
| **Zone Link** | Linked Rachio zone name (if any) |
| **Automation** | Auto-water status, threshold display |
| **History Chart** | Mini chart with period picker |
| **Quick Actions** | "Run Zone" button (if linked) |

---

## 🌿 Zones Tab

Lists all Rachio irrigation zones with status and controls.

### Zone Row Components

| Element | Description |
|---------|-------------|
| **Zone Name** | Rachio zone name |
| **Status Badge** | "Idle", "Running", or "Scheduled" |
| **Last Run** | When zone last ran (e.g., "Yesterday at 6:00 AM") |
| **Duration** | Default run time |

### Zone Row Interactions

| Action | Result |
|--------|--------|
| **Tap row** | Opens Zone Detail view |
| **Pull down** | Refreshes zone status from Rachio |

### Zone Detail View

| Section | Contents |
|---------|----------|
| **Status Card** | Current status, time remaining if running |
| **Run Controls** | Duration picker + "Start" button |
| **Linked Sensors** | List of sensors linked to this zone |
| **Schedule** | Upcoming scheduled runs |
| **History** | Recent run history |

### Zone Control Buttons

| Button | Action |
|--------|--------|
| **Start** | Starts zone for selected duration |
| **Stop** | Stops zone immediately (shown when running) |
| **Duration Picker** | Select run time (5, 10, 15, 20, 30 min) |

---

## ⚙️ Settings Tab

Comprehensive configuration organized into sections.

### Account Section

#### SenseCraft Credentials
| Field | Description |
|-------|-------------|
| **API Key** | Your SenseCAP API key |
| **API Secret** | Your SenseCAP API secret |
| **Test Connection** | Button to verify credentials work |
| **Status Badge** | "Connected" (green) or "Not Connected" (red) |

#### Rachio Credentials
| Field | Description |
|-------|-------------|
| **API Key** | Your Rachio API key |
| **Test Connection** | Button to verify credentials work |
| **Status Badge** | "Connected" (green) or "Not Connected" (red) |

---

### Configuration Section

#### Sensor-Zone Links

Links soil sensors to Rachio irrigation zones.

**List View:**
| Element | Description |
|---------|-------------|
| **Linked Sensors** | Section showing sensors with zone links |
| **Unlinked Sensors** | Section showing sensors without links |
| **Sensor Row** | Name, original name (if aliased), linked zone, auto badge |

**Detail View (tap a sensor):**
| Field | Description |
|-------|-------------|
| **Alias** | Custom display name for sensor |
| **Original Name** | Read-only, from SenseCAP |
| **EUI** | Device identifier (read-only) |
| **Zone Picker** | Dropdown to select linked Rachio zone |
| **Auto-water Toggle** | Enable/disable automatic irrigation |
| **Show in Graphs Toggle** | Hide sensor from all graphs |
| **Remove Link** | Button to unlink sensor from zone |

#### Zone Groups

Organize zones into groups for combined graph display.

| Control | Description |
|---------|-------------|
| **Add Group** | "+" button to create new group |
| **Group Name** | Editable text field |
| **Assigned Zones** | Checkboxes to assign zones to group |
| **Sort Order** | Drag handles to reorder groups |
| **Delete** | Swipe left to delete group |

#### Thresholds

Global moisture thresholds used throughout the app.

| Slider | Default | Description |
|--------|---------|-------------|
| **High Level** | 40% | 🔵 Blue — Moisture above this is "well watered" |
| **Dry Level** | 25% | 🟡 Yellow — Below this triggers dry alerts |
| **Auto-water Trigger** | 20% | 🔴 Red — Below this starts auto-irrigation |

| Control | Description |
|---------|-------------|
| **Slider** | Drag to adjust threshold (shows % value) |
| **Color** | Slider/value colored to match threshold level |
| **Preview** | Live preview showing sample values with colors |
| **Reset to Defaults** | Button to restore default values |

#### Notifications
| Toggle | Description |
|--------|-------------|
| **Dry Alerts** | Notify when sensor drops below dry threshold |
| **Critical Alerts** | Notify when sensor drops below auto-water threshold |
| **Watering Started** | Notify when auto-water activates |
| **Watering Complete** | Notify when zone finishes running |

#### Weather Integration
| Toggle | Description |
|--------|-------------|
| **Rain Skip** | Skip scheduled watering when rain is forecast |
| **Freeze Skip** | Skip watering when freeze is forecast |

---

### Display Section

#### Appearance
| Control | Options | Description |
|---------|---------|-------------|
| **Theme** | System / Light / Dark | App color scheme |
| **Accent Color** | Color picker | Primary accent color |
| **Haptics** | Toggle | Enable/disable haptic feedback |
| **Animations** | Toggle | Enable/disable UI animations |

#### Graph Settings
| Control | Description |
|---------|-------------|
| **Default Period** | Default time range for graphs (1d–1w) |
| **Y-Axis Minimum** | Bottom of graph scale (default 15%) |
| **Y-Axis Maximum** | Top of graph scale (default 45%) |

#### Sensor Labels
| Control | Options |
|---------|---------|
| **Primary Label** | Name / EUI / Group |
| **Secondary Label** | Moisture+Temp / Moisture only / Temp only / None |
| **Status Indicator** | Colored dot / Colored background / None |

#### Units
| Control | Options |
|---------|---------|
| **Temperature** | Fahrenheit (°F) / Celsius (°C) |

---

### Data & Privacy Section

#### Backup & Restore
| Button | Description |
|--------|-------------|
| **Create Backup** | Exports all settings as JSON file |
| **Restore from Backup** | Imports settings from JSON file |

*Backup includes: sensor aliases, zone links, groups, thresholds, display settings*
*Backup excludes: API credentials (security), sensor readings (too large)*

#### Export Data
| Option | Description |
|--------|-------------|
| **Format** | CSV or JSON |
| **Date Range** | Last 7 days / Last 30 days / All / Custom |
| **Export** | Generates and shares file |

#### Local Storage
| Display | Description |
|---------|-------------|
| **Readings Stored** | Number of sensor readings in database |
| **Date Range** | Oldest to newest reading dates |
| **Storage Used** | Approximate database size |
| **Clear Old Data** | Button to delete readings older than 7 days |

---

### Support Section

#### Diagnostics

Debugging tools for troubleshooting.

**API Latency:**
| Row | Description |
|-----|-------------|
| **SenseCraft API** | Response time in ms |
| **Rachio API** | Response time in ms |
| **Measure Latency** | Button to test both APIs |

**Sync Status:**
| Row | Description |
|-----|-------------|
| **Last Sync** | When data was last fetched |
| **Sensors** | Number of sensor configs |
| **Zones** | Number of zone configs |
| **Readings Stored** | Total readings in database |

**History API Test:**
| Control | Description |
|---------|-------------|
| **Test History Endpoint** | Fetches 7 days for first sensor |
| **Result Display** | Shows success/failure, reading count, sample data |
| **Copy** | Copy raw result to clipboard |

**Actions:**
| Button | Description |
|--------|-------------|
| **Copy Debug Log** | Copies full diagnostic report to clipboard |
| **Reset Graph Cache** | Deletes all readings, forces full re-fetch |

#### Help / FAQ
Common questions and answers about app usage.

#### Contact Support
| Field | Description |
|-------|-------------|
| **Email** | Pre-filled support email |
| **Include Diagnostics** | Toggle to attach diagnostic report |

#### About
App version, build number, acknowledgments, links.

---

### Reset Section

**Individual Reset Options:**
| Button | What it clears |
|--------|---------------|
| **Reset SenseCraft** | SenseCraft API credentials only |
| **Reset Rachio** | Rachio API credentials only |
| **Clear Sensor Links** | Zone links and auto-water settings |
| **Reset Settings** | Display preferences to defaults |

**Full Reset:**
| Button | Description |
|--------|-------------|
| **Reset Everything** | Clears ALL data, returns to onboarding |

*All reset actions require confirmation dialog*

---

## Data Flow Architecture

```
SenseCAP API
    ↓
GraphDataPrefetcher (smart fetch with rate limiting)
    ↓
SwiftData (local store — up to 7 days)
    ↓
GraphsViewModel / SensorsViewModel
    ↓
UI Views (charts, lists, cards)
```

### Smart Data Fetching

| Trigger | Fetch Behavior |
|---------|----------------|
| **App launch** | Fetch gap since last reading (incremental) |
| **Pull-to-refresh (Graphs)** | Fetch gap since last reading |
| **Pull-to-refresh (Sensors)** | Fetch latest readings only |
| **First launch / Reset cache** | Full 7-day history |

### Rate Limiting Protection
- Sensors fetched in batches of 2 (not all at once)
- 30-second cooldown between full refreshes
- Automatic backoff on HTTP 429 errors

---

## Key Services

| File | Purpose |
|------|---------|
| `SenseCraftAPI.swift` | SenseCAP HTTP client — devices, readings, history |
| `RachioAPI.swift` | Rachio REST client — devices, zones, schedules, control |
| `GraphDataPrefetcher.swift` | Smart historical fetch with dedup and rate limiting |
| `KeychainService.swift` | Secure credential storage |
| `BackgroundRefreshManager.swift` | iOS background task handling |

---

## Data Models (SwiftData)

| Model | Key Fields |
|-------|------------|
| `SensorConfig` | id, name, alias, eui, linkedZoneId, autoWaterEnabled, isHiddenFromGraphs |
| `ZoneConfig` | id, name, deviceId, lastRunAt |
| `SensorReading` | eui, moisture, tempC, recordedAt |
| `ZoneGroup` | id, name, sortOrder, assignedZoneIds |
| `DashboardCardOrder` | cards, hiddenCards |

---

## Setup Guide

1. **Get SenseCAP credentials:**
   - Go to [sensecap.seeed.cc](https://sensecap.seeed.cc)
   - Account → Access API Keys
   - Copy API Key and API Secret

2. **Get Rachio API key:**
   - Open Rachio app
   - Account → API Access
   - Copy API key

3. **Configure RachioSense:**
   - Settings → Account → enter both credentials
   - Tap "Test Connection" to verify

4. **Import sensors:**
   - Go to Sensors tab
   - Sensors load automatically from SenseCAP

5. **Link sensors to zones:**
   - Settings → Configuration → Sensor-Zone Links
   - Tap each sensor → select its Rachio zone

6. **Configure thresholds:**
   - Settings → Configuration → Thresholds
   - Adjust levels for your soil type

7. **View graphs:**
   - Go to Graphs tab
   - Historical data loads automatically

---

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 6
- SenseCAP account with soil moisture sensors
- Rachio irrigation controller

---

## Backup Reminder

Settings are stored locally and **will be lost if the app is deleted**. 

Before uninstalling or resetting:
1. Settings → Data & Privacy → Backup & Restore
2. Create Backup
3. Save the JSON file somewhere safe

---

## License

MIT License — see LICENSE file
