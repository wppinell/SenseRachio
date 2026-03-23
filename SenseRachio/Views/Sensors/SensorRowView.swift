import SwiftUI

struct SensorRowView: View {
    let sensor: SensorConfig
    let reading: SensorReading?

    private var moisture: Double {
        reading?.moisture ?? 0
    }

    private var tempC: Double {
        reading?.tempC ?? 0
    }

    private var moistureColor: Color {
        if moisture >= 40 { return .green }
        if moisture >= 25 { return .yellow }
        return .red
    }

    private var moistureLabel: String {
        if reading == nil { return "No data" }
        return "\(Int(moisture))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sensor.name)
                        .font(.headline)
                    Text(sensor.eui)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(moistureLabel)
                        .font(.title3.bold())
                        .foregroundStyle(moistureColor)
                    if reading != nil {
                        Text("\(String(format: "%.1f", tempC))°C")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Moisture Bar Indicator
            if reading != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(moistureColor.gradient)
                            .frame(width: max(geo.size.width * (moisture / 100), 4), height: 8)
                            .animation(.easeInOut(duration: 0.4), value: moisture)
                    }
                }
                .frame(height: 8)
            }

            // Threshold indicator
            if let threshold = sensor.moistureThreshold {
                HStack(spacing: 4) {
                    Image(systemName: moisture < threshold ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(moisture < threshold ? .red : .green)
                    Text("Threshold: \(Int(threshold))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        SensorRowView(
            sensor: SensorConfig(id: "1", name: "Garden Bed A", eui: "2CF7F1C044200006"),
            reading: SensorReading(eui: "2CF7F1C044200006", moisture: 35.5, tempC: 21.3)
        )
        SensorRowView(
            sensor: SensorConfig(id: "2", name: "Front Lawn", eui: "2CF7F1C044200007"),
            reading: SensorReading(eui: "2CF7F1C044200007", moisture: 18.2, tempC: 23.1)
        )
        SensorRowView(
            sensor: SensorConfig(id: "3", name: "Backyard", eui: "2CF7F1C044200008"),
            reading: SensorReading(eui: "2CF7F1C044200008", moisture: 55.0, tempC: 19.8)
        )
    }
}
