import SwiftUI
import SwiftData

enum ZoneSortOrder: String, CaseIterable {
    case moisture = "Moisture"
    case name = "Name"
    case nextRun = "Next Run"
    case lastWatered = "Last Watered"
    case weeklyWater = "Weekly Watering"

    var icon: String {
        switch self {
        case .moisture:    return "drop.fill"
        case .name:        return "textformat.abc"
        case .nextRun:     return "clock.fill"
        case .lastWatered: return "calendar"
        case .weeklyWater: return "timer"
        }
    }
}

struct ZonesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sensorConfigs: [SensorConfig]
    @State private var viewModel = ZonesViewModel()
    @State private var showStopAllConfirmation = false
    @State private var latestMoisture: [String: Double] = [:] // keyed by zone id
    @AppStorage("zoneSortOrder") private var sortOrder: String = ZoneSortOrder.moisture.rawValue

    private var currentSort: ZoneSortOrder {
        ZoneSortOrder(rawValue: sortOrder) ?? .moisture
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    /// Get moisture value for a zone (from pre-loaded dict)
    private func avgMoisture(forZoneId zoneId: String) -> Double? {
        latestMoisture[zoneId]
    }

    /// Load latest reading per sensor and map to zones — done once after load, not on every render
    private func loadMoisture(modelContext: ModelContext) {
        let euiToZoneId = Dictionary(
            sensorConfigs.compactMap { s -> (String, String)? in
                guard let z = s.linkedZoneId else { return nil }
                return (s.eui, z)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !euiToZoneId.isEmpty else { return }

        var result: [String: [Double]] = [:]
        let cutoff = Date().addingTimeInterval(-86400) // only look at last 24h
        let descriptor = FetchDescriptor<SensorReading>(
            predicate: #Predicate { $0.recordedAt > cutoff },
            sortBy: [SortDescriptor(\SensorReading.recordedAt, order: .reverse)]
        )
        let readings = (try? modelContext.fetch(descriptor)) ?? []

        // For each EUI, take the most recent reading and map to zone
        var seen = Set<String>()
        for reading in readings {
            guard !seen.contains(reading.eui),
                  let zoneId = euiToZoneId[reading.eui] else { continue }
            seen.insert(reading.eui)
            result[zoneId, default: []].append(reading.moisture)
        }

        latestMoisture = result.mapValues { vals in vals.reduce(0, +) / Double(vals.count) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ScrollView {
                        DSLoadingState(label: "Loading zones…")
                            .padding(DS.Spacing.lg)
                    }
                    .dsBackground()
                } else {
                    mainContent
                }
            }
            .navigationTitle("Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(ZoneSortOrder.allCases, id: \.rawValue) { order in
                                Label(order.rawValue, systemImage: order.icon).tag(order.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.devices.isEmpty && viewModel.activeZoneId != nil {
                        Button(role: .destructive) {
                            showStopAllConfirmation = true
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(DS.Color.error)
                        }
                    }
                }
            }
        }
        .task {
            let mc = modelContext
            let vm = viewModel
            Task.detached(priority: .userInitiated) {
                await vm.loadZones(modelContext: mc)
                await MainActor.run { self.loadMoisture(modelContext: mc) }
            }
        }
        .confirmationDialog(
            "Stop All Zones",
            isPresented: $showStopAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop All Zones", role: .destructive) {
                Task { await viewModel.stopAllZones() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop all currently running zones.")
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = viewModel.errorMessage {
                    DSInlineBanner(message: message, style: .error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                }

                if viewModel.devices.isEmpty {
                    DSEmptyState(
                        icon: "drop.fill",
                        title: "No Zones Found",
                        message: "No irrigation devices were found in your Rachio account.",
                        action: { Task { await viewModel.loadZones(modelContext: modelContext) } },
                        actionLabel: "Refresh"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                } else {
                    ForEach(viewModel.devices) { device in
                        deviceSection(device)
                    }
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.loadZones(modelContext: modelContext, forceRefresh: true)
            loadMoisture(modelContext: modelContext)
        }
    }

    private func sortedZones(_ zones: [RachioZone], device: RachioDevice) -> [RachioZone] {
        switch currentSort {
        case .moisture:
            return zones.sorted {
                let a = avgMoisture(forZoneId: $0.id) ?? Double.infinity
                let b = avgMoisture(forZoneId: $1.id) ?? Double.infinity
                return a < b
            }
        case .name:
            return zones.sorted { $0.name < $1.name }
        case .nextRun:
            return zones.sorted {
                let a = device.nextRunDate(forZone: $0) ?? Date.distantFuture
                let b = device.nextRunDate(forZone: $1) ?? Date.distantFuture
                return a < b
            }
        case .lastWatered:
            return zones.sorted {
                let a = $0.lastWateredDate ?? 0
                let b = $1.lastWateredDate ?? 0
                return a > b
            }
        case .weeklyWater:
            return zones.sorted {
                let a = weeklyMinutes(forZone: $0, device: device)
                let b = weeklyMinutes(forZone: $1, device: device)
                return a > b // most water first
            }
        }
    }

    private func weeklyMinutes(forZone zone: RachioZone, device: RachioDevice) -> Double {
        device.schedules(forZoneId: zone.id)
            .reduce(0.0) { $0 + (Double($1.duration) / 60.0 * $1.rule.runsPerWeekDouble) }
    }

    private func deviceSection(_ device: RachioDevice) -> some View {
        let enabledZones = sortedZones(device.zones.filter(\.enabled), device: device)

        return VStack(alignment: .leading, spacing: 0) {
            // Device header
            HStack(spacing: DS.Spacing.sm) {
                DSStatusDot(status: device.on == true ? .online : .offline, size: 8)
                Text(device.name.uppercased())
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)
                Spacer()
                Text("\(enabledZones.count) zones")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.md)

            // Grid of zone cards
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                ForEach(enabledZones) { zone in
                    NavigationLink {
                        ZoneDetailView(
                            zone: zone,
                            device: device,
                            isActive: viewModel.activeZoneId == zone.id,
                            onStart: { duration in
                                Task { await viewModel.startZone(id: zone.id, duration: duration, modelContext: modelContext) }
                            },
                            onStop: {
                                Task { await viewModel.stopZone(id: zone.id) }
                            }
                        )
                    } label: {
                        ZoneCardView(
                            zone: zone,
                            device: device,
                            moisture: avgMoisture(forZoneId: zone.id),
                            isActive: viewModel.activeZoneId == zone.id,
                            onStart: { duration in
                                Task { await viewModel.startZone(id: zone.id, duration: duration, modelContext: modelContext) }
                            },
                            onStop: {
                                Task { await viewModel.stopZone(id: zone.id) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }
}

#Preview {
    ZonesView()
}
