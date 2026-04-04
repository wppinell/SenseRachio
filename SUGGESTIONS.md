# RachioSense — Suggestions & Roadmap Notes

This file captures architectural suggestions and feature ideas specific to the current state of the codebase, supplementing the Planned Features and Future Enhancements sections in the README.

---

## 🔴 Fresh Code Review — April 2026 (Pass 2)

Issues found in the second review pass.

---

### ✅ Bug — `WeatherAPI` crashes when daily forecast arrays have mismatched lengths — FIXED
**File:** `Services/WeatherAPI.swift` (~line 99)
**Severity:** Bug — crash on malformed Open-Meteo response

```swift
for i in 0..<min(dates.count, 7) {
    let precipAmount = precip[i] > 0 ? precip[i] : nil  // ← crash if precip.count < dates.count
    daily.append(DailyForecast(
        date: date,
        highTemp: highs[i],   // ← crash if highs.count < dates.count
        ...
    ))
}
```

The loop is bounded by `dates.count`, but the API could return shorter arrays for `highs`, `lows`, `codes`, or `precip` if the forecast data for a day is unavailable. Any index beyond the shorter array's bounds is a fatal crash.

**Fix:**
```swift
for i in 0..<min(dates.count, highs.count, lows.count, codes.count, precip.count, 7) {
```
One-liner. Also consider logging a warning if the counts don't match so it's visible in diagnostics.

---

### ✅ Bug — `SensorsViewModel` inserts duplicate `SensorReading` rows on every foreground refresh — FIXED
**Files:** `ViewModels/SensorsViewModel.swift` (~line 78), `Services/LiveReadingsCache.swift`
**Severity:** Bug — database bloat, corrupts graph accuracy over time

Every call to `loadSensors()` that gets a cache hit inserts a fresh `SensorReading` into SwiftData with `recordedAt = cache.fetchedAt` (the time the cache was last populated, not the sensor's actual reading time). With a foreground refresh of 15s and a cache TTL of 60s, up to 4 identical records per sensor are inserted per minute — all with the same `recordedAt` value.

Two compounding problems:
1. Duplicate inserts: multiple `SensorReading` rows with identical `(eui, recordedAt)` accumulate in SwiftData, slowing graph queries and inflating local storage.
2. Wrong timestamp: `LiveReadingsCache.CachedReading.fetchedAt` is `Date()` at fetch time, not the sensor's actual measurement time (SenseCraft's `/view_latest_telemetry_data` endpoint returns no timestamp — only the current value). This means live-path readings appear "now" even if the sensor's last update was 20 minutes ago.

**Fix (duplicate inserts):** Before inserting, check if a reading for the same EUI within the last 60 seconds already exists:
```swift
let eui = reading.eui
let cutoff = reading.recordedAt.addingTimeInterval(-60)
let existingPredicate = #Predicate<SensorReading> { $0.eui == eui && $0.recordedAt >= cutoff }
let existing = (try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate)))?.first
if existing == nil {
    modelContext.insert(SensorReading(eui: reading.eui, moisture: reading.moisture,
                                     tempC: reading.tempC, recordedAt: reading.recordedAt))
}
```

**Fix (wrong timestamp):** If SenseCraft ever adds a timestamp field to the telemetry endpoint, thread it through `CachedReading` and `SensorReading`. For now, document the current behavior so future engineers don't assume SwiftData timestamps reflect sensor measurement times.

---

### ✅ Bug — "Zone Started" toggle is dead code; users enabling it see nothing — FIXED
**File:** `Views/Settings/Configuration/NotificationsSettingsView.swift` (~line 98), `DesignSystem/DesignSystem.swift`
**Severity:** Bug — misleading UI; user enables a toggle that never fires

`AppStorageKey.zoneStartedEnabled` is defined, surfaced in Settings as a toggle (default off), and included in the export backup — but `NotificationService` has no `scheduleZoneStartedAlert()` method and `BackgroundRefreshManager` never evaluates the toggle. A user who enables "Zone Started" receives no notifications.

**Fix:** Either implement the alert (detect a zone transitioning to running state via Rachio's running status field in a future polling pass), or remove the toggle from the UI and key from `DesignSystem` until the feature is ready. Leaving it visible is the worse option — it erodes user trust in the notification system.

---

## 🔴 Fresh Code Review — April 2026

Issues found in this pass. Severity ratings: **Bug** = can misbehave at runtime; **Fragile** = correct today but breaks under plausible future conditions; **Design** = no current misbehavior, but creates maintenance risk.

---

### ✅ Bug — `RachioAPI` rate-limit reset timestamp fails to parse when fractional seconds are present — FIXED
**File:** `Services/RachioAPI.swift` (~line 286)
**Severity:** Bug — silent API abuse when Rachio returns a 429

`ISO8601DateFormatter()` with default options does not parse timestamps that include fractional seconds (e.g. `2026-04-04T10:30:00.000Z`). If Rachio sends this format, `formatter.date(from: resetStr)` returns `nil`, `rateLimitedUntil` is never set, and the app continues firing requests past the 429 limit.

**Fix:**
```swift
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
```
Or try both formatters in sequence:
```swift
let formatter1 = ISO8601DateFormatter()
let formatter2 = ISO8601DateFormatter()
formatter2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let resetDate = formatter1.date(from: resetStr) ?? formatter2.date(from: resetStr)
```

---

### ✅ Bug — `LiveReadingsCache.getReadings(hiddenEuis:)` ignores `hiddenEuis` for coalesced callers — FIXED
**File:** `Services/LiveReadingsCache.swift` (~line 43-47)
**Severity:** Logic bug — callers that coalesce onto an in-flight fetch receive results filtered by the *first* caller's hidden sensor set, not their own.

When `isFetching == true`, a second caller appends a `CheckedContinuation` and awaits. When the fetch finishes, all waiting continuations get the same `result` computed from the first caller's `hiddenEuis`. The second caller's `hiddenEuis` argument is silently dropped.

In the current codebase, all callers pass the same hidden set so this is not visible. But if any future caller uses a different set (e.g. a widget extension or diagnostics view), it will receive wrong data.

**Fix:** Either ignore `hiddenEuis` entirely and filter at the call site, or store waiting continuations with their requested filter and apply per-caller filtering after the fetch resolves.

---

### ✅ Bug — `checkZoneSkips()` records Rachio success timestamp before all API calls complete — FIXED
**File:** `Background/BackgroundRefreshManager.swift` (~line 410)
**Severity:** Minor logic — service-disconnect alert timer resets even on partial failures

`notif_rachio_last_success` is written immediately after `getDevices()` succeeds, before `getRainSkips(deviceId:days:)` is called. If `getRainSkips` throws, the success timestamp was already updated, silencing any service-disconnect alert for the next 6 hours. This matters if rain-skip polling is flakier than device polling (e.g. a specific endpoint outage).

**Fix:** Only write the success timestamp after all per-device Rachio calls in a given cycle complete without throwing.

---

### ✅ Fragile — `LocationManager` timeout task is not stored or cancelled — FIXED
**File:** `Services/LocationManager.swift` (~line 103)
**Severity:** Fragile — correct in current usage; crashes under a specific edge case

`requestLocation()` spawns an unstructured `Task` for the 10-second timeout but does not store a reference to it. If `requestLocation()` were called a second time before the first timeout fires (e.g. due to a retry added in the future), the first timeout task wakes up, sees a non-nil `locationContinuation` (pointing at the *new* request), nils it, and resumes the new continuation with `nil` — silently killing the second location request.

**Fix:** Store the timeout task in a property and cancel it on success:
```swift
private var locationTimeoutTask: Task<Void, Never>?

// in requestLocation(), on success path:
locationTimeoutTask?.cancel()
locationTimeoutTask = nil
```

---

### ✅ Design — `SensorSummaryData.driest` uses a named tuple — FIXED
**File:** `Background/BackgroundRefreshManager.swift` (top-level struct)
**Severity:** Design — named tuples cannot conform to protocols; blocks future Sendable verification and testing

`let driest: (name: String, eui: String, moisture: Double)?` works fine today but will cause issues if you ever need to store it in a collection, pass it to a generic, or add Codable conformance. Swift's named-tuple Sendable inference is also under-specified.

**Fix:** Replace with a small struct:
```swift
struct DriestSensor: Sendable {
    let name: String
    let eui: String
    let moisture: Double
}
```

---

### ✅ Design — `checkZoneNotifications()` and `checkZoneSkips()` both call `getDevices()` independently — FIXED
**File:** `Background/BackgroundRefreshManager.swift`
**Severity:** Design — wasteful even with caching; second call adds a cache-lookup hop and a potential 5-minute stale data gap

Both methods hit `RachioAPI.shared.getDevices()`. The actor cache prevents double network I/O, but the two callers are logically coupled (both need the same device snapshot per refresh cycle) and should share a single result.

**Fix:** Fetch devices once in `performRefresh()` and pass the result to both `checkZoneNotifications(devices:)` and `checkZoneSkips(devices:)` as a parameter. Eliminates the coupling and removes the redundant `notif_rachio_last_success` write in `checkZoneSkips()`.

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
