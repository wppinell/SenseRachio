# RachioSense — Suggestions & Roadmap Notes

This file captures architectural suggestions and feature ideas specific to the current state of the codebase, supplementing the Planned Features and Future Enhancements sections in the README.

---

## ✅ Code Reviews — April 2026 (All Resolved)

All 9 issues found across two review passes have been fixed. See git log for full details.

| # | Severity | File | Issue | Status |
|---|----------|------|-------|--------|
| 1 | Bug | `RachioAPI.swift` | ISO8601 rate-limit reset parsing fails on fractional-second timestamps | ✅ Fixed |
| 2 | Bug | `LiveReadingsCache.swift` | `hiddenEuis` silently ignored for coalesced callers | ✅ Fixed |
| 3 | Bug | `BackgroundRefreshManager.swift` | Rachio success timestamp written before all API calls complete | ✅ Fixed |
| 4 | Bug | `WeatherAPI.swift` | Daily forecast loop crashes if any array is shorter than `dates` | ✅ Fixed |
| 5 | Bug | `SensorsViewModel.swift` | Duplicate `SensorReading` inserts on every foreground refresh | ✅ Fixed |
| 6 | Bug | `NotificationsSettingsView.swift` | "Zone Started" toggle wired to no implementation | ✅ Removed |
| 7 | Fragile | `LocationManager.swift` | Timeout task unretained — could resume wrong continuation | ✅ Fixed |
| 8 | Design | `BackgroundRefreshManager.swift` | `getDevices()` called twice per cycle | ✅ Fixed |
| 9 | Design | `BackgroundRefreshManager.swift` | `SensorSummaryData.driest` was a named tuple | ✅ Fixed |

**Remaining known data-quality note:** `LiveReadingsCache` stores readings with `recordedAt = Date()` (fetch time), not the sensor's actual measurement time, because SenseCraft's `/view_latest_telemetry_data` endpoint returns no timestamp. Dedup fix (#5) prevents duplicate rows; the timestamp issue remains until SenseCraft exposes measurement timestamps.

---

## 🔴 High Priority — Bugs & Technical Debt

### ✅ Graphs: Complete 7-Day History with Per-Sensor Coverage — COMPLETED
**Files:** `Services/GraphDataPrefetcher.swift`, `Services/SenseCraftAPI.swift`, `Views/Graphs/SensorGraphCard.swift`, `Views/Graphs/GraphsView.swift`
- Coverage check is now per-sensor: detects any sensor missing 7-day history and triggers full re-fetch
- Sequential chunk fetching (1s delay, up to 5 retries) eliminates silent 429 failures
- `SensorGraphCard` receives `readingsByEUI: [String: [SensorReading]]` directly — SwiftUI now reactively updates charts as data arrives
- Bad readings (moisture outside 0–100%) filtered and purged from SwiftData
- Linear interpolation replaces catmullRom to avoid overshoot on watering spikes
- Y-axis auto-scales to fit all sensor data; never clips lines

### ✅ Zones: Sort Tiles — COMPLETED
**File:** `Views/Zones/ZonesView.swift`, `Services/RachioAPI.swift`
Sort picker (↑↓) in Zones toolbar, persisted via `AppStorage`. Options:
- **Moisture** (default) — driest zones first
- **Name** — A→Z
- **Next Run** — soonest first, using same schedule logic as zone card display
- **Last Watered** — most recently watered first
- **Weekly Watering** — most total weekly minutes first
`nextRunDate(forZone:)` helper added to `RachioDevice` extension for shared use.

### ✅ Sensors: Hide "Critical" Badge on Disabled Sensors — COMPLETED
**File:** `Views/Sensors/SensorRowView.swift`
Disabled (hidden-from-graphs) sensors no longer show Critical/Dry/High status badges, which was misleading since they're inactive.

### ✅ Fix Duplicate API Calls on Load — COMPLETED
**File:** `Services/LiveReadingsCache.swift` (NEW)
Both ViewModels now use a shared `LiveReadingsCache` actor that coalesces sensor reading fetches. One fetch, one source of truth with 60-second TTL.

### ✅ Fix SwiftData Threading — COMPLETED
**File:** `Background/BackgroundRefreshManager.swift`
Converted to use `@ModelActor` (`BackgroundModelActor`) for thread-safe SwiftData access in background tasks. No more `ModelContext` used off the main queue.

### ✅ Fix Hardcoded Phoenix Weather Location — COMPLETED
**Files:** `Services/LocationManager.swift` (NEW), `ViewModels/DashboardViewModel.swift`, `Info.plist`
Now uses `CoreLocation` via `LocationManager.shared.getLocation()`. Falls back to user-configured location in Settings if permission denied, then to Phoenix as last resort. Added `NSLocationWhenInUseUsageDescription` to Info.plist.

### ✅ Remove Debug Print Statements — COMPLETED
**Files:** All service and ViewModel files.
Replaced all `print()` calls with `os.Logger` for proper production logging, including `NotificationService.swift` (added April 2026).

### ✅ Claude Refactor — COMPLETED (April 2026)
Full code review, refactor, and bug fixes. Key changes:
- `RachioAPI` converted from `final class` + manual locking to `actor` — all mutable state now compiler-enforced thread-safe
- `KeychainService.deleteAll()` fixed to also clear `rachioDeviceIds` (bug: stale IDs persisted after reset)
- `ZonesViewModel.stopAllZones()` now collects and reports errors per zone
- `@MainActor` added to `AppState` and `ZonesViewModel`; `DispatchQueue.main.async` boilerplate removed
- `SenseCraftAPI` measurement IDs replaced with named `MeasurementID` enum
- `GraphDataPrefetcher` pruning now uses predicate-based `FetchDescriptor` instead of full table scan
- `WeatherAPI` force unwrap fixed, configured `URLSession` added, `WeatherError` enriched with context
- Full `CODE_REVIEW.md` added with findings, refactoring notes, and test case recommendations

---

## 🟡 Medium Priority — Architecture Improvements

### SenseCraft WebSocket for Foreground Sensor Updates
**Current state:** Sensor readings are fetched via REST polling on a timer. `LiveReadingsCache` has a 60-second TTL, so the app is at best 60 seconds behind whatever SenseCraft last received.
**Context:** Sensors are configured to transmit every 10 minutes. SenseCraft buffers each transmission and exposes it over both REST and WebSocket.

**Target:** Open a WebSocket connection to the SenseCraft API when the app enters the foreground, and close it on background. Each incoming packet updates `LiveReadingsCache` and triggers a UI refresh — so the reading appears within seconds of the sensor transmitting rather than waiting for the next poll cycle.

**Scope:**
- Foreground only — background refresh continues to use the existing REST + `BGAppRefreshTask` path
- No change to `LiveReadingsCache` interface; WebSocket handler calls the same update path as the poller
- Eliminates the scenario where the app is open but showing data that's up to a full sensor interval stale

**Why medium and not low:** With 10-minute sensor intervals, the REST poller is adequate most of the time. But the WebSocket ensures you never miss a packet — if the poller fires between transmissions you get the cached value, whereas the WebSocket delivers the reading the instant it arrives regardless of timer alignment. Most noticeable when watching a zone run and waiting for the first moisture uptick.

### Implement Rachio Webhook → APNs Pipeline
**Current state:** Zone running status is polled. There is no real-time event delivery.
**Target architecture (already designed):**
```
Rachio Webhook → Cloudflare Worker → APNs → iOS app
```
This enables:
- Real-time zone started/stopped notifications
- Accurate "currently running" status in the Zones tab without polling
- Auto-water confirmation delivery

**Rachio webhook events to handle:**
- `ZONE_STATUS` (running/not running)
- `DEVICE_STATUS`
- `SCHEDULE_STATUS`
- `RAIN_DELAY`

### ✅ Add Rachio Run History Overlay on Graphs — COMPLETED
**Endpoint:** `GET /device/{id}/event`
Watering events are fetched and overlaid as teal vertical bands on each graph card, matched by zone name. Events under 5 minutes are excluded.

### Expose Rachio Flex Daily Zone Parameters
**Endpoint:** `GET /device/{id}` → `zones[]`
Zone objects contain agronomic parameters that drive Flex Daily scheduling. These are currently unused.
**Fields to surface in Zone Detail view:**
- `rootZoneDepth` — how deep the root zone is (inches)
- `availableWater` — soil water-holding capacity
- `managementAllowedDepletion` — how dry Rachio allows it to get before watering
- `efficiency` — sprinkler efficiency %
- `cropCoefficient` — seasonal water demand factor

Showing these would be the first app to make Flex Daily transparent to users.

### Deduplicate `moistureThreshold` Field
**File:** `SensorConfig` SwiftData model
The `moistureThreshold` field is kept for DB compatibility but is unused — global thresholds only. Add a migration to remove this field cleanly rather than carrying it indefinitely.

### Build Out Zone Detail Screen
**File:** `Views/Zones/ZoneDetailView.swift`
The current Zone Detail screen is minimal — it shows a single "last watered" entry, non-tappable sensor rows, and no skip history. The goal is to make this a full zone command center.

#### 1. Full Run History Card
**Current state:** One row derived from `zone.lastWateredDate`. No duration, no history.
**Target:** Fetch the last 10–20 watering events from `GET /device/{id}/event` (filtered by `zoneId`) and display them as a scrollable list.

Each row should show:
- Date + time of run (e.g. "Tue Apr 1 · 6:04 AM")
- Duration in minutes (from `RachioWateringEvent.duration / 60`)
- Skip any events where `isLongEnough == false` (< 5 min)

`RachioWateringEvent` struct is already defined. `getWateringHistory(deviceId:days:)` already exists on `RachioAPI`. No new API work needed — just wire the data into a multi-row section.

#### 2. Zone Skip History Card
**Current state:** Not shown anywhere in Zone Detail.
**Target:** Add a "Skipped Runs" section that lists recent rain/weather skips for this zone's schedule.

Use `getRainSkips(deviceId:days:)` (already implemented). Filter skips by matching `scheduleName` against the zone's linked schedule. Each row:
- Date of skip
- Reason string (e.g. "Rain", "Freeze", "Wind")

If no skips in last 30 days, show "No skips recently" placeholder. Cap at 5 rows; add "View all" if more.

#### 3. Active Zone Live Timer
**Current state:** Zone Detail shows "Running" badge but no elapsed/remaining time.
**Target:** When `zone.isRunning == true`, replace the static badge with a live countdown or elapsed timer.

If RachioSense started the run (duration known from the picker), show countdown: "3:42 remaining". Otherwise show elapsed time since `zone.lastWateredDate`. Use a `TimelineView(.periodic(from:by:))` or a 1-second `Timer` publisher so the display updates without re-fetching the API.

Add a visible progress ring or bar under the zone header that drains as the run progresses (only when duration is known).

#### 4. Tappable Linked Sensor Rows → Sensor Detail
**Current state:** Linked sensor rows in Zone Detail are static labels. Tapping does nothing.
**Target:** Make each linked sensor row a `NavigationLink` to `SensorDetailView` (or a new `SensorDetailView` if one doesn't exist yet).

The destination screen should show:
- Current moisture % + status badge
- Temperature reading
- 7-day sparkline chart (reuse `SensorGraphCard`)
- Predicted dry/critical date if trending down
- Sensor config (alias, thresholds, auto-water toggle)

This gives the user a way to drill from zone → sensor → full history without going to the Sensors tab.

#### 5. Inline Moisture Sparkline on Linked Sensor Rows
**Current state:** Linked sensor rows show name + EUI + auto-water badge only.
**Target:** Add a compact 48pt-wide sparkline (last 24h of readings) to the trailing edge of each linked sensor row, color-coded by current moisture status (green/yellow/red).

Reuse the `SensorGraphCard` chart rendering logic but at thumbnail scale. Data is already in SwiftData — no new fetch needed.

#### 6. Flex Daily Agronomic Parameters Card
**Current state:** These fields exist in the Rachio API response but are not shown anywhere.
**Target:** Add a collapsible "Flex Daily Settings" card at the bottom of Zone Detail (only visible when the zone's schedule type is `FLEX_DAILY`).

Fields to display (all from `GET /device/{id}` → `zones[]`):
| Label | Field | Display |
|-------|-------|---------|
| Root zone depth | `rootZoneDepth` | "X in" |
| Soil water holding | `availableWater` | "X in/in" |
| Allowed depletion | `managementAllowedDepletion` | "X%" |
| Head efficiency | `efficiency` | "X%" |
| Crop coefficient | `cropCoefficient` | "X" |

Add a small info button next to the card header that shows a sheet explaining what each parameter means. This makes RachioSense the only app that exposes these values to users.

**Note:** The top-level `RachioZone` struct already has these fields — just surface them in the UI.

---

## 🟢 Feature Additions — Rachio Standalone Quality

### ✅ Next Scheduled Run on Dashboard and Zone Rows — COMPLETED
**File:** `Views/Zones/ZoneCardView.swift`
Zone cards now display "Next run: 6:00 PM" per zone using the schedule's `startHour`/`startMinute`. For Flex Daily schedules, estimates time based on `lastWateredDate` since Rachio doesn't expose computed FLEX times via public API.

### Implement Auto-Water Execution
**Current state:** Auto-water is a setting but doesn't trigger Rachio.
**Implementation:**
1. `BackgroundRefreshManager` detects sensor crossing `autoWaterThreshold`
2. Calls `RachioAPI.startZone(zoneId:duration:)`
3. Sends local notification confirming execution
4. Enforces cooldown (configurable, e.g., 6 hours minimum between auto-water runs)
5. Respects watering windows (e.g., only between 4 AM – 10 AM)
6. Skips if Rachio rain delay is active

### ~~Multiple Rachio Devices~~ — NOT NEEDED
Single device only by design.

### Predictive Dry Alert + Schedule Reschedule Hint
**Location:** Dashboard Alerts card
**Trigger:** Any visible sensor predicted to hit dry or critical threshold within 24 hours.

**Display format (in Alerts card):**
```
⏱ Drying Soon
  Tomato Bed    critical in 4h  →  Move 6:00 AM run earlier
  Herb Garden   dry in 11h      →  Move 6:00 AM run earlier
```

**Logic:**
1. Use `SensorsViewModel.predictedCriticalDate()` / `predictedDryDate()` — already implemented via exponential decay fit on 72h of readings.
2. Only show sensors where predicted time is **> 0h and ≤ 24h** from now. If longer, suppress entirely.
3. For each affected sensor, look up its `linkedZoneId`, find the next scheduled Rachio run for that zone via `RachioDevice.nextRunDate(forZone:)`, and compute how much earlier the run should move.
4. Hint text: `"Move [schedule name] [startTimeFormatted] run earlier"` — or `"No schedule found, consider a manual run"` if no schedule is linked.

**Files to touch:**
- `Views/Dashboard/DashboardView.swift` — add new alert section in Alerts card
- `ViewModels/DashboardViewModel.swift` — expose `predictedAlerts: [(sensor: SensorConfig, hoursRemaining: Double, scheduleHint: String?)]`
- `SensorsViewModel.predictedDryDate()` / `predictedCriticalDate()` — already usable, may need to be called from DashboardViewModel

**Notes:**
- Reuse the existing prediction math — no new ML needed.
- `nextRunDate(forZone:)` is already on `RachioDevice` extension.
- Show critical threshold alert (not dry) if both apply — critical takes priority.
- Hide if sensor has `autoWaterEnabled = true` (auto-water will handle it).

### Retry UI for API Errors
**Current state:** Errors shown as banner, no retry button.
**Fix:** Add a retry button to error banners. For graph load failures, show a "Tap to retry" overlay on the blank chart area.

---

## 🔵 Differentiating Features — Beyond the Official App

### Soil Moisture vs. Watering Correlation View
A dedicated analytics screen that shows, for a selected sensor:
- Moisture level over the past 30 days (line chart)
- Each watering event as a vertical marker
- Moisture response curve: how quickly and how much the soil responded
- "Effectiveness" score: did watering actually raise moisture to the target?

### Smart Watering Suggestion
If auto-water is disabled, when a sensor is Dry/Critical show:
> "Tomato Bed has been dry for 6 hours. Suggested: Run Zone 3 for 12 min."

With a one-tap "Run Now" action.

### Rain Skip Transparency
When Rachio skips a scheduled run due to weather, display:
- Why it was skipped (rain forecast, freeze, wind)
- How much rain was expected vs. received
- Whether the skip was appropriate given actual sensor readings

**Note:** Zone Skip *notifications* are now implemented (fires within 30 min of the skip event, includes skip reason). What remains here is a dedicated UI view showing skip history with rain expectation vs. actual moisture response — a deeper transparency layer beyond the push alert.

### iOS Widget Suite
| Widget | Size | Content |
|--------|------|---------|
| Moisture summary | Small | Worst-case sensor status + count |
| Zone status | Small | Currently running zone or next run |
| Sensor grid | Medium | All sensors with color-coded dots |
| Combined dashboard | Large | Weather + alerts + next run |

### Live Activity — Active Zone
When a zone is running (manual or scheduled), show a Live Activity on the lock screen:
- Zone name
- Time remaining (countdown)
- Stop button

---

## 🏗️ Longer-Term Architecture

### Separate Rachio Logic into a Swift Package
`RachioKit` — a standalone Swift package wrapping the Rachio API with:
- Full typed model coverage
- Webhook event parsing
- Rate limit management
- Could be open-sourced independently

### CloudKit Sync
Settings and sensor configs synced via CloudKit so new devices and iPad get the same configuration without a manual backup/restore cycle.

### HomeKit Integration
Expose Rachio zones as `HMService` irrigation accessories via a local HomeKit bridge. High complexity but enables Siri, Automations, and Home app visibility.

---

## Notes on App Store Readiness
Before submission:
- [x] Replace hardcoded Phoenix coordinates with CoreLocation
- [x] Remove or gate all debug print statements
- [x] Fix SwiftData threading (ModelActor)
- [x] Add privacy usage strings for CoreLocation in Info.plist
- [x] Test on physical device (SenseCAP WebSocket + background refresh)
- [ ] Add onboarding flow for first launch (no credentials state)
- [ ] Verify Keychain entries are properly scoped with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

---

## 🔧 Refactoring Opportunities

### Introduce `CachedValue<T>` Generic
TTL-based caching logic is duplicated across `RachioAPI`, `SenseCraftAPI`, `ZonesViewModel`, and `WeatherAPI`. A small generic would eliminate it:
```swift
struct CachedValue<T> {
    private var value: T?
    private var cachedAt: Date?
    let ttl: TimeInterval

    var isFresh: Bool {
        guard let cachedAt else { return false }
        return Date().timeIntervalSince(cachedAt) < ttl
    }
    mutating func set(_ newValue: T) { value = newValue; cachedAt = Date() }
    func get() -> T? { isFresh ? value : nil }
    mutating func invalidate() { cachedAt = nil }
}
```

### Extract `SensorStatus` Enum
Moisture threshold comparisons appear in ViewModels, Views, and cache logic. A centralized enum ensures consistent behavior:
```swift
enum SensorStatus {
    case critical, dry, ok, high
    init(moisture: Double, autoWater: Double, dry: Double, high: Double) {
        if moisture < autoWater      { self = .critical }
        else if moisture < dry       { self = .dry }
        else if moisture > high      { self = .high }
        else                         { self = .ok }
    }
}
```

### Replace Manual JSON Parsing in `WeatherAPI` with `Codable`
`fetchForecast` uses `JSONSerialization` with manual key lookups. The Open-Meteo response shape is stable and documented — a `Codable` model would be more robust and self-documenting.

### Remove Redundant ViewModel Cache in `ZonesViewModel`
`ZonesViewModel` has its own 5-minute `lastLoadedAt` guard before calling `RachioAPI.getDevices()`, which already has a 5-minute actor-isolated cache. The ViewModel-level cache is redundant and prevents `forceRefresh: true` from reaching the API layer.

### Fix `DashboardCardOrder` — No Single-Instance Enforcement
Multiple `DashboardCardOrder` records can be inserted. Callers using `first` silently ignore duplicates. A fetch-or-create pattern or unique constraint would prevent this.

---

## 🧪 Unit Tests

Recommended test structure:
```
RachioSenseTests/
├── Models/         SensorConfigTests.swift
├── Services/       RachioAPITests.swift, KeychainServiceTests.swift, WeatherAPITests.swift
├── ViewModels/     ZonesViewModelTests.swift
├── Extensions/     DateExtensionTests.swift
└── Integration/    GraphDataPrefetcherTests.swift, LiveReadingsCacheTests.swift
```

### High-value unit tests

**`RachioScheduleRule.runsPerWeekDouble`**
- 3 specific weekdays → 3.0
- `INTERVAL_2` → 3.5, `INTERVAL_7` → 1.0
- Empty types → defaults to 1.0

**`RachioScheduleRule.startTimeFormatted`**
- Midnight (0:00) → "12:00 AM", Noon (12:00) → "12:00 PM", 13:30 → "1:30 PM"

**`SensorConfig.displayName` and `daysUntilExpiry`**
- No alias → returns `name`; empty alias → returns `name`; alias set → returns alias
- No expiry date → `nil`; future date → positive days; past date → ≤ 0

**`KeychainService` round-trip**
- Save / Load / Delete cycle; overwrite replaces existing value

**`RachioWateringEvent.isLongEnough`**
- 300s → `true`; 240s → `false`

**`WeatherAPI` icon and description mapping**
- WMO code 0 → `"sun.max.fill"`; code 99 → `"cloud.bolt.rain.fill"`; unknown → `"cloud.fill"`
- Note: `weatherIcon` and `weatherDescription` need to be `internal` to be testable

**`NotificationService` cooldown**
- First call fires; second call within cooldown window is suppressed; call after cooldown fires again

### Integration tests (require mock URLSession / in-memory SwiftData)
- **GraphDataPrefetcher deduplication** — readings within 60s of existing records are not duplicated
- **LiveReadingsCache coalescing** — concurrent `getReadings()` calls hit the API only once per device
- **RachioAPI 429 backoff** — mock 429 with `X-RateLimit-Reset` header; verify `rateLimitedUntil` uses header date, not fixed 5-minute fallback
- **LocationManager fallback chain** — GPS authorized → device location; denied + UserDefaults set → configured location; denied + no UserDefaults → Phoenix default
