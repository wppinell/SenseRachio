import SwiftUI

struct ZoneRowView: View {
    let zone: RachioZone
    let isActive: Bool
    let onStart: (Int) -> Void
    let onStop: () -> Void

    @State private var showDurationSheet = false
    @State private var selectedDuration = 10

    private let durations = [5, 10, 15, 20, 30]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(zone.name)
                        .font(.subheadline.bold())
                    if isActive {
                        Label("Running", systemImage: "drop.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.gradient)
                            .clipShape(Capsule())
                    }
                }
                Text(zone.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if isActive {
                    Button(role: .destructive) {
                        onStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        showDurationSheet = true
                    } label: {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.blue.opacity(0.08) : Color.clear)
        .sheet(isPresented: $showDurationSheet) {
            DurationPickerSheet(
                zoneName: zone.name,
                durations: durations,
                selectedDuration: $selectedDuration
            ) { duration in
                onStart(duration * 60)
                showDurationSheet = false
            }
            .presentationDetents([.height(320)])
        }
    }
}

// MARK: - Duration Picker Sheet

struct DurationPickerSheet: View {
    let zoneName: String
    let durations: [Int]
    @Binding var selectedDuration: Int
    let onConfirm: (Int) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Run \(zoneName)")
                .font(.title3.bold())
                .padding(.top, 24)

            Text("Select duration")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        selectedDuration = minutes
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(minutes)")
                                .font(.title3.bold())
                            Text("min")
                                .font(.caption2)
                        }
                        .frame(width: 56, height: 56)
                        .background(selectedDuration == minutes ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedDuration == minutes ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Button {
                onConfirm(selectedDuration)
            } label: {
                Label("Start Zone", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

#Preview {
    List {
        ZoneRowView(
            zone: RachioZone(id: "zone-1", name: "Front Lawn", enabled: true),
            isActive: false,
            onStart: { _ in },
            onStop: {}
        )
        ZoneRowView(
            zone: RachioZone(id: "zone-2", name: "Back Garden", enabled: true),
            isActive: true,
            onStart: { _ in },
            onStop: {}
        )
    }
}
