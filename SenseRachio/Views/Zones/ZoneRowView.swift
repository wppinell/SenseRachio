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
        HStack(spacing: 10) {
            zoneImage

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
                if let subtitle = lastWateredSubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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

    // MARK: - Zone Image

    @ViewBuilder
    private var zoneImage: some View {
        if let urlString = zone.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                default:
                    zonePlaceholder
                }
            }
        } else {
            zonePlaceholder
        }
    }

    private var zonePlaceholder: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Last Watered

    private var lastWateredSubtitle: String? {
        guard let epochMs = zone.lastWateredDate else { return nil }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        if let duration = zone.lastWateredDuration {
            let mins = duration / 60
            let secs = duration % 60
            let durationStr = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
            return "Watered \(relative) for \(durationStr)"
        }
        return "Watered \(relative)"
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
            zone: RachioZone(id: "zone-1", name: "Front Lawn", enabled: true, zoneNumber: 1, lastWateredDate: Int(Date().addingTimeInterval(-172800).timeIntervalSince1970 * 1000), lastWateredDuration: 600, imageUrl: nil),
            isActive: false,
            onStart: { _ in },
            onStop: {}
        )
        ZoneRowView(
            zone: RachioZone(id: "zone-2", name: "Tomato Garden", enabled: true, zoneNumber: 4, lastWateredDate: nil, lastWateredDuration: nil, imageUrl: nil),
            isActive: true,
            onStart: { _ in },
            onStop: {}
        )
    }
}
