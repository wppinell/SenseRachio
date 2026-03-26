import SwiftUI
import SwiftData

struct GroupingView: View {
    @Query(sort: \ZoneGroup.sortOrder) private var groups: [ZoneGroup]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.sensorGrouping) private var sensorGrouping = "none"
    @AppStorage(AppStorageKey.zoneGrouping) private var zoneGrouping = "none"

    @State private var showAddGroup = false
    @State private var newGroupName = ""
    @State private var newGroupIcon = "circle.hexagongrid"

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
                            GroupDetailView(group: group)
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
                                    Text("\(group.assignedZoneIds.count) zones")
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
        .navigationTitle("Zone Display Grouping")
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
        let group = ZoneGroup(
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
    let group: ZoneGroup
    @Environment(\.modelContext) private var modelContext
    @Query private var zones: [ZoneConfig]

    @State private var groupName: String = ""
    @State private var selectedIcon: String = "circle.hexagongrid"

    private let iconOptions = [
        "circle.hexagongrid", "leaf.fill", "drop.fill", "sun.max.fill",
        "tree.fill", "house.fill", "fork.knife", "flower.fill",
        "camera.macro", "wind", "snowflake", "flame.fill"
    ]

    var body: some View {
        List {
            // Name
            Section("Name") {
                TextField("Group name", text: $groupName)
                    .onSubmit { saveName() }
            }

            // Icon picker
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: DS.Spacing.md) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            group.iconName = icon
                            try? modelContext.save()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedIcon == icon ? DS.Color.accent : DS.Color.textSecondary)
                                .frame(width: 42, height: 42)
                                .background(selectedIcon == icon ? DS.Color.accentMuted : DS.Color.background)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.badge))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init())

            // Zones checkboxes
            Section {
                if zones.isEmpty {
                    Text("No zones available — load Zones tab first")
                        .foregroundStyle(DS.Color.textTertiary)
                        .font(DS.Font.cardBody)
                } else {
                    ForEach(zones) { zone in
                        let isAssigned = group.assignedZoneIds.contains(zone.id)
                        Button {
                            toggleZone(zone)
                        } label: {
                            HStack {
                                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isAssigned ? DS.Color.online : DS.Color.textTertiary)
                                Text(zone.name)
                                    .foregroundStyle(DS.Color.textPrimary)
                            }
                        }
                    }
                }
            } header: { Text("Zones (\(group.assignedZoneIds.count))") }
             footer: { Text("Sensors linked to these zones will appear together in Graphs.") }

            // Delete button
            Section {
                Button("Delete Group", role: .destructive) {
                    modelContext.delete(group)
                    try? modelContext.save()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            groupName = group.name
            selectedIcon = group.iconName
        }
    }

    private func saveName() {
        let trimmed = groupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        group.name = trimmed
        try? modelContext.save()
    }

    private func toggleZone(_ zone: ZoneConfig) {
        if group.assignedZoneIds.contains(zone.id) {
            group.assignedZoneIds.removeAll(where: { $0 == zone.id })
        } else {
            group.assignedZoneIds.append(zone.id)
        }
        try? modelContext.save()
    }
}
