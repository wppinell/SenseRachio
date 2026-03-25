import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ScrollView {
                        VStack(spacing: DS.Spacing.md) {
                            DSLoadingState(label: "Loading dashboard…")
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                    }
                    .dsBackground()
                } else {
                    mainContent
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.load(modelContext: modelContext)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Error banner
                if let message = viewModel.errorMessage {
                    DSInlineBanner(message: message, style: .error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                }

                // Summary Stats
                DSSectionHeader(title: "Overview")

                HStack(spacing: DS.Spacing.md) {
                    DSStatCard(
                        icon: "sensor.fill",
                        iconColor: DS.Color.accent,
                        value: "\(viewModel.totalSensors)",
                        label: viewModel.totalSensors == 1 ? "Sensor" : "Sensors"
                    )
                    DSStatCard(
                        icon: "drop.fill",
                        iconColor: DS.Color.online,
                        value: "\(viewModel.enabledZonesCount)",
                        label: viewModel.enabledZonesCount == 1 ? "Zone" : "Zones"
                    )
                }
                .padding(.horizontal, DS.Spacing.lg)

                // Driest Sensor
                if let driest = viewModel.sensorReadings.min(by: { $0.moisture < $1.moisture }) {
                    DSSectionHeader(title: "Attention Required")
                    DriestSensorCardView(reading: driest, tempUnit: tempUnit)
                        .padding(.horizontal, DS.Spacing.lg)
                } else if appState.hasSenseCraftCredentials {
                    DSSectionHeader(title: "Sensors")
                    DSEmptyState(
                        icon: "sensor.fill",
                        title: "No Readings Yet",
                        message: "Pull down to refresh sensor data.",
                        action: { Task { await viewModel.load(modelContext: modelContext) } },
                        actionLabel: "Refresh"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                }

                // All Sensors Summary
                if viewModel.sensorReadings.count > 1 {
                    DSSectionHeader(title: "All Sensors", count: viewModel.sensorReadings.count)
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(viewModel.sensorReadings.sorted(by: { $0.moisture < $1.moisture }), id: \.eui) { reading in
                            SensorSummaryRow(reading: reading, tempUnit: tempUnit)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }

                // Devices
                if !viewModel.zones.isEmpty {
                    DSSectionHeader(title: "Irrigation Devices", count: viewModel.zones.count)
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(viewModel.zones) { device in
                            DeviceSummaryCard(device: device)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                } else if appState.hasRachioCredentials {
                    DSSectionHeader(title: "Irrigation")
                    DSEmptyState(
                        icon: "drop.fill",
                        title: "No Devices Found",
                        message: "No Rachio devices in your account.",
                        action: { Task { await viewModel.load(modelContext: modelContext) } }
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                }

                if !appState.hasAnyCredentials {
                    DSSectionHeader(title: "Get Started")
                    DSEmptyState(
                        icon: "leaf.fill",
                        title: "No Services Connected",
                        message: "Add your SenseCraft and Rachio credentials in Settings to get started."
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.load(modelContext: modelContext)
        }
    }
}

// MARK: - Driest Sensor Card

private struct DriestSensorCardView: View {
    let reading: SensorReading
    let tempUnit: String

    var tempDisplay: String {
        if tempUnit == "fahrenheit" {
            let f = reading.tempC * 9/5 + 32
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", reading.tempC)
    }

    var statusLabel: String {
        if reading.moisture < 25 { return "DRY" }
        if reading.moisture < 40 { return "LOW" }
        return "OK"
    }

    var statusColor: Color { DS.Color.moisture(reading.moisture) }

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            DSCircleGauge(value: reading.moisture, size: 80)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSBadge(text: statusLabel, color: statusColor)

                Text(reading.eui)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.md) {
                    Label(tempDisplay, systemImage: "thermometer")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Label(reading.recordedAt.relativeFormatted, systemImage: "clock")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }
}

// MARK: - Sensor Summary Row

private struct SensorSummaryRow: View {
    let reading: SensorReading
    let tempUnit: String

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSStatusDot(status: reading.moisture < 25 ? .offline : reading.moisture < 40 ? .warning : .online, size: 10)

            Text(reading.eui)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            DSMoistureBar(value: reading.moisture)
                .frame(width: 60)

            Text("\(Int(reading.moisture))%")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.moisture(reading.moisture))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .dsCard()
    }
}

// MARK: - Device Summary Card

private struct DeviceSummaryCard: View {
    let device: RachioDevice

    var enabledZones: Int { device.zones.filter(\.enabled).count }
    var statusColor: Color { device.on == true ? DS.Color.online : DS.Color.textTertiary }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSStatusDot(status: device.on == true ? .online : .offline, size: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("\(enabledZones) of \(device.zones.count) zones enabled")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Spacer()

            DSBadge(text: device.on == true ? "Online" : "Offline",
                    color: device.on == true ? DS.Color.online : DS.Color.textTertiary,
                    small: true)
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
