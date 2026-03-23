import SwiftUI
import SwiftData

struct ZonesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ZonesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading zones...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.devices.isEmpty {
                    emptyZonesView
                } else {
                    zonesList
                }
            }
            .navigationTitle("Zones")
            .overlay(alignment: .top) {
                if let message = viewModel.errorMessage {
                    InlineBanner(message: message, color: .red)
                        .padding(.top, 4)
                }
            }
        }
        .task {
            await viewModel.loadZones(modelContext: modelContext)
        }
    }

    // MARK: - Zones List

    private var zonesList: some View {
        List {
            if let message = viewModel.errorMessage {
                InlineBanner(message: message, color: .red)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(viewModel.devices) { device in
                Section(device.name) {
                    ForEach(device.zones.filter(\.enabled)) { zone in
                        ZoneRowView(
                            zone: zone,
                            isActive: viewModel.activeZoneId == zone.id,
                            onStart: { duration in
                                Task {
                                    await viewModel.startZone(id: zone.id, duration: duration, modelContext: modelContext)
                                }
                            },
                            onStop: {
                                Task {
                                    await viewModel.stopZone(id: zone.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadZones(modelContext: modelContext)
        }
    }

    // MARK: - Empty State

    private var emptyZonesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "drop.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Zones Found")
                .font(.title2.bold())
            Text("No irrigation devices were found in your Rachio account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Refresh") {
                Task { await viewModel.loadZones(modelContext: modelContext) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await viewModel.loadZones(modelContext: modelContext)
        }
    }
}

#Preview {
    ZonesView()
}
