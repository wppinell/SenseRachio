import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading dashboard...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let message = viewModel.errorMessage {
                                InlineBanner(message: message, color: .red)
                            }

                            // Summary Cards
                            HStack(spacing: 12) {
                                SummaryCard(
                                    title: "Sensors",
                                    value: "\(viewModel.totalSensors)",
                                    icon: "sensor.fill",
                                    color: .blue
                                )
                                SummaryCard(
                                    title: "Zones",
                                    value: "\(viewModel.enabledZonesCount)",
                                    icon: "drop.fill",
                                    color: .cyan
                                )
                            }
                            .padding(.horizontal)

                            // Driest Sensor Card
                            if let driest = viewModel.sensorReadings.min(by: { $0.moisture < $1.moisture }) {
                                DriestSensorCard(reading: driest)
                                    .padding(.horizontal)
                            } else if appState.hasSenseCraftCredentials {
                                EmptyStateCard(
                                    icon: "sensor.fill",
                                    message: "No sensor readings yet.\nPull to refresh."
                                )
                                .padding(.horizontal)
                            }

                            // Active Zones
                            if !viewModel.zones.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Devices")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ForEach(viewModel.zones) { device in
                                        DeviceSummaryRow(device: device)
                                            .padding(.horizontal)
                                    }
                                }
                            }

                            Spacer(minLength: 20)
                        }
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await viewModel.load(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
        .task {
            await viewModel.load(modelContext: modelContext)
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.largeTitle.bold())
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Driest Sensor Card

struct DriestSensorCard: View {
    let reading: SensorReading

    var moistureColor: Color {
        if reading.moisture >= 40 { return .green }
        if reading.moisture >= 25 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Driest Sensor", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.eui)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(Int(reading.moisture))% moisture")
                        .font(.title2.bold())
                        .foregroundStyle(moistureColor)
                    Text("\(String(format: "%.1f", reading.tempC))°C")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(moistureColor.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: reading.moisture / 100)
                        .stroke(moistureColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Device Summary Row

struct DeviceSummaryRow: View {
    let device: RachioDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.name)
                .font(.subheadline.bold())
            Text("\(device.zones.filter(\.enabled).count) of \(device.zones.count) zones enabled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty State Card

struct EmptyStateCard: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Inline Banner

struct InlineBanner: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
