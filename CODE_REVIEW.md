# RachioSense — Code Review, Refactoring & Test Case Report

**Date:** April 4, 2026
**Scope:** Full codebase — Services, ViewModels, Models, Background tasks
**Swift version:** 6

---

## Executive Summary

RachioSense is a well-structured SwiftUI app with a solid MVVM architecture, thoughtful API rate-limit handling, and good use of modern Swift concurrency (`async/await`, actors). Many previously known issues (SwiftData threading, hardcoded location, duplicate API calls, debug prints) have already been resolved. The findings below focus on the issues that remain — primarily around concurrency safety, a few fragile patterns, and missing test coverage.

**Severity legend:** 🔴 High &nbsp;|&nbsp; 🟡 Medium &nbsp;|&nbsp; 🟢 Low

---

## Code Review Findings

### Services Layer

---

#### `RachioAPI.swift`

**🔴 Unsynchronized mutable state outside the fetch lock**

`OSAllocatedUnfairLock` protects only `activeFetchTask`, but mutable properties like `cachedDevices`, `cacheTimestamp`, `cachedPersonId`, `rateLimitedUntil`, `rateLimitRemaining`, and `rateLimitTotal` are read and written without any lock. The comment `// no lock needed for read` on line 401 is not correct — concurrent reads of a mutating value are a data race in Swift 6 strict concurrency mode. Converting `RachioAPI` to an `actor` would resolve all of these at once (see Refactoring section).

**🟡 `getWateringEvents` cache is not thread-safe**

`cachedEvents` and `eventCacheTimestamp` are mutated from whatever concurrency context the caller is on. These have the same race condition as the device cache above. They also lack the coalescing (`activeFetchTask`) logic that `getDevices` has, meaning two callers arriving simultaneously will both make live API requests.

**🟡 Zone name parsing from event summaries is fragile**

In `getWateringEvents`, zone names are extracted by splitting the `summary` string on keywords like `" began "` and `" started "`:

```swift
let separators = [" began ", " started ", " completed ", " finished "]
```

If Rachio changes their event summary wording, zone names silently revert to the raw summary string. A defensive fallback to the `zoneName` field (if Rachio adds it) or logging of parse failures would reduce brittleness.

**🟡 Empty `MARK` section**

There is a `// MARK: - Get Schedule Rules for Device` section at line 383 with no implementation. Either delete it or add the planned implementation.

**🟢 Unnecessary `[weak self]` in singleton Task**

In `getDevices()`, the task closure captures `[weak self]` — but `RachioAPI.shared` is a singleton that will never be deallocated. The weak reference is harmless but misleading.

---

#### `SenseCraftAPI.swift`

**🟡 `fetchHistoryChunk` is unnecessarily public**

`fetchHistoryChunk(eui:startMs:endMs:)` is `internal` (the default), but it is only called by `GraphDataPrefetcher` and within `SenseCraftAPI` itself. Making it `private` and exposing a higher-level interface would better encapsulate the chunking strategy.

**🟡 Measurement IDs are magic strings**

`"4103"` (moisture) and `"4102"` (temperature) appear in multiple places. These should be named constants:

```swift
private enum MeasurementID {
    static let moisture = "4103"
    static let temperature = "4102"
}
```

**🟢 `try?` silently drops `CancellationError` in retry sleep**

`try? await Task.sleep(nanoseconds: wait)` inside the chunking retry loop discards `CancellationError`. If the enclosing task is cancelled during the sleep, the cancellation is silently ignored and the loop continues. Prefer `try await Task.sleep(...)` and let the cancellation propagate.

---

#### `GraphDataPrefetcher.swift`

**🟡 Full DB scan for pruning is O(n)**

After every fetch, the pruning step fetches *all* readings into memory and filters in Swift:

```swift
let freshReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
let old = freshReadings.filter { $0.recordedAt < cutoff }
```

With 8,000+ readings this works fine today, but as the DB grows this becomes expensive. A predicate-based fetch would be more efficient:

```swift
let descriptor = FetchDescriptor<SensorReading>(
    predicate: #Predicate { $0.recordedAt < cutoff }
)
let old = (try? modelContext.fetch(descriptor)) ?? []
```

**🟡 Two parallel fetch-tracking mechanisms**

Both `isFetching: Bool` and `activeFetchTask: Task?` are used to guard against concurrent fetches. They serve slightly different roles (`isFetching` is used in `run()`, `activeFetchTask` is used in `fetchRecent`/`fetchIfNeeded`) but having two mechanisms could get out of sync if code paths change. Consolidating to a single `Task?` sentinel would simplify the logic.

**🟢 `@MainActor` class performing heavy async work**

`GraphDataPrefetcher` is annotated `@MainActor` but all its async methods immediately do network calls and DB writes. Because the methods are `async`, Swift suspends from the main thread during awaits — so there's no actual main-thread blocking. However, the `@MainActor` annotation is misleading: it implies the class is UI-facing when its real role is a background data service. Consider removing `@MainActor` and instead ensuring that only `modelContext.save()` and inserts are dispatched to `MainActor` explicitly (or using `ModelActor`).

---

#### `LiveReadingsCache.swift`

**🟡 Creating `SensorReading` SwiftData models outside a `ModelContext`**

`buildSensorReadings(from:)` creates `SensorReading` instances (a `@Model` class) without inserting them into a `ModelContext`. These are "detached" model objects — not persisted, used purely for in-memory state passing to ViewModels. This works today, but SwiftData models created this way are in an unmanaged state. A plain `struct` for the in-flight reading data would be semantically cleaner and avoid any potential SwiftData lifecycle surprises.

**🟢 `hiddenEuis` must be passed by caller to avoid ModelContext access**

The comment acknowledges this is a workaround. A cleaner long-term approach would be for `LiveReadingsCache` to accept a device list (already fetched) rather than fetching devices itself, separating the concerns of "fetch device list" and "fetch live readings."

---

#### `KeychainService.swift`

**🟡 `deleteAll()` does not delete `rachioDeviceIds`**

`deleteAll()` removes the SenseCraft key/secret and the Rachio API key, but `KeychainKey.rachioDeviceIds` is not deleted. After a "Reset Everything" flow, cached device IDs persist in the keychain. If the user later connects a *different* Rachio account with different devices, stale IDs could cause incorrect fetches before the cache is refreshed.

```swift
// Missing from deleteAll():
_ = try? delete(forKey: KeychainKey.rachioDeviceIds)
```

**🟡 Credential existence check pattern is verbose**

Many callers check `KeychainService.shared.load(forKey: ...) != nil` just to verify a credential exists, then call `load` again to retrieve the value. A `hasCredential(forKey:)` helper (checking `SecItemCopyMatching` without returning data) would express intent more clearly and avoid the double Keychain lookup.

**🟢 Keychain accessibility attribute**

`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` allows the keychain items to be accessed while the device is locked (after first unlock). The SUGGESTIONS.md already flags `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` as the preferred value for better security. Note: changing this will break background refresh (which needs credentials when the device may be locked), so this is a deliberate trade-off worth documenting explicitly in a comment.

---

#### `WeatherAPI.swift`

**🟡 Force unwrap on URL construction**

Line 48: `URLSession.shared.data(from: components.url!)` will crash if `URLComponents` fails to produce a URL. Although this won't happen with the current hardcoded base URL, it's a defensive gap. The pattern used in `RachioAPI` (using a `guard let url = URL(string: ...)`) is safer.

**🟢 Uses `URLSession.shared` instead of a configured session**

Unlike `RachioAPI` and `SenseCraftAPI`, `WeatherAPI` uses `URLSession.shared` with its default 60-second timeout. Consistent use of a configured session with an explicit 30-second timeout would match the rest of the codebase.

**🟢 `WeatherError` carries no diagnostic context**

`WeatherError.apiError` and `.parseError` carry no information about the HTTP status code or which field failed to parse. Adding associated values (e.g., `case apiError(Int)`, `case parseError(String)`) would improve debuggability without breaking anything.

---

### ViewModels

---

#### `AppState.swift`

**🟡 Mixed concurrency patterns**

`showError()` dispatches to `DispatchQueue.main.async` while the rest of the class relies on Combine's `@Published`. In a Swift 6 codebase, the recommended approach is `@MainActor` isolation on the class, which makes all property mutations implicitly main-actor-safe without any manual dispatching.

**🟢 No `@MainActor` annotation**

`AppState` is `ObservableObject` with `@Published` properties that should always be mutated on the main thread. Adding `@MainActor` to the class declaration would enforce this at compile time.

---

#### `ZonesViewModel.swift`

**🟡 `stopAllZones` silently swallows errors**

```swift
for zone in allZones {
    try? await RachioAPI.shared.stopZone(id: zone.id)
}
```

If any zone fails to stop (e.g., network error, rate limit), the error is discarded. Users get no feedback that some zones may still be running. At minimum, collect errors and expose them via `errorMessage`.

**🟡 Redundant 5-minute cache layer**

`ZonesViewModel` has its own `lastLoadedAt` 5-minute guard check before calling `RachioAPI.getDevices()`, which already has a 5-minute cache internally. The ViewModel-level cache is redundant — it prevents `forceRefresh: true` from reaching the API layer when the ViewModel's timer hasn't expired. Consider removing the ViewModel-level cache and relying solely on `RachioAPI`'s cache.

**🟢 `MainActor.run` boilerplate throughout**

`await MainActor.run { isLoading = true; errorMessage = nil }` appears in nearly every method. Adding `@MainActor` to `ZonesViewModel` would eliminate all of these blocks.

---

#### `DashboardViewModel.swift`

**🟢 `driestSensor` returns `(config: SensorConfig?, reading: SensorReading?)`**

The computed property always returns `config: nil` — the `SensorConfig` half is never populated. Either populate it (requires ModelContext access) or simplify the return type to just `SensorReading?`.

---

### Models

---

#### `SwiftDataModels.swift`

**🟡 `moistureThreshold` dead field**

`SensorConfig.moistureThreshold` is documented as unused (global thresholds only) but retained for DB compatibility. This should be removed via a SwiftData migration to avoid confusion for future contributors. The `SUGGESTIONS.md` already tracks this.

**🟡 `DashboardCardOrder` — no single-instance enforcement**

Multiple `DashboardCardOrder` records can be inserted. Any code that fetches this model with `fetch(FetchDescriptor<DashboardCardOrder>())` and takes `first` will silently ignore extras. A unique constraint or explicit "fetch-or-create" pattern would be safer.

**🟢 `SensorConfig` has both `id` and `eui`**

In practice, `eui` is the stable unique identifier for a SenseCAP device. `id` appears to be a UUID generated at creation. Clarifying in code comments which field is authoritative for deduplication would reduce ambiguity.

---

## Refactoring Opportunities

### 1. Convert `RachioAPI` to an Actor

The most impactful single refactor. Converting from a `final class` with manual `OSAllocatedUnfairLock` to `actor RachioAPI` would:

- Eliminate all manual locking
- Protect all mutable state (`cachedDevices`, `cachedPersonId`, `rateLimitedUntil`, etc.) automatically
- Make the concurrency contract explicit and compiler-enforced
- Resolve the data-race risks identified above

The main trade-off is that callers would need `await` at the call site for property access, but since `getDevices()` is already `async`, most call sites are already in async contexts.

### 2. Introduce a `CachedValue<T>` Generic

TTL-based caching logic appears in at least four places (`RachioAPI`, `SenseCraftAPI`, `ZonesViewModel`, and `WeatherAPI` in `DashboardViewModel`). A small generic struct would eliminate the duplication:

```swift
struct CachedValue<T> {
    private var value: T?
    private var cachedAt: Date?
    let ttl: TimeInterval

    var isFresh: Bool {
        guard let cachedAt else { return false }
        return Date().timeIntervalSince(cachedAt) < ttl
    }

    mutating func set(_ newValue: T) {
        value = newValue
        cachedAt = Date()
    }

    func get() -> T? { isFresh ? value : nil }
    mutating func invalidate() { cachedAt = nil }
}
```

### 3. Extract `SensorStatus` Enum

Moisture threshold comparisons like `moisture < autoWaterThreshold` and `moisture > highThreshold` appear in ViewModels, Views, and cache logic. A centralized `SensorStatus` enum with a computed initializer would ensure consistent behavior everywhere:

```swift
enum SensorStatus {
    case critical, dry, ok, high

    init(moisture: Double, autoWater: Double, dry: Double, high: Double) {
        if moisture < autoWater { self = .critical }
        else if moisture < dry   { self = .dry }
        else if moisture > high  { self = .high }
        else                     { self = .ok }
    }
}
```

### 4. Replace Manual JSON Parsing with `Codable` in `WeatherAPI`

`WeatherAPI.fetchForecast` uses `JSONSerialization` with manual key lookups and force casts. This is error-prone and verbose. Since the Open-Meteo API has a stable, documented response shape, a `Codable` model would be more robust and self-documenting.

### 5. Annotate `ZonesViewModel` and `DashboardViewModel` with `@MainActor`

Both ViewModels repeatedly call `await MainActor.run { ... }` to publish state changes. Adding `@MainActor` to the class declaration eliminates this pattern entirely and makes the isolation contract clear to the compiler.

---

## Test Case Recommendations

### Unit Tests (XCTest / Swift Testing)

The following are the highest-value unit tests to write, covering logic that can be tested without network access or a device.

---

#### `RachioScheduleRule` — `runsPerWeekDouble`

```swift
func testRunsPerWeek_fixedDays() {
    // 3 specific days → 3.0 runs/week
    let rule = makeRule(types: ["DAY_OF_WEEK_1", "DAY_OF_WEEK_3", "DAY_OF_WEEK_5"])
    XCTAssertEqual(rule.runsPerWeekDouble, 3.0)
}

func testRunsPerWeek_interval2() {
    // Every 2 days → 3.5 runs/week
    let rule = makeRule(types: ["INTERVAL_2"])
    XCTAssertEqual(rule.runsPerWeekDouble, 3.5)
}

func testRunsPerWeek_interval7() {
    // Every 7 days → 1.0 run/week
    let rule = makeRule(types: ["INTERVAL_7"])
    XCTAssertEqual(rule.runsPerWeekDouble, 1.0)
}

func testRunsPerWeek_emptyTypes_defaultsTo1() {
    let rule = makeRule(types: [])
    XCTAssertEqual(rule.runsPerWeekDouble, 1.0)
}
```

---

#### `RachioScheduleRule` — `startTimeFormatted`

```swift
func testStartTime_midnight() {
    let rule = makeRule(hour: 0, minute: 0)
    XCTAssertEqual(rule.startTimeFormatted, "12:00 AM")
}

func testStartTime_noon() {
    let rule = makeRule(hour: 12, minute: 0)
    XCTAssertEqual(rule.startTimeFormatted, "12:00 PM")
}

func testStartTime_1330() {
    let rule = makeRule(hour: 13, minute: 30)
    XCTAssertEqual(rule.startTimeFormatted, "1:30 PM")
}

func testStartTime_nineAM() {
    let rule = makeRule(hour: 9, minute: 5)
    XCTAssertEqual(rule.startTimeFormatted, "9:05 AM")
}
```

---

#### `SensorConfig` — `displayName` and `daysUntilExpiry`

```swift
func testDisplayName_noAlias_returnsName() {
    let sensor = SensorConfig(id: "1", name: "Soil Sensor #1", eui: "ABC")
    XCTAssertEqual(sensor.displayName, "Soil Sensor #1")
}

func testDisplayName_emptyAlias_returnsName() {
    let sensor = SensorConfig(id: "1", name: "Soil Sensor #1", eui: "ABC", alias: "")
    XCTAssertEqual(sensor.displayName, "Soil Sensor #1")
}

func testDisplayName_withAlias_returnsAlias() {
    let sensor = SensorConfig(id: "1", name: "Soil Sensor #1", eui: "ABC", alias: "Tomato Bed")
    XCTAssertEqual(sensor.displayName, "Tomato Bed")
}

func testDaysUntilExpiry_nil_whenNoExpiry() {
    let sensor = SensorConfig(id: "1", name: "S", eui: "A")
    XCTAssertNil(sensor.daysUntilExpiry)
}

func testDaysUntilExpiry_positiveWhenFuture() {
    let expiry = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    let sensor = SensorConfig(id: "1", name: "S", eui: "A", subscriptionExpiryDate: expiry)
    XCTAssertEqual(sensor.daysUntilExpiry, 14)
}

func testDaysUntilExpiry_negativeOrZeroWhenPast() {
    let expiry = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let sensor = SensorConfig(id: "1", name: "S", eui: "A", subscriptionExpiryDate: expiry)
    XCTAssertTrue((sensor.daysUntilExpiry ?? 1) <= 0)
}
```

---

#### `Date.rounded(toMinutes:)`

```swift
func testRoundedUpToNearestMinute() {
    // 12:01:31 rounds up to 12:02:00
    let date = Calendar.current.date(from: DateComponents(hour: 12, minute: 1, second: 31))!
    let rounded = date.rounded(toMinutes: 1)
    let comps = Calendar.current.dateComponents([.minute, .second], from: rounded)
    XCTAssertEqual(comps.minute, 2)
    XCTAssertEqual(comps.second, 0)
}

func testRoundedDownToNearestMinute() {
    // 12:00:29 rounds down to 12:00:00
    let date = Calendar.current.date(from: DateComponents(hour: 12, minute: 0, second: 29))!
    let rounded = date.rounded(toMinutes: 1)
    let comps = Calendar.current.dateComponents([.minute, .second], from: rounded)
    XCTAssertEqual(comps.minute, 0)
    XCTAssertEqual(comps.second, 0)
}
```

*(Note: `Date.rounded(toMinutes:)` is currently `private` in `GraphDataPrefetcher.swift` — make it `internal` or move it to a shared `Date+Extensions.swift` to enable testing.)*

---

#### `WeatherAPI` — Icon and description mapping

```swift
func testWeatherIcon_clearSky() {
    XCTAssertEqual(WeatherAPI.shared.weatherIcon(for: 0), "sun.max.fill")
}

func testWeatherIcon_thunderstormWithHail() {
    XCTAssertEqual(WeatherAPI.shared.weatherIcon(for: 99), "cloud.bolt.rain.fill")
}

func testWeatherIcon_unknownCode_returnsDefault() {
    XCTAssertEqual(WeatherAPI.shared.weatherIcon(for: 999), "cloud.fill")
}
```

*(Note: `weatherIcon` and `weatherDescription` are currently `private` — they should be exposed as `internal` or via a static helper to enable testing.)*

---

#### `KeychainService` — Save, Load, Delete cycle

```swift
func testKeychainSaveAndLoad() throws {
    let key = "test_key_\(UUID().uuidString)"
    try KeychainService.shared.save("test_value", forKey: key)
    XCTAssertEqual(KeychainService.shared.load(forKey: key), "test_value")
    try KeychainService.shared.delete(forKey: key)
    XCTAssertNil(KeychainService.shared.load(forKey: key))
}

func testKeychainOverwrite() throws {
    let key = "test_overwrite_\(UUID().uuidString)"
    try KeychainService.shared.save("first", forKey: key)
    try KeychainService.shared.save("second", forKey: key)
    XCTAssertEqual(KeychainService.shared.load(forKey: key), "second")
    try KeychainService.shared.delete(forKey: key)
}
```

---

#### `RachioAPI` — Rate limit state

```swift
func testIsRateLimited_false_whenNilUntil() {
    let api = RachioAPI.shared
    // After a successful fetch, rateLimitedUntil should be nil
    XCTAssertFalse(api.isRateLimited)
}

func testRateLimitResetsInMinutes_nil_whenNotLimited() {
    XCTAssertNil(RachioAPI.shared.rateLimitResetsInMinutes)
}
```

---

#### `RachioWateringEvent` — `isLongEnough`

```swift
func testIsLongEnough_true_forFiveMinutes() {
    let event = RachioWateringEvent(id: "1", zoneId: "z", zoneName: "Front Lawn",
                                    startDate: Date(), endDate: nil, duration: 300)
    XCTAssertTrue(event.isLongEnough)
}

func testIsLongEnough_false_forFourMinutes() {
    let event = RachioWateringEvent(id: "1", zoneId: "z", zoneName: "Front Lawn",
                                    startDate: Date(), endDate: nil, duration: 240)
    XCTAssertFalse(event.isLongEnough)
}
```

---

### Integration Tests

These require more setup (mock URLSession, in-memory SwiftData container) but cover critical paths:

**GraphDataPrefetcher deduplication** — Verify that inserting a batch containing readings within 60 seconds of existing DB entries does not create duplicates.

**LiveReadingsCache coalescing** — Call `getReadings()` concurrently from multiple tasks and verify `SenseCraftAPI.fetchReading()` is called only once per device (requires injecting a mock API).

**RachioAPI 429 backoff** — Mock a 429 response with a `X-RateLimit-Reset` header and verify `rateLimitedUntil` is set to the header's date, not the fallback 5-minute window.

**LocationManager fallback chain** — Test the three cases: GPS authorized (returns device location), GPS denied with UserDefaults set (returns configured location), GPS denied with no UserDefaults (returns Phoenix default).

---

### Suggested Test File Structure

```
RachioSenseTests/
├── Models/
│   └── SensorConfigTests.swift
├── Services/
│   ├── RachioAPITests.swift
│   ├── KeychainServiceTests.swift
│   └── WeatherAPITests.swift
├── ViewModels/
│   └── ZonesViewModelTests.swift
├── Extensions/
│   └── DateExtensionTests.swift
└── Integration/
    ├── GraphDataPrefetcherTests.swift
    └── LiveReadingsCacheTests.swift
```

---

## App Store Readiness Checklist Update

Items carried forward from `SUGGESTIONS.md`:

| Item | Status | Notes |
|------|--------|-------|
| Replace hardcoded Phoenix coordinates | ✅ Done | `LocationManager` implemented |
| Remove debug print statements | ✅ Done | Replaced with `os.Logger` |
| Fix SwiftData threading (ModelActor) | ✅ Done | `BackgroundRefreshManager` updated |
| Add CoreLocation privacy string | ✅ Done | Added to Info.plist |
| `deleteAll()` missing `rachioDeviceIds` | 🔴 Open | See KeychainService findings |
| Verify Keychain accessibility attribute | 🟡 Open | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` vs current |
| Test on physical device | 🟡 Open | SenseCAP WebSocket + background refresh |
| Add onboarding flow | 🟡 Open | First-launch empty state |
| Write unit tests | 🟡 Open | See test cases above |

---

*Generated by Claude — RachioSense codebase review, April 4, 2026*
