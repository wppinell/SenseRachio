import SwiftUI

struct GraphsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.trendChartPeriod) private var chartPeriod = "4d"

    @State private var viewModel = GraphsViewModel()
    @State private var syncFlash: Bool = false

    private func events(forZoneName zoneName: String) -> [RachioWateringEvent] {
        viewModel.wateringEvents.filter {
            $0.zoneName.localizedCaseInsensitiveContains(zoneName) ||
            zoneName.localizedCaseInsensitiveContains($0.zoneName)
        }
    }

    private func events(forSensors sensors: [SensorConfig]) -> [RachioWateringEvent] {
        // For multi-sensor cards, union events from all linked zone names
        let zoneNames = Set(sensors.compactMap { sensor -> String? in
            guard let zoneId = sensor.linkedZoneId else { return nil }
            return viewModel.zoneConfigs.first(where: { $0.id == zoneId })?.name
        })
        return viewModel.wateringEvents.filter { event in
            zoneNames.contains(where: {
                event.zoneName.localizedCaseInsensitiveContains($0) ||
                $0.localizedCaseInsensitiveContains(event.zoneName)
            })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !appState.hasSenseCraftCredentials {
                    DSEmptyState(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "SenseCap Not Connected",
                        message: "Connect your SenseCap account in Settings to view sensor graphs."
                    )
                } else if viewModel.isLoading {
                    DSLoadingState(label: "Loading sensor data…")
                } else {
                    graphsScrollContent
                }
            }
            .navigationTitle("Graphs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .task {
                await viewModel.load(modelContext: modelContext)
            }
            .refreshable {
                guard !viewModel.isFetchingData else { return }
                await viewModel.forceRefresh(modelContext: modelContext)
            }
            // Removed: onChange of chartPeriod was triggering duplicate fetches
            // Users can pull-to-refresh manually if needed after changing period
        }
    }
    
    // MARK: - Background Refresh
    
    // MARK: - Graphs Content

    @ViewBuilder
    private var graphsScrollContent: some View {
        let hasAnySensors = !viewModel.zonesWithLinkedSensors.isEmpty || !viewModel.unlinkedSensors.isEmpty

        if !hasAnySensors && viewModel.zoneGroups.isEmpty {
            DSEmptyState(
                icon: "chart.xyaxis.line",
                title: "No Sensors",
                message: "No sensors available. Load sensors from the Sensors tab or check visibility settings."
            )
        } else {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    if viewModel.zoneGroups.isEmpty {
                        // Default: one graph per zone that has linked sensors
                        ForEach(viewModel.zonesWithLinkedSensors) { zone in
                            SensorGraphCard(
                                title: zone.name,
                                sensors: viewModel.sensors(linkedTo: zone.id),
                                readingsByEUI: viewModel.readingsByEUI,
                                wateringEvents: events(forZoneName: zone.name),
                                                                chartPeriod: $chartPeriod,
                                isFetching: viewModel.isFetchingData,
                                syncFlash: $syncFlash
                            )
                        }
                        if !viewModel.unlinkedSensors.isEmpty {
                            SensorGraphCard(
                                title: "Unlinked Sensors",
                                sensors: viewModel.unlinkedSensors,
                                readingsByEUI: viewModel.readingsByEUI,
                                wateringEvents: [],
                                                                chartPeriod: $chartPeriod,
                                isFetching: viewModel.isFetchingData,
                                syncFlash: $syncFlash
                            )
                        }
                    } else {
                        // One graph per zone group
                        ForEach(viewModel.zoneGroups) { group in
                            let groupSensors = viewModel.sensors(forGroup: group)
                            if !groupSensors.isEmpty {
                                SensorGraphCard(
                                    title: group.name,
                                    sensors: groupSensors,
                                    readingsByEUI: viewModel.readingsByEUI,
                                wateringEvents: events(forSensors: groupSensors),
                                                                        chartPeriod: $chartPeriod,
                                isFetching: viewModel.isFetchingData,
                                syncFlash: $syncFlash
                                )
                            }
                        }
                        // Plus: zones NOT in any group
                        ForEach(viewModel.zonesNotInAnyGroup) { zone in
                            SensorGraphCard(
                                title: zone.name,
                                sensors: viewModel.sensors(linkedTo: zone.id),
                                readingsByEUI: viewModel.readingsByEUI,
                                wateringEvents: events(forZoneName: zone.name),
                                                                chartPeriod: $chartPeriod,
                                isFetching: viewModel.isFetchingData,
                                syncFlash: $syncFlash
                            )
                        }
                        if !viewModel.unlinkedSensors.isEmpty {
                            SensorGraphCard(
                                title: "Unlinked Sensors",
                                sensors: viewModel.unlinkedSensors,
                                readingsByEUI: viewModel.readingsByEUI,
                                wateringEvents: [],
                                                                chartPeriod: $chartPeriod,
                                isFetching: viewModel.isFetchingData,
                                syncFlash: $syncFlash
                            )
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.lg)
            }
            .dsBackground()
        }
    }
}

#Preview {
    GraphsView()
        .environmentObject(AppState())
}
