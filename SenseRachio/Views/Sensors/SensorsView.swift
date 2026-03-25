import SwiftUI
import SwiftData

struct SensorsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SensorsViewModel()
    @Query(sort: \SensorGroup.sortOrder) private var groups: [SensorGroup]
    @State private var selectedGroupId: String? = nil

    private var filteredSensors: [SensorConfig] {
        guard let groupId = selectedGroupId else { return viewModel.sensors }
        return viewModel.sensors.filter { $0.groupId == groupId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ScrollView {
                        DSLoadingState(label: "Loading sensors…")
                            .padding(DS.Spacing.lg)
                    }
                    .dsBackground()
                } else {
                    mainContent
                }
            }
            .navigationTitle("Sensors")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadSensors(modelContext: modelContext)
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Error
                if let message = viewModel.errorMessage {
                    DSInlineBanner(message: message, style: .error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                }

                // Group filter chips
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            GroupChip(label: "All", isSelected: selectedGroupId == nil) {
                                selectedGroupId = nil
                            }
                            ForEach(groups) { group in
                                GroupChip(label: group.name, isSelected: selectedGroupId == group.id) {
                                    selectedGroupId = selectedGroupId == group.id ? nil : group.id
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.vertical, DS.Spacing.md)
                }

                // Sensor count
                DSSectionHeader(title: "Sensors", count: filteredSensors.count)

                if filteredSensors.isEmpty {
                    DSEmptyState(
                        icon: "sensor.fill",
                        title: "No Sensors Found",
                        message: "No devices were found in your SenseCraft account. Make sure your sensors are registered and active.",
                        action: { Task { await viewModel.loadSensors(modelContext: modelContext) } },
                        actionLabel: "Refresh"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(filteredSensors) { sensor in
                            SensorRowView(
                                sensor: sensor,
                                reading: viewModel.readings[sensor.eui]
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.loadSensors(modelContext: modelContext)
        }
    }
}

// MARK: - Group Filter Chip

private struct GroupChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.label)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(isSelected ? DS.Color.accent : DS.Color.card)
                .clipShape(Capsule())
                .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : DS.Color.cardShadow, radius: 2)
        }
    }
}

#Preview {
    SensorsView()
}
