# RachioSense — Notification System

Complete reference for the notification system: what's implemented, what's missing, exact message copy, timing rules, and the settings UI inventory.

---

## Status Overview

| Area | Status |
|------|--------|
| NotificationService (cooldown, quiet hours, severity) | ✅ Implemented |
| Predictive dry/critical alerts | ✅ Implemented |
| Permission request | ❌ Never called |
| Background refresh scheduling | ❌ Never submitted to OS |
| Sensor offline detection | ❌ Not implemented |
| Zone started / stopped | ❌ Not implemented |
| Scheduled run notification | ❌ Not implemented |
| Daily summary | ❌ Not implemented |
| Weekly report | ❌ Not implemented |

---

## Critical Gaps (Nothing Works Without These)

### 1. Permission is never requested

`NotificationService.shared.requestPermission()` exists but is never called. iOS will never show the permission dialog, and no notifications can be delivered.

**Fix — `RachioSenseApp.swift`:**
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        UserDefaults.standard.removeObject(forKey: "lastExtendedFetchTimestamp")
        Task { await NotificationService.shared.requestPermission() }   // ADD
    }
}
```
`requestAuthorization` is a no-op if permission was already granted or denied, so calling it on every foreground is safe.

### 2. Background refresh is never scheduled

`registerTasks()` tells iOS *how* to handle the task but never *submits* a request. The background task will never fire.

**Fix — `RachioSenseApp.swift`:**
```swift
init() {
    // ... ModelContainer setup ...
    BackgroundRefreshManager.shared.registerTasks()
    BackgroundRefreshManager.shared.scheduleAppRefresh()   // ADD — submit first request
}
```

Also reschedule whenever the app moves to the background (iOS may cancel pending requests):
```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {                                        // ADD
        BackgroundRefreshManager.shared.scheduleAppRefresh()            // ADD
    }                                                                   // ADD
    if newPhase == .active { ... }
}
```

---

## Notification Types

### A. Threshold Alert — Critical
Fires when `moisture < autoWaterThreshold` (default 20%).

| Field | Value |
|-------|-------|
| **Title** | `⚠️ Critical Soil Moisture` |
| **Body (with zone)** | `{SensorName} is at {X}%. Consider running zone "{ZoneName}".` |
| **Body (no zone)** | `{SensorName} is at {X}%.` |
| **Sound** | Default |
| **Identifier** | `moisture-critical-{eui}` (replaces previous if pending) |
| **Toggle key** | `dryAlertsEnabled` (default: on) |
| **Cooldown key** | `notif_last_sent_critical_{eui}` |

### B. Threshold Alert — Low
Fires when `dryThreshold > moisture >= autoWaterThreshold` (typically 20–25%).

| Field | Value |
|-------|-------|
| **Title** | `Soil Moisture Low` |
| **Body (with zone)** | `{SensorName} is at {X}%. Consider running zone "{ZoneName}".` |
| **Body (no zone)** | `{SensorName} is at {X}%.` |
| **Sound** | Default |
| **Identifier** | `moisture-low-{eui}` |
| **Toggle key** | `lowAlertsEnabled` (default: on) |
| **Cooldown key** | `notif_last_sent_low_{eui}` |

### C. Predictive Alert — Going Critical
Fires when exponential decay model predicts `moisture < autoWaterThreshold` within the alert window, but sensor is still above it now.

| Field | Value |
|-------|-------|
| **Title** | `⚠️ Going Critical Soon` |
| **Body** | `{SensorName} will reach critical in ~{X}h.` or `~{X}m` if < 1h |
| **Sound** | Default |
| **Identifier** | `moisture-predictive-critical-{eui}` |
| **Toggle key** | `predictiveAlertEnabled` (default: on) |
| **Cooldown key** | `notif_last_sent_predictive-critical_{eui}` |
| **Window** | `predictiveAlertWindowHours` (default: 6h) |

### D. Predictive Alert — Going Dry
Fires when model predicts `moisture < dryThreshold` within the window. Suppressed if a predictive-critical alert already fired for this sensor this cycle.

| Field | Value |
|-------|-------|
| **Title** | `Going Dry Soon` |
| **Body** | `{SensorName} will reach dry in ~{X}h.` |
| **Sound** | Default |
| **Identifier** | `moisture-predictive-dry-{eui}` |
| **Toggle key** | `predictiveAlertEnabled` (default: on) |
| **Cooldown key** | `notif_last_sent_predictive-dry_{eui}` |

### E. Sensor Offline *(not implemented)*
Toggle exists in UI (`sensorOfflineEnabled`), no code fires it.

**Proposed trigger:** No new reading received in `2 × backgroundRefreshInterval`.

| Field | Value |
|-------|-------|
| **Title** | `Sensor Offline` |
| **Body** | `{SensorName} hasn't reported in over {X} hours.` |
| **Identifier** | `sensor-offline-{eui}` |
| **Cooldown** | 12h (sensor offline tends to persist) |

**Implementation note:** Track last successful reading timestamp per EUI in UserDefaults (`notif_last_reading_{eui}`). In `BackgroundRefreshManager`, if a `fetchReading()` call fails *and* the stored timestamp is older than the threshold, fire the offline alert.

### F. Zone Started / Stopped / Scheduled Run *(not implemented)*
Toggles exist. Needs Rachio webhook pipeline (see SUGGESTIONS.md) or polling in `performRefresh()`.

**Proposed messages:**
- **Zone Started:** `"{ZoneName}" is running — {duration} scheduled.`
- **Zone Stopped:** `"{ZoneName}" finished after {actual} minutes.`
- **Scheduled Run:** `"{ZoneName}" is scheduled to run at {time} today.`

### G. Daily Summary *(not implemented)*
Toggle + time picker exist. No scheduled local notification is ever created.

**Implementation:** On foreground launch, use `UNCalendarNotificationTrigger` with `DateComponents(hour:, minute:)` to schedule a repeating daily notification. Regenerate on each launch so the summary content stays current.

| Field | Value |
|-------|-------|
| **Title** | `RachioSense Daily Summary` |
| **Body** | `{N} sensors healthy · {N} low · driest: {SensorName} at {X}%` |
| **Identifier** | `daily-summary` (replace on each schedule) |

### H. Weekly Report *(not implemented)*
Toggle + day picker exist. Same approach as daily summary but with `UNCalendarNotificationTrigger` using `weekday:`.

---

## Timing & Cooldown Rules

### Background Refresh
- Interval requested: 10 minutes (`refreshInterval`)
- Actual iOS delivery: typically 15–60 min depending on usage patterns and battery
- Registered identifier: `com.rachiosense.app.refresh`
- Info.plist: `BGTaskSchedulerPermittedIdentifiers` ✅, `background-fetch` mode ✅

### Cooldown
Per-sensor cooldown stored as `Date` in UserDefaults under key `notif_last_sent_{type}_{eui}`.

| Alert Type | Default Cooldown | Rationale |
|------------|-----------------|-----------|
| Critical | 4h (configurable) | Soil dries slowly; 4h is roughly 4–8 refresh cycles |
| Low | 4h (configurable) | Same |
| Predictive critical | 4h (configurable) | Avoids repeated "going critical" during long dry spell |
| Predictive dry | 4h (configurable) | Same |
| Sensor offline | 12h (hardcoded) | Offline state persists; once per half-day is enough |

Cooldown hours are user-configurable in Settings → Notifications → Cooldown (2 / 4 / 6 / 12 / 24h).

### Quiet Hours
Stored in UserDefaults as `Int` hour values (0–23). Default off.
- `quietHoursEnabled` — master switch
- `quietHoursStartHour` — default 22 (10 PM)
- `quietHoursEndHour` — default 7 (7 AM)
- Overnight ranges handled correctly (e.g. 22–7 wraps midnight)

### Alert Window (Predictive)
Configurable in Settings → Notifications → Sensor Alerts → Alert window.
- Options: 2 / 4 / 6 / 12 hours
- Default: 6 hours
- Stored as `Int` in `predictiveAlertWindowHours`

---

## Settings UI Inventory

**Settings → Notifications** (`NotificationsSettingsView`)

### Sensor Alerts section
| Control | Key | Default | Wired? |
|---------|-----|---------|--------|
| Critical Alerts toggle | `dryAlertsEnabled` | on | ✅ |
| Low Alerts toggle | `lowAlertsEnabled` | on | ✅ |
| Sensor Offline toggle | `sensorOfflineEnabled` | on | ❌ no code |
| Predictive Alerts toggle | `predictiveAlertEnabled` | on | ✅ |
| Alert window picker | `predictiveAlertWindowHours` | 6h | ✅ |

### Cooldown section
| Control | Key | Default | Wired? |
|---------|-----|---------|--------|
| Alert cooldown picker | `notificationCooldownHours` | 4h | ✅ |

### Zone Activity section
| Control | Key | Default | Wired? |
|---------|-----|---------|--------|
| Zone Started toggle | `zoneStartedEnabled` | off | ❌ no code |
| Zone Stopped toggle | `zoneStoppedEnabled` | off | ❌ no code |
| Scheduled Run toggle | `scheduleRunEnabled` | off | ❌ no code |

### Summaries section
| Control | Key | Default | Wired? |
|---------|-----|---------|--------|
| Daily Summary toggle | `dailySummaryEnabled` | off | ❌ no code |
| Daily summary time picker | `dailySummaryHour` / `dailySummaryMinute` | 8:00 AM | ❌ |
| Weekly Report toggle | `weeklyReportEnabled` | off | ❌ no code |
| Weekly report day picker | `weeklyReportDay` | Monday | ❌ |

### Quiet Hours section
| Control | Key | Default | Wired? |
|---------|-----|---------|--------|
| Quiet Hours toggle | `quietHoursEnabled` | off | ✅ |
| From picker | `quietHoursStartHour` | 10 PM | ✅ |
| Until picker | `quietHoursEndHour` | 7 AM | ✅ |

---

## Implementation Priority

1. **Fix permission request + background scheduling** in `RachioSenseApp.swift` — ~10 lines, nothing works without this.
2. **Sensor Offline detection** in `BackgroundRefreshManager.performRefresh()` — track last-seen timestamp per EUI, fire alert if stale.
3. **Daily Summary** — schedule/reschedule a `UNCalendarNotificationTrigger` on foreground; compute body from latest SwiftData readings.
4. **Zone Started/Stopped** — blocked on Rachio webhook pipeline; can poll as a workaround.
5. **Weekly Report** — same pattern as daily summary.

---

## Testing on Device

iOS does not fire background tasks on demand. Use the Xcode debugger pause trick to simulate:

1. Run app on device via Xcode
2. Put app in background
3. In Xcode, pause execution and run in the debugger console:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.rachiosense.app.refresh"]
   ```
4. Resume — the background handler fires immediately

Alternatively, use the Environment Overrides in Xcode to force background task execution from the Debug menu.
