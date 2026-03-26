import SwiftUI
import SwiftData

struct ZoneDetailView: View {
    let zone: RachioZone
    let isActive: Bool
    let onStart: (Int) -> Void
    let onStop: () -> Void

    @Query private var sensors: [SensorConfig]
    @Query(sort: \ZoneGroup.sortOrder) private var groups: [ZoneGroup]
    @AppStorage(AppStorageKey.durationUnit) private var durationUnit = "minutes"

    @State private var selectedDuration = 10
    private let durations = [5, 10, 15, 20, 30]

    private var linkedSensors: [SensorConfig] {
        sensors.filter { $0.linkedZoneId == zone.id }
    }

    private var zoneGroup: ZoneGroup? {
        groups.first(where: { $0.assignedZoneIds.contains(zone.id) })
    }

    private var lastWateredDate: Date? {
        guard let epochMs = zone.lastWateredDate else { return nil }
        return Date(timeIntervalSince1970: Double(epochMs) / 1000)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header Card
                headerCard
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)

                // Start/Stop + Duration
                DSSectionHeader(title: "Control")
                controlCard
                    .padding(.horizontal, DS.Spacing.lg)

                // Run History
                DSSectionHeader(title: "Run History")
                runHistoryCard
                    .padding(.horizontal, DS.Spacing.lg)

                // Linked Sensors
                if !linkedSensors.isEmpty {
                    DSSectionHeader(title: "Linked Sensors", count: linkedSensors.count)
                    linkedSensorsCard
                        .padding(.horizontal, DS.Spacing.lg)
                }

                // Group
                if let group = zoneGroup {
                    DSSectionHeader(title: "Group")
                    groupCard(group: group)
                        .padding(.horizontal, DS.Spacing.lg)
                }

                // Schedule Info
                DSSectionHeader(title: "Schedule")
                scheduleCard
                    .padding(.horizontal, DS.Spacing.lg)

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.badge)
                    .fill(isActive ? DS.Color.online : DS.Color.accent.opacity(0.12))
                Text("\(zone.zoneNumber ?? 0)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : DS.Color.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(zone.name)
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    DSBadge(
                        text: isActive ? "Running" : "Idle",
                        color: isActive ? DS.Color.online : DS.Color.textTertiary,
                        small: true
                    )
                }
                if let date = lastWateredDate {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("Last watered \(date.relativeFormatted)")
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                }
                if let dur = zone.lastWateredDuration {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                        Text(formatDuration(dur))
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Control Card

    private var controlCard: some View {
        VStack(spacing: DS.Spacing.lg) {
            if isActive {
                DSPrimaryButton(
                    label: "Stop Zone",
                    icon: "stop.fill",
                    isDestructive: true,
                    action: onStop
                )
            } else {
                // Duration picker
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Duration")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(durations, id: \.self) { minutes in
                            Button {
                                selectedDuration = minutes
                                HapticFeedback.impact(.light)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(minutes)")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                    Text("min")
                                        .font(DS.Font.footnote)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(selectedDuration == minutes ? DS.Color.accent : DS.Color.background)
                                .foregroundStyle(selectedDuration == minutes ? .white : DS.Color.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                            }
                        }
                    }
                }

                DSPrimaryButton(label: "Start Zone", icon: "play.fill") {
                    onStart(selectedDuration * 60)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Run History Card

    private var runHistoryCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Last 7 days")
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)

            if let date = lastWateredDate,
               Date().timeIntervalSince(date) < 7 * 86400 {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(DS.Color.textPrimary)
                        if let dur = zone.lastWateredDuration {
                            Text(formatDuration(dur))
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    Spacer()
                    DSBadge(text: "Completed", color: DS.Color.online, small: true)
                }
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No runs in the last 7 days")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Linked Sensors Card

    private var linkedSensorsCard: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(linkedSensors) { sensor in
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "sensor.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sensor.name)
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(sensor.eui)
                            .font(DS.Font.mono)
                            .foregroundStyle(DS.Color.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if sensor.autoWaterEnabled {
                        Label("Auto", systemImage: "drop.fill")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.online)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                if sensor.id != linkedSensors.last?.id {
                    Divider().padding(.leading, DS.Spacing.lg)
                }
            }
        }
        .dsCard()
    }

    // MARK: - Group Card

    private func groupCard(group: ZoneGroup) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: group.iconName)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28, height: 28)
                .background(DS.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(group.name)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)

            Spacer()

            Text("\(group.assignedZoneIds.count) zones")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Schedule Card

    private var scheduleCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "calendar")
                .foregroundStyle(DS.Color.textTertiary)
            Text("Schedule information is managed in the Rachio app")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        switch durationUnit {
        case "seconds":
            return "\(seconds)s"
        case "hoursMinutes":
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        default:
            let m = seconds / 60
            let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
    }
}

// MARK: - Date Extension


