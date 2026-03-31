# RachioSense — Suggestions & Roadmap Notes

This file captures architectural suggestions and feature ideas specific to the current state of the codebase, supplementing the Planned Features and Future Enhancements sections in the README.

---

## 🔴 High Priority — Bugs & Technical Debt

### Fix Duplicate API Calls on Load
**File:** `SensorsViewModel.swift`, `DashboardViewModel.swift`  
Both ViewModels independently fetch live SenseCAP readings on load, burning rate-limited calls unnecessarily.  
**Fix:** Introduce a shared `LiveReadingsCache` (actor or `@Observable` singleton) that both ViewModels subscribe to. One fetch, one source of truth.

### Fix SwiftData Threading
**File:** `BackgroundRefreshManager.swift`  
`ModelContext` is being used off the main queue. This is a known crash risk in Swift 6.  
**Fix:** Convert to `ModelActor` for background context access.

### Fix Hardcoded Phoenix Weather Location
**File:** `WeatherAPI.swift`  
Coordinates are hardcoded at `33.4484, -112.0740`.  
**Fix:** Use `CoreLocation` with a `CLLocationManager`. Fall back to a user-set location in Settings if location permission is denied. This also unblocks rain/freeze skip features from being meaningful.

### Remove Debug Print Statements
`[RachioAPI]`, `[Prefetch]`, etc. should be gated behind a `DEBUG` flag or replaced with `os.Logger` for production builds.

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

### Add Rachio Run History Overlay on Graphs
**Endpoint:** `GET /device/{id}/event`  
Returns irrigation event history with start time, duration, and zone ID.  
**Feature:** Overlay watering events as vertical bands or markers on the moisture line graphs. This makes the correlation between irrigation and moisture response immediately visible — something no official app shows.

**Data to extract per event:**
```json
{
  "type": "ZONE_STATUS",
  "subType": "ZONE_STARTED",
  "eventDate": "...",
  "zoneName": "...",
  "zoneId": "...",
  "duration": 600
}
```

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

### Next Scheduled Run on Dashboard and Zone Rows
**Endpoint:** Schedule data is already fetched via `GET /device/{id}`  
Calculate and display "Next run: Tomorrow 6:00 AM" per zone using the schedule's `startTime` and `days` arrays. For Flex Daily, use `nextRunDate` from the zone object if available.

### Implement Auto-Water Execution
**Current state:** Auto-water is a setting but doesn't trigger Rachio.  
**Implementation:**
1. `BackgroundRefreshManager` detects sensor crossing `autoWaterThreshold`
2. Calls `RachioAPI.startZone(zoneId:duration:)`
3. Sends local notification confirming execution
4. Enforces cooldown (configurable, e.g., 6 hours minimum between auto-water runs)
5. Respects watering windows (e.g., only between 4 AM – 10 AM)
6. Skips if Rachio rain delay is active

### Multiple Rachio Devices
**Current state:** README notes "Currently shows first device only."  
**Fix:** Iterate `person.devices[]` and aggregate zones across all controllers. Group zones by device in the Zones tab with a device header.

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

### Predictive Dry Date
Using recent moisture decline rate and weather forecast:
- Calculate estimated date/time the sensor will hit the dry threshold
- Show "Estimated dry in ~2.5 days" in sensor rows and detail view
- Send a push notification 24h before predicted critical

### Smart Watering Suggestion
If auto-water is disabled, when a sensor is Dry/Critical show:
> "Tomato Bed has been dry for 6 hours. Suggested: Run Zone 3 for 12 min."

With a one-tap "Run Now" action.

### Rain Skip Transparency
When Rachio skips a scheduled run due to weather, display:
- Why it was skipped (rain forecast, freeze, wind)
- How much rain was expected vs. received
- Whether the skip was appropriate given actual sensor readings

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
- [ ] Replace hardcoded Phoenix coordinates with CoreLocation
- [ ] Remove or gate all debug print statements
- [ ] Fix SwiftData threading (ModelActor)
- [ ] Add privacy usage strings for CoreLocation in Info.plist
- [ ] Test on physical device (SenseCAP WebSocket + background refresh)
- [ ] Add onboarding flow for first launch (no credentials state)
- [ ] Verify Keychain entries are properly scoped with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
