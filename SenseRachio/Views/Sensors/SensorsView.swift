import SwiftUI
import SwiftData

struct SensorsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SensorsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading sensors...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.sensors.isEmpty {
                    emptySensorsView
                } else {
                    sensorsList
                }
            }
            .navigationTitle("Sensors")
            .overlay(alignment: .top) {
                if let message = viewModel.errorMessage {
                    InlineBanner(message: message, color: .red)
                        .padding(.top, 4)
                }
            }
        }
        .task {
            await viewModel.loadSensors(modelContext: modelContext)
        }
    }

    // MARK: - Sensors List

    private var sensorsList: some View {
        List {
            if let message = viewModel.errorMessage {
                InlineBanner(message: message, color: .red)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(viewModel.sensors) { sensor in
                SensorRowView(
                    sensor: sensor,
                    reading: viewModel.readings[sensor.eui]
                )
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadSensors(modelContext: modelContext)
        }
    }

    // MARK: - Empty State

    private var emptySensorsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Sensors Found")
                .font(.title2.bold())
            Text("No devices were found in your SenseCraft account. Make sure your sensors are registered and active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Refresh") {
                Task { await viewModel.loadSensors(modelContext: modelContext) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await viewModel.loadSensors(modelContext: modelContext)
        }
    }
}

#Preview {
    SensorsView()
}
