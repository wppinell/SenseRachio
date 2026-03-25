import SwiftUI
import SwiftData

struct GroupingView: View {
    @Query(sort: \SensorGroup.sortOrder) private var groups: [SensorGroup]
    @Query private var sensors: [SensorConfig]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.sensorGrouping) private var sensorGrouping = "none"
    @AppStorage(AppStorageKey.zoneGrouping) private var zoneGrouping = "none"

    @State private var showAddGroup = false
    @State private var newGroupName = ""
    @State private var newGroupIcon = "circle.hexagongrid"
    @State private var groupToDelete: SensorGroup? = nil

    private let iconOptions = [
        "circle.hexagongrid", "leaf.fill", "drop.fill", "sun.max.fill",
        "tree.fill", "house.fill", "fork.knife", "flower.fill"
    ]

    var body: some View {
        List {
            Section {
                Picker("Sensor view grouping", selection: $sensorGrouping) {
                    Text("None").tag("none")
                    ForEach(groups) { g in
                        Text(g.name).tag(g.id)
                    }
                }
                Picker("Zone view grouping", selection: $zoneGrouping) {
                    Text("None").tag("none")
                    ForEach(groups) { g in
                        Text(g.name).tag(g.id)
                    }
                }
            } header: { Text("Default View") }
             footer: { Text("Choose which group to show by default in the Sensors and Zones tabs.") }

            Section {
                if groups.isEmpty {
                    Text("No groups created yet.")
                        .foregroundStyle(DS.Color.textTertiary)
                        .font(DS.Font.cardBody)
                } else {
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupDetailView(group: group, sensors: sensors)
                        } label: {
                            HStack(spacing: DS.Spacing.md) {
                                Image(systemName: group.iconName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Color.accent)
                                    .frame(width: 28, height: 28)
                                    .background(DS.Color.accentMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(DS.Font.cardTitle)
                                    Text("\(group.assignedSensorIds.count) sensors · \(group.assignedZoneIds.count) zones")
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.textSecondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteGroups)
                }
            } header: {
                HStack {
                    Text("Groups")
                    Spacer()
                    Button {
                        showAddGroup = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(DS.Font.label)
                    }
                    .foregroundStyle(DS.Color.accent)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Grouping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddGroup = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddGroup) {
            addGroupSheet
        }
    }

    private var addGroupSheet: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Front Yard", text: $newGroupName)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: DS.Spacing.md) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                newGroupIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 22))
                                    .foregroundStyle(newGroupIcon == icon ? DS.Color.accent : DS.Color.textSecondary)
                                    .frame(width: 52, height: 52)
                                    .background(newGroupIcon == icon ? DS.Color.accentMuted : DS.Color.background)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.badge))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddGroup = false
                        newGroupName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addGroup()
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addGroup() {
        let group = SensorGroup(
            name: newGroupName.trimmingCharacters(in: .whitespaces),
            iconName: newGroupIcon,
            sortOrder: groups.count
        )
        modelContext.insert(group)
        try? modelContext.save()
        showAddGroup = false
        newGroupName = ""
        HapticFeedback.notification(.success)
    }

    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(groups[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Group Detail

private struct GroupDetailView: View {
    let group: SensorGroup
    let sensors: [SensorConfig]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("Assigned Sensors") {
                ForEach(sensors) { sensor in
                    let isAssigned = group.assignedSensorIds.contains(sensor.id)
                    Button {
                        toggleSensor(sensor)
                    } label: {
                        HStack {
                            Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isAssigned ? DS.Color.online : DS.Color.textTertiary)
                            Text(sensor.name)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleSensor(_ sensor: SensorConfig) {
        if group.assignedSensorIds.contains(sensor.id) {
            group.assignedSensorIds.removeAll(where: { $0 == sensor.id })
            sensor.groupId = nil
        } else {
            group.assignedSensorIds.append(sensor.id)
            sensor.groupId = group.id
        }
        try? modelContext.save()
    }
}
