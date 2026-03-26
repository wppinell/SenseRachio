import SwiftUI
import SwiftData

struct SensorsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SensorsViewModel()
    @Query(sort: \ZoneGroup.sortOrder) private var groups: [ZoneGroup]
    @State private var moistureFilter: MoistureFilter = .all
    @State private var selectedGroupId: String? = nil

    enum MoistureFilter: String, CaseIterable {
        case all = "All"
        case dry = "Dry"
        case ok  = "OK"
    }

    private var filteredSensors: [SensorConfig] {
        var result = viewModel.sensors

        // Moisture filter
        switch moistureFilter {
        case .dry:
            result = result.filter { sensor in
                guard let r = viewModel.readings[sensor.eui] else { return false }
                return r.moisture < 40
            }
        case .ok:
            result = result.filter { sensor in
                guard let r = viewModel.readings[sensor.eui] else { return false }
                return r.moisture >= 40
            }
        case .all:
            break
        }

        // Group filter
        if let groupId = selectedGroupId {
            result = result.filter { $0.groupId == groupId }
        }

        return result
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

                // Filter chips: All | Dry | OK + optional group chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        // Moisture status chips
                        ForEach(MoistureFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                label: filter.rawValue,
                                icon: chipIcon(for: filter),
                                isSelected: moistureFilter == filter
                            ) {
                                moistureFilter = filter
                            }
                        }

                        // Group chips (if groups exist)
                        if !groups.isEmpty {
                            Divider()
                                .frame(height: 20)
                                .padding(.horizontal, DS.Spacing.xs)

                            GroupChip(label: "All Groups", isSelected: selectedGroupId == nil) {
                                selectedGroupId = nil
                            }
                            ForEach(groups) { group in
                                GroupChip(label: group.name, isSelected: selectedGroupId == group.id) {
                                    selectedGroupId = selectedGroupId == group.id ? nil : group.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }
                .padding(.vertical, DS.Spacing.md)

                // Sensor count
                DSSectionHeader(title: "Sensors", count: filteredSensors.count)

                if filteredSensors.isEmpty {
                    DSEmptyState(
                        icon: "sensor.fill",
                        title: moistureFilter == .all ? "No Sensors Found" : "No \(moistureFilter.rawValue) Sensors",
                        message: moistureFilter == .all
                            ? "No devices were found. Make sure your sensors are registered and active."
                            : "No sensors match the current filter.",
                        action: moistureFilter == .all ? { Task { await viewModel.loadSensors(modelContext: modelContext) } } : nil,
                        actionLabel: "Refresh"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(filteredSensors) { sensor in
                            NavigationLink {
                                SensorDetailView(
                                    sensor: sensor,
                                    reading: viewModel.readings[sensor.eui]
                                )
                            } label: {
                                SensorRowView(
                                    sensor: sensor,
                                    reading: viewModel.readings[sensor.eui]
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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

    private func chipIcon(for filter: MoistureFilter) -> String? {
        switch filter {
        case .all: return nil
        case .dry: return "exclamationmark.circle.fill"
        case .ok:  return "checkmark.circle.fill"
        }
    }
}

// MARK: - Filter Chip (with optional icon)

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(DS.Font.label)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isSelected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs + 2)
            .background(isSelected ? DS.Color.accent : DS.Color.card)
            .clipShape(Capsule())
            .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : DS.Color.cardShadow, radius: 2)
        }
    }
}

// MARK: - Group Chip

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
                .background(isSelected ? DS.Color.accent.opacity(0.7) : DS.Color.card)
                .clipShape(Capsule())
                .shadow(color: isSelected ? DS.Color.accent.opacity(0.2) : DS.Color.cardShadow, radius: 2)
        }
    }
}

#Preview {
    SensorsView()
}
