import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"

    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40

    @Query private var sensorConfigs: [SensorConfig]
    
    private var sensorNameByEUI: [String: String] {
        Dictionary(uniqueKeysWithValues: sensorConfigs.map { ($0.eui, $0.displayName) })
    }


    
    // Visible sensors only (exclude hidden)
    private var hiddenEUIs: Set<String> {
        Set(sensorConfigs.filter { $0.isHiddenFromGraphs }.map { $0.eui })
    }
    private var visibleReadings: [SensorReading] {
        viewModel.sensorReadings.filter { !hiddenEUIs.contains($0.eui) }
    }
    
    // Sensor lists by status (visible only)
    private var criticalSensors: [SensorReading] {
        visibleReadings.filter { $0.moisture < autoWaterThreshold }.sorted { $0.moisture < $1.moisture }
    }
    private var drySensors: [SensorReading] {
        visibleReadings.filter { $0.moisture >= autoWaterThreshold && $0.moisture < dryThreshold }.sorted { $0.moisture < $1.moisture }
    }
    private var okCount: Int {
        visibleReadings.filter { $0.moisture >= dryThreshold && $0.moisture < highThreshold }.count
    }
    private var highSensors: [SensorReading] {
        visibleReadings.filter { $0.moisture >= highThreshold }.sorted { $0.moisture > $1.moisture }
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
                if visibleReadings.isEmpty {
                    HStack {
                        Image(systemName: "sensor.fill")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(appState.hasSenseCraftCredentials ? "No readings yet — pull to refresh" : "Connect SenseCraft in Settings")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    // Critical sensors
                    if !criticalSensors.isEmpty {
                        SensorStatusSection(
                            title: "Critical",
                            icon: "exclamationmark.triangle.fill",
                            color: DS.Color.error,
                            sensors: criticalSensors,
                            nameByEUI: sensorNameByEUI
                        )
                    }
                    
                    // Dry sensors
                    if !drySensors.isEmpty {
                        SensorStatusSection(
                            title: "Dry",
                            icon: "exclamationmark.circle.fill",
                            color: DS.Color.warning,
                            sensors: drySensors,
                            nameByEUI: sensorNameByEUI
                        )
                    }
                    
                    // High sensors
                    if !highSensors.isEmpty {
                        SensorStatusSection(
                            title: "High",
                            icon: "drop.fill",
                            color: Color(hex: "0EA5E9"),
                            sensors: highSensors,
                            nameByEUI: sensorNameByEUI
                        )
                    }
                    
                    // OK summary (just count, not individual sensors)
                    if okCount > 0 && criticalSensors.isEmpty && drySensors.isEmpty && highSensors.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DS.Color.online)
                            Text("All \(okCount) sensors OK")
                                .font(DS.Font.cardBody)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    } else if okCount > 0 {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Color.online)
                            Text("\(okCount) OK")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }

                }
            }
            .padding(DS.Spacing.lg)
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

            WeatherForecastCard(tempUnit: tempUnit)
                .padding(.horizontal, DS.Spacing.lg)
        }
    }
}

// MARK: - Weather Forecast Card

private struct WeatherForecastCard: View {
    let tempUnit: String
    @State private var forecast: WeatherAPI.Forecast?
    @State private var isLoading = true
    @State private var error: String?
    
    // Default to Phoenix, AZ — could be made configurable
    private let latitude = 33.4484
    private let longitude = -112.0740
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading…")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .frame(height: 70)
            } else if let forecast {
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    // Current conditions (compact)
                    compactCurrentView(forecast.current)
                    
                    Divider()
                        .frame(height: 50)
                    
                    // 7-day forecast (compact)
                    HStack(spacing: 0) {
                        ForEach(Array(forecast.daily.enumerated()), id: \.element.id) { index, day in
                            compactDayView(day, isToday: index == 0)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
            } else if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Color.warning)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .frame(height: 50)
            }
        }
        .dsCard()
        .task {
            await loadForecast()
        }
    }
    
    private func loadForecast() async {
        do {
            forecast = try await WeatherAPI.shared.fetchForecast(latitude: latitude, longitude: longitude)
            isLoading = false
        } catch {
            self.error = "Unable to load forecast"
            isLoading = false
        }
    }
    
    @ViewBuilder
    private func compactCurrentView(_ current: WeatherAPI.CurrentWeather) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: current.icon)
                .font(.system(size: 24))
                .foregroundStyle(iconColor(for: current.weatherCode))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(formatTemp(current.temperature))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.textPrimary)
                Text("\(current.humidity)%")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .frame(minWidth: 70)
    }
    
    @ViewBuilder
    private func compactDayView(_ day: WeatherAPI.DailyForecast, isToday: Bool) -> some View {
        VStack(spacing: 2) {
            Text(shortDayLabel(day.date, isToday: isToday))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Color.textTertiary)
            
            Image(systemName: day.icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor(for: day.weatherCode))
            
            Text("\(Int(day.highTemp))°")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
            
            Text("\(Int(day.lowTemp))°")
                .font(.system(size: 9))
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shortDayLabel(_ date: Date, isToday: Bool) -> String {
        if isToday { return "TOD" }
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) { return "TOM" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased().prefix(2).description
    }
    
    private func formatTemp(_ temp: Double) -> String {
        if tempUnit == "celsius" {
            let c = (temp - 32) * 5 / 9
            return "\(Int(c))°"
        }
        return "\(Int(temp))°"
    }
    
    private func iconColor(for code: Int) -> Color {
        switch code {
        case 0: return .yellow           // Clear
        case 1, 2, 3: return .orange     // Partly cloudy
        case 61, 63, 65, 80, 81, 82: return Color(hex: "0EA5E9")  // Rain
        case 95, 96, 99: return .purple  // Thunderstorm
        default: return DS.Color.textSecondary
        }
    }
}

// MARK: - Sensor Status Section

private struct SensorStatusSection: View {
    let title: String
    let icon: String
    let color: Color
    let sensors: [SensorReading]
    let nameByEUI: [String: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Header
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(title)
                    .font(DS.Font.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            // Sensor list
            ForEach(sensors, id: \.eui) { reading in
                HStack {
                    Text(nameByEUI[reading.eui] ?? String(reading.eui.suffix(4)))
                        .font(DS.Font.cardBody)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Spacing.sm)
                    Text("\(Int(reading.moisture))%")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(color)
                        .monospacedDigit()
                }
            }
        }
        .padding(DS.Spacing.sm)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}



#Preview {
    DashboardView()
        .environmentObject(AppState())
}
