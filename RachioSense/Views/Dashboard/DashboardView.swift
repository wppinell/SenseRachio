import SwiftUI
import SwiftData
import CoreLocation

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()
    @State private var locationName: String? = nil
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"

    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40
    @AppStorage(AppStorageKey.subscriptionAlertDays) private var subscriptionAlertDays: Int = 30

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
    
    // Sensors expiring within configured alert window
    private var expiringSensors: [(name: String, days: Int)] {
        sensorConfigs
            .filter { !$0.isHiddenFromGraphs }
            .compactMap { sensor -> (name: String, days: Int)? in
                guard let days = sensor.daysUntilExpiry, days <= subscriptionAlertDays else { return nil }
                return (name: sensor.displayName, days: days)
            }
            .sorted { $0.days < $1.days }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.zones.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        devicePickerMenu
                    }
                }
            }
        }
        .task {
            // Restore cached city name instantly
            locationName = UserDefaults.standard.string(forKey: "cached_city_name")
            await viewModel.load(modelContext: modelContext)
            await resolveLocationName()
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
                    weatherCard
                    alertsCard
                    statusCard
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - ALERTS Card

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ALERTS")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textSecondary)
                .tracking(0.8)
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
                } else if criticalSensors.isEmpty && drySensors.isEmpty && highSensors.isEmpty && expiringSensors.isEmpty && viewModel.rachioRateLimitMinutes == nil {
                    // All OK — show a clean green message
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Color.online)
                        Text("All \(okCount) sensors OK")
                            .font(DS.Font.cardBody)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    if !criticalSensors.isEmpty {
                        SensorStatusSection(title: "Critical", icon: "exclamationmark.triangle.fill", color: DS.Color.error, sensors: criticalSensors, nameByEUI: sensorNameByEUI)
                    }
                    if !drySensors.isEmpty {
                        SensorStatusSection(title: "Dry", icon: "exclamationmark.circle.fill", color: DS.Color.warning, sensors: drySensors, nameByEUI: sensorNameByEUI)
                    }
                    if !highSensors.isEmpty {
                        SensorStatusSection(title: "High", icon: "drop.fill", color: Color(hex: "0EA5E9"), sensors: highSensors, nameByEUI: sensorNameByEUI)
                    }
                    if !expiringSensors.isEmpty {
                        ExpiryAlertSection(sensors: expiringSensors)
                    }
                    if let mins = viewModel.rachioRateLimitMinutes {
                        RateLimitAlertSection(minutesRemaining: mins)
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .dsCard()
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - STATUS Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SYSTEM STATUS")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textSecondary)
                .tracking(0.8)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xs)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // SenseCraft row
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "sensor.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text("SenseCraft")
                                .font(DS.Font.cardTitle)
                            Circle()
                                .fill(viewModel.senseCraftConnected ? DS.Color.online : DS.Color.error)
                                .frame(width: 7, height: 7)
                            Text(viewModel.senseCraftConnected ? "Connected" : "Disconnected")
                                .font(DS.Font.caption)
                                .foregroundStyle(viewModel.senseCraftConnected ? DS.Color.online : DS.Color.error)
                        }
                        HStack(spacing: DS.Spacing.xs) {
                            Text("\(visibleReadings.count) sensors")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                            if let sync = viewModel.lastSyncDate {
                                Text("· synced \(sync.relativeFormatted)")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Rachio row
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text("Rachio")
                                .font(DS.Font.cardTitle)
                            Circle()
                                .fill(viewModel.rachioConnected ? DS.Color.online : DS.Color.error)
                                .frame(width: 7, height: 7)
                            Text(viewModel.rachioConnected ? "Connected" : "Disconnected")
                                .font(DS.Font.caption)
                                .foregroundStyle(viewModel.rachioConnected ? DS.Color.online : DS.Color.error)
                        }
                        HStack(spacing: DS.Spacing.xs) {
                            if let device = viewModel.zones.first {
                                Text("\(device.name) · \(viewModel.zones.flatMap(\.zones).filter(\.enabled).count) zones")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                            if let remaining = viewModel.rachioApiRemaining, let total = viewModel.rachioApiTotal {
                                Text("· \(remaining)/\(total) API")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(remaining < 100 ? DS.Color.warning : DS.Color.textTertiary)
                            }
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
            HStack {
                Text("WEATHER")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)
                Spacer()
                if let name = locationName {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text(name)
                            .font(DS.Font.footnote)
                    }
                    .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)

            WeatherForecastCard(forecast: viewModel.forecast, tempUnit: tempUnit)
                .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private func resolveLocationName() async {
        let location = await LocationManager.shared.getLocation()
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(clLocation).first {
            let name = placemark.locality ?? placemark.administrativeArea ?? placemark.country
            locationName = name
            // Cache for instant display next launch
            if let name { UserDefaults.standard.set(name, forKey: "cached_city_name") }
        }
    }
}

// MARK: - Weather Forecast Card

private struct WeatherForecastCard: View {
    let forecast: WeatherAPI.Forecast?
    let tempUnit: String
    
    var body: some View {
        VStack(spacing: 0) {
            if forecast == nil {
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
            }
        }
        .dsCard()
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

// MARK: - Rate Limit Alert Section

private struct RateLimitAlertSection: View {
    let minutesRemaining: Int
    
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 13))
                .foregroundStyle(DS.Color.error)
                .frame(width: 28, height: 28)
                .background(DS.Color.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rachio API Rate Limited")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.error)
                
                if minutesRemaining >= 60 {
                    let hours = minutesRemaining / 60
                    let mins = minutesRemaining % 60
                    Text("Resets in \(hours)h \(mins)m")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text("Resets in \(minutesRemaining) min")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.error.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Expiry Alert Section

private struct ExpiryAlertSection: View {
    let sensors: [(name: String, days: Int)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.warning)
                Text("Subscription Expiring")
                    .font(DS.Font.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Color.warning)
            }
            
            ForEach(sensors, id: \.name) { sensor in
                HStack {
                    Text(sensor.name)
                        .font(DS.Font.cardBody)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Spacing.sm)
                    Text(sensor.days <= 0 ? "Expired" : sensor.days == 1 ? "Tomorrow" : "\(sensor.days)d")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(sensor.days <= 7 ? DS.Color.error : DS.Color.warning)
                        .monospacedDigit()
                }
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.warning.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
