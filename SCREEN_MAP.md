# RachioSense Screen Map

Complete implementation guide for all screens.

```
RachioSense App
│
├── TAB: Home (house.fill)
│   └── Dashboard
│       ├── Header: "🌱 RachioSense" + device picker dropdown
│       ├── MOISTURE Card
│       │   ├── Section header + "See All →" link
│       │   ├── Sensor dots with % values (top 4)
│       │   └── 24h trend sparkline
│       ├── ZONES Card
│       │   ├── Section header + "See All →" link
│       │   └── Zone status rows (name, Idle/Running + duration)
│       └── WEATHER Card
│           ├── Current temp + conditions
│           ├── Rain forecast warning
│           └── Skip recommendation
│
├── TAB: Sensors (leaf.fill)
│   ├── Header: "Sensors" + filter chips (All | Dry | OK)
│   ├── [If grouping enabled] Group headers with count
│   └── Sensor List
│       └── Each Sensor Row
│           ├── Status dot (🟢🟡🔴)
│           ├── Name
│           ├── Moisture % · Temp · Last updated
│           └── Chevron → Sensor Detail
│               ├── Header: sensor name + status
│               ├── Current readings (moisture, temp)
│               ├── History chart (configurable period)
│               ├── Linked zone (if any)
│               ├── Group assignment
│               └── [Run Linked Zone] button
│
├── TAB: Zones (drop.fill)
│   ├── Header: "Zones"
│   ├── [If grouping enabled] Group headers with count
│   ├── Zone List
│   │   └── Each Zone Row
│   │       ├── 💧 icon
│   │       ├── Name
│   │       ├── Status (Idle / Running + time remaining)
│   │       ├── Today's usage (Xm today)
│   │       └── Chevron → Zone Detail
│   │           ├── Header: zone name + status
│   │           ├── [Start Zone] / [Stop Zone] button
│   │           ├── Duration picker
│   │           ├── Run history (last 7 days)
│   │           ├── Linked sensors (if any)
│   │           ├── Group assignment
│   │           └── Schedule info
│   └── [STOP ALL ZONES] button (bottom, destructive)
│
└── TAB: Settings (gearshape.fill)
    │
    ├── ACCOUNT
    │   ├── SenseCraft → SenseCraftAccountView
    │   │   ├── Status badge (Connected/Disconnected + sensor count)
    │   │   ├── API Key field (secure)
    │   │   ├── API Secret field (secure)
    │   │   ├── Account email (read-only when connected)
    │   │   ├── [Test Connection] button
    │   │   └── [Sign Out] button (destructive)
    │   └── Rachio → RachioAccountView
    │       ├── Status badge (Connected/Disconnected + zone count)
    │       ├── API Key field (secure)
    │       ├── Controller info card
    │       │   ├── Model
    │       │   ├── Serial number
    │       │   ├── Firmware version
    │       │   └── WiFi signal strength
    │       ├── Account email (read-only when connected)
    │       ├── [Test Connection] button
    │       ├── [View in Rachio App] button (opens Rachio app)
    │       └── [Sign Out] button (destructive)
    │
    ├── CONFIGURATION
    │   ├── Sensor-Zone Links → SensorZoneLinksView
    │   │   ├── LINKED section
    │   │   │   └── Each: Sensor name → Zone name, Auto-water toggle
    │   │   │       └── Tap → LinkDetailView
    │   │   │           ├── Sensor picker
    │   │   │           ├── Zone picker
    │   │   │           ├── Auto-water toggle
    │   │   │           ├── Auto-water threshold slider
    │   │   │           └── [Delete Link] button
    │   │   ├── UNLINKED section
    │   │   │   └── Each: Sensor name + "Tap to link"
    │   │   └── [Create New Link] button
    │   │
    │   ├── Thresholds → ThresholdsView
    │   │   ├── Dry level slider (default 25%)
    │   │   │   └── Live preview: 🔴 below this
    │   │   ├── Low level slider (default 40%)
    │   │   │   └── Live preview: 🟡 below this
    │   │   ├── Auto-water trigger slider (default 20%)
    │   │   │   └── Triggers linked zone when below
    │   │   └── [Reset to Defaults] button
    │   │
    │   ├── Notifications → NotificationsView
    │   │   ├── ALERTS section
    │   │   │   ├── Dry alerts toggle
    │   │   │   ├── Low alerts toggle
    │   │   │   └── Sensor offline toggle
    │   │   ├── ZONE ACTIVITY section
    │   │   │   ├── Zone started toggle
    │   │   │   ├── Zone stopped toggle
    │   │   │   └── Schedule run toggle
    │   │   ├── SUMMARIES section
    │   │   │   ├── Daily summary toggle + time picker
    │   │   │   └── Weekly report toggle + day picker
    │   │   └── QUIET HOURS section
    │   │       ├── Enabled toggle
    │   │       └── Time range (start/end pickers)
    │   │
    │   ├── Grouping → GroupingView
    │   │   ├── SENSORS section
    │   │   │   └── Picker: None / Group Name
    │   │   ├── ZONES section
    │   │   │   └── Picker: None / Group Name
    │   │   └── Manage Groups → ManageGroupsView
    │   │       ├── List of groups
    │   │       │   └── Each → EditGroupView
    │   │       │       ├── Name field
    │   │       │       ├── Icon picker (emoji grid)
    │   │       │       ├── SENSORS section (checkboxes)
    │   │       │       ├── ZONES section (checkboxes)
    │   │       │       └── [Delete Group] button
    │   │       └── [Add Group] button
    │   │
    │   ├── Refresh Rate → RefreshRateView
    │   │   ├── FOREGROUND section
    │   │   │   └── Picker: 15s / 30s / 1m / 5m
    │   │   ├── BACKGROUND section
    │   │   │   └── Picker: 10m / 15m / 30m / 1h
    │   │   └── Push notifications toggle
    │   │
    │   └── Weather Integration → WeatherIntegrationView
    │       ├── SOURCE section
    │       │   └── Picker: Rachio / National Weather / Open-Meteo
    │       ├── SMART SKIPS section
    │       │   ├── Rain skip toggle + threshold (inches)
    │       │   ├── Freeze skip toggle + threshold (°F)
    │       │   ├── Wind skip toggle + threshold (mph)
    │       │   └── Saturation skip toggle + threshold (%)
    │       └── FORECAST LOOKAHEAD section
    │           └── Picker: 24h / 48h / 72h
    │
    ├── DISPLAY
    │   ├── Appearance → AppearanceView
    │   │   ├── THEME section
    │   │   │   └── Picker: Light / Dark / System
    │   │   ├── ACCENT COLOR section
    │   │   │   └── Color swatches: Blue / Green / Purple / Orange / Leaf
    │   │   ├── ANIMATIONS toggle
    │   │   ├── HAPTICS toggle
    │   │   └── ICON STYLE section
    │   │       └── Picker: Filled / Outlined
    │   │
    │   ├── Units → UnitsView
    │   │   ├── Temperature: °F / °C
    │   │   ├── Moisture: % / Raw (0-1000)
    │   │   ├── Duration: Minutes / Hours:Minutes / Seconds
    │   │   └── Volume: Gallons / Liters
    │   │
    │   ├── Dashboard Layout → DashboardLayoutView
    │   │   ├── CARDS section (drag to reorder)
    │   │   │   ├── ≡ Moisture (toggle visibility)
    │   │   │   ├── ≡ Zones (toggle visibility)
    │   │   │   ├── ≡ Weather (toggle visibility)
    │   │   │   ├── ≡ History (toggle visibility)
    │   │   │   └── ≡ Schedule (toggle visibility)
    │   │   ├── TREND CHART PERIOD
    │   │   │   └── Picker: 6h / 12h / 24h / 7d
    │   │   └── Quick actions on cards toggle
    │   │
    │   └── Sensor Labels → SensorLabelsView
    │       ├── PRIMARY LINE
    │       │   └── Picker: Name / EUI / Group
    │       ├── SECONDARY LINE
    │       │   └── Picker: Moisture+Temp / Moisture only / Last updated / Group
    │       ├── STATUS INDICATOR
    │       │   └── Picker: Colored dot / Colored background / None
    │       └── PREVIEW card (live example)
    │
    ├── DATA & PRIVACY
    │   ├── Local Storage → LocalStorageView
    │   │   ├── USAGE section
    │   │   │   ├── Sensor readings: X records · Y MB
    │   │   │   ├── Zone run history: X records · Y MB
    │   │   │   └── Configuration: X KB
    │   │   ├── HISTORY RETENTION
    │   │   │   └── Picker: 7d / 30d / 90d / 1y / Forever
    │   │   ├── [Clear old readings] button
    │   │   └── [Optimize database] button
    │   │
    │   ├── Export Data → ExportDataView
    │   │   ├── FORMAT section
    │   │   │   └── Picker: CSV / JSON / SQLite
    │   │   ├── DATE RANGE section
    │   │   │   └── Picker: 7d / 30d / All / Custom
    │   │   ├── INCLUDE section (toggles)
    │   │   │   ├── Sensor readings
    │   │   │   ├── Zone history
    │   │   │   ├── Settings
    │   │   │   └── Credentials
    │   │   ├── DESTINATION section
    │   │   │   └── Picker: Files / Share / AirDrop
    │   │   └── [Export Now] button
    │   │
    │   └── Privacy → PrivacyView
    │       ├── PERMISSIONS section
    │       │   ├── Location → shows status, opens Settings
    │       │   ├── Notifications → shows status, opens Settings
    │       │   └── Background Refresh → shows status, opens Settings
    │       ├── DATA COLLECTION section
    │       │   ├── Analytics toggle
    │       │   └── Crash reports toggle
    │       └── DELETE MY DATA section
    │           ├── [Request data export] button
    │           └── [Delete all my data] button (destructive + confirmation)
    │
    ├── SUPPORT
    │   ├── Help & FAQ → HelpFAQView (or opens web)
    │   ├── Contact Support → ContactSupportView (email composer)
    │   ├── Diagnostics → DiagnosticsView
    │   │   ├── CONNECTION STATUS section
    │   │   │   ├── SenseCraft API: ✓ Xms latency
    │   │   │   ├── Rachio API: ✓ Xms latency
    │   │   │   └── Weather API: ✓ Xms latency
    │   │   ├── SYNC STATUS section
    │   │   │   ├── Last successful: X ago
    │   │   │   ├── Sensors refreshed: X of Y
    │   │   │   └── Zones refreshed: X of Y
    │   │   ├── ERRORS (Last 24h) section
    │   │   │   └── List or "None"
    │   │   ├── [Copy Debug Log] button
    │   │   └── [Send to Support] button
    │   └── About → AboutView
    │       ├── App icon
    │       ├── Version X.X.X
    │       ├── Build number (XX)
    │       ├── Copyright © 2026 Pinello
    │       └── [Open Source Licenses] → LicensesView
    │
    └── RESET
        ├── SenseCraft → confirmation sheet
        │   ├── Clear sensor cache
        │   ├── Clear credentials
        │   └── Full reset (cache + credentials + sensor configs)
        ├── Rachio → confirmation sheet
        │   ├── Clear zone cache
        │   ├── Clear credentials
        │   └── Full reset (cache + credentials + zone configs)
        ├── App Data → confirmation sheet
        │   ├── Clear all cache
        │   ├── Clear sensor-zone links
        │   └── Reset settings to defaults
        └── All → confirmation sheet (destructive)
            └── Erases everything, returns to fresh state
```

## Design System

- **Background**: #F5F7FA (light gray)
- **Cards**: White with subtle shadow, 12pt corner radius
- **Primary accent**: #0066FF (blue)
- **Status colors**: Green (#22C55E) good, Yellow warning, Red alert
- **Typography**: SF Pro
- **Tab icons**: house.fill, leaf.fill, drop.fill, gearshape.fill
