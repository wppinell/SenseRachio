import SwiftUI

struct GraphsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.trendChartPeriod) private var chartPeriod = "24h"

    @State private var viewModel = GraphsViewModel()
    @State private var selectedMode: GraphsMode = .graphs

    enum GraphsMode: String, CaseIterable {
        case graphs = "Graphs"
        case missionControl = "Mission Control"
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
                    DSLoadingState(message: "Loading sensor data…")
                } else {
                    mainContent
                }
            }
            .navigationTitle("Graphs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .task { await viewModel.load(modelContext: modelContext) }
            .refreshable { await viewModel.load(modelContext: modelContext) }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isMissionControlAvailable {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(GraphsMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.background)

                Divider()

                if selectedMode == .graphs {
                    graphsScrollContent
                } else {
                    MissionControlView(viewModel: viewModel)
                }
            }
            .dsBackground()
        } else {
            graphsScrollContent
        }
    }

    // MARK: - Graphs Scroll Content

    @ViewBuilder
    private var graphsScrollContent: some View {
        if viewModel.visibleSensors.isEmpty {
            DSEmptyState(
                icon: "chart.xyaxis.line",
                title: "No Sensors",
                message: "No sensors available. Load sensors from the Sensors tab or check visibility settings."
            )
        } else {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    let hasGroups = !viewModel.groupsWithSensors.isEmpty

                    if hasGroups {
                        // One card per group
                        ForEach(viewModel.groupsWithSensors) { group in
                            SensorGraphCard(
                                title: group.name,
                                sensors: viewModel.visibleSensors(inGroup: group.id),
                                readingsFor: { eui, period in
                                    viewModel.readings(for: eui, period: period)
                                },
                                chartPeriod: $chartPeriod
                            )
                        }
                        // Ungrouped sensors card (if any)
                        if !viewModel.ungroupedVisibleSensors.isEmpty {
                            SensorGraphCard(
                                title: "Other Sensors",
                                sensors: viewModel.ungroupedVisibleSensors,
                                readingsFor: { eui, period in
                                    viewModel.readings(for: eui, period: period)
                                },
                                chartPeriod: $chartPeriod
                            )
                        }
                    } else {
                        // No groups — single card with all sensors
                        SensorGraphCard(
                            title: "All Sensors",
                            sensors: viewModel.visibleSensors,
                            readingsFor: { eui, period in
                                viewModel.readings(for: eui, period: period)
                            },
                            chartPeriod: $chartPeriod
                        )
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
