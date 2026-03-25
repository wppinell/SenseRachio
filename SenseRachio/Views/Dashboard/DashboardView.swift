import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"
    @AppStorage(AppStorageKey.rainSkipEnabled) private var rainSkip = true
    @AppStorage(AppStorageKey.freezeSkipEnabled) private var freezeSkip = true
    @AppStorage(AppStorageKey.windSkipEnabled) private var windSkip = false
    @AppStorage(AppStorageKey.rainSkipThreshold) private var rainThreshold = 6.0
    @AppStorage(AppStorageKey.freezeSkipThreshold) private var freezeThreshold = 2.0
    @AppStorage(AppStorageKey.windSkipThreshold) private var windThreshold = 30.0

    @Query(sort: \SensorReading.recordedAt) private var storedReadings: [SensorReading]

    private var top4Sensors: [SensorReading] {
        Array(viewModel.sensorReadings.sorted(by: { $0.moisture < $1.moisture }).prefix(4))
    }

    private var allEnabledZones: [RachioZone] {
        viewModel.zones.flatMap(\.zones).filter(\.enabled)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ScrollView {
                        DSLoadingState(label: "Loading dashboard…")
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.lg)
                    }
                    .dsBackground()
                } else {
                    mainContent
                }
            }
            .navigationTitle("🌱 RachioSense")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.zones.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        devicePickerMenu
                    }
                }
            }
        }
        .task {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - Device Picker

    @ViewBuilder
    private var devicePickerMenu: some View {
        Menu {
            ForEach(viewModel.zones) { device in
                Label(device.name, systemImage: device.on == true ? "wifi" : "wifi.slash")
            }
        } label: {
            HStack(spacing: 4) {
                if let first = viewModel.zones.first {
                    Text(first.name)
                        .font(DS.Font.label)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DS.Color.accent)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = viewModel.errorMessage {
                    DSInlineBanner(message: message, style: .error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                }

                if !appState.hasAnyCredentials {
                    DSSectionHeader(title: "Get Started")
                    DSEmptyState(
                        icon: "leaf.fill",
                        title: "No Services Connected",
                        message: "Add your SenseCraft and Rachio credentials in Settings to get started."
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    moistureCard
                    zonesCard
                    weatherCard
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - MOISTURE Card

    private var moistureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MOISTURE")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)
                Spacer()
                Button {
                    appState.selectedTab = 1
                } label: {
                    Text("See All →")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if top4Sensors.isEmpty {
                    HStack {
                        Image(systemName: "sensor.fill")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(appState.hasSenseCraftCredentials ? "No readings yet — pull to refresh" : "Connect SenseCraft in Settings")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    // Sensor dots — top 4 sensors
                    HStack(spacing: DS.Spacing.lg) {
                        ForEach(top4Sensors, id: \.eui) { reading in
                            MoistureDotView(reading: reading)
                        }
                        Spacer()
                    }

                    // 24h trend sparkline
                    let cutoff = Date().addingTimeInterval(-86400)
                    let trendData = storedReadings
                        .filter { $0.recordedAt >= cutoff }
                        .map { ($0.recordedAt, $0.moisture) }
                        .sorted(by: { $0.0 < $1.0 })

                    if trendData.count >= 2 {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("24h trend")
                                .font(DS.Font.footnote)
                                .foregroundStyle(DS.Color.textTertiary)
                            Chart {
                                ForEach(trendData, id: \.0) { point in
                                    AreaMark(
                                        x: .value("Time", point.0),
                                        y: .value("Moisture", point.1)
                                    )
                                    .foregroundStyle(DS.Color.accent.opacity(0.15))
                                    LineMark(
                                        x: .value("Time", point.0),
                                        y: .value("Moisture", point.1)
                                    )
                                    .foregroundStyle(DS.Color.accent)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .frame(height: 56)
                            .chartYScale(domain: 0...100)
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                        }
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .dsCard()
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - ZONES Card

    private var zonesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ZONES")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)
                Spacer()
                Button {
                    appState.selectedTab = 2
                } label: {
                    Text("See All →")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)

            VStack(spacing: 1) {
                if allEnabledZones.isEmpty {
                    HStack {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(appState.hasRachioCredentials ? "No zones found — pull to refresh" : "Connect Rachio in Settings")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .padding(DS.Spacing.md)
                } else {
                    ForEach(allEnabledZones.prefix(5)) { zone in
                        ZoneSummaryRow(zone: zone)
                        if zone.id != allEnabledZones.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, DS.Spacing.lg)
                        }
                    }
                    if allEnabledZones.count > 5 {
                        Button {
                            appState.selectedTab = 2
                        } label: {
                            Text("+ \(allEnabledZones.count - 5) more zones")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.accent)
                                .padding(DS.Spacing.md)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .dsCard()
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - WEATHER Card

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WEATHER")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textSecondary)
                .tracking(0.8)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xs)

            DashboardWeatherCard(
                rainSkip: rainSkip,
                rainThreshold: rainThreshold,
                freezeSkip: freezeSkip,
                freezeThreshold: freezeThreshold,
                windSkip: windSkip,
                windThreshold: windThreshold,
                tempUnit: tempUnit
            )
            .padding(.horizontal, DS.Spacing.lg)
        }
    }
}

// MARK: - Moisture Dot View

private struct MoistureDotView: View {
    let reading: SensorReading

    private var color: Color { DS.Color.moisture(reading.moisture) }

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 54, height: 54)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(reading.moisture, 100)) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text("\(Int(reading.moisture))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            Text(String(reading.eui.suffix(4)))
                .font(DS.Font.footnote)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Zone Summary Row

private struct ZoneSummaryRow: View {
    let zone: RachioZone

    private var lastWateredText: String {
        guard let epochMs = zone.lastWateredDate else { return "Never watered" }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28, height: 28)
                .background(DS.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(lastWateredText)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Spacer()

            DSBadge(text: "Idle", color: DS.Color.textTertiary, small: true)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

// MARK: - Dashboard Weather Card

private struct DashboardWeatherCard: View {
    let rainSkip: Bool
    let rainThreshold: Double
    let freezeSkip: Bool
    let freezeThreshold: Double
    let windSkip: Bool
    let windThreshold: Double
    let tempUnit: String

    private var activeSkips: [(icon: String, label: String, value: String)] {
        var skips: [(String, String, String)] = []
        if rainSkip   { skips.append(("cloud.rain.fill",       "Rain Skip",   ">\(Int(rainThreshold)) mm")) }
        if freezeSkip { skips.append(("thermometer.snowflake", "Freeze Skip", "<\(Int(freezeThreshold))°C")) }
        if windSkip   { skips.append(("wind",                  "Wind Skip",   ">\(Int(windThreshold)) km/h")) }
        return skips
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Current conditions row (placeholder — no live weather API)
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.Color.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weather Integration")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Configure source in Settings → Weather Integration")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            if !activeSkips.isEmpty {
                Divider()
                Text("SMART SKIPS ACTIVE")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)

                HStack(spacing: DS.Spacing.md) {
                    ForEach(activeSkips, id: \.label) { skip in
                        VStack(spacing: DS.Spacing.xs) {
                            Image(systemName: skip.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(DS.Color.accent)
                            Text(skip.label)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                                .multilineTextAlignment(.center)
                            Text(skip.value)
                                .font(DS.Font.label)
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.Color.textPrimary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                DSInlineBanner(
                    message: "Zones will skip scheduled runs when conditions exceed thresholds.",
                    style: .info
                )
            } else {
                Divider()
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Color.online)
                    Text("No skip conditions active")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
