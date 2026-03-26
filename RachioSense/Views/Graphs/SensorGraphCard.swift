import SwiftUI
import Charts

struct SensorGraphCard: View {
    let title: String
    let sensors: [SensorConfig]
    let readingsFor: (String, String) -> [(Date, Double)]
    @Binding var chartPeriod: String
    var showPeriodPicker: Bool = true

    // Shared color palette for multi-sensor lines
    static let lineColors: [Color] = [
        Color(hex: "0066FF"),
        Color(hex: "22C55E"),
        Color(hex: "F59E0B"),
        Color(hex: "8B5CF6"),
        Color(hex: "EF4444"),
        Color(hex: "EC4899"),
        Color(hex: "06B6D4"),
        Color(hex: "F97316"),
    ]

    private func color(for index: Int) -> Color {
        Self.lineColors[index % Self.lineColors.count]
    }

    private struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let moisture: Double
        let sensorName: String
        let colorIndex: Int
    }

    private var allPoints: [DataPoint] {
        sensors.enumerated().flatMap { index, sensor in
            readingsFor(sensor.eui, chartPeriod).map { date, moisture in
                DataPoint(date: date, moisture: moisture, sensorName: sensor.name, colorIndex: index)
            }
        }
    }

    private var hasData: Bool {
        sensors.contains { readingsFor($0.eui, chartPeriod).count >= 2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            headerRow
            if hasData {
                chartView
                if sensors.count > 1 { legendView }
            } else {
                emptyState
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text(title)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer()
            if showPeriodPicker {
                Picker("Period", selection: $chartPeriod) {
                    Text("6h").tag("6h")
                    Text("12h").tag("12h")
                    Text("24h").tag("24h")
                    Text("7d").tag("7d")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

    private var chartView: some View {
        Chart {
            ForEach(allPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Moisture", point.moisture),
                    series: .value("Sensor", point.sensorName)
                )
                .foregroundStyle(color(for: point.colorIndex))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Moisture", point.moisture),
                    series: .value("Sensor", point.sensorName)
                )
                .foregroundStyle(color(for: point.colorIndex).opacity(0.08))
            }

            RuleMark(y: .value("Dry", 25))
                .foregroundStyle(DS.Color.error.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .trailing) {
                    Text("Dry").font(DS.Font.footnote).foregroundStyle(DS.Color.error)
                }
            RuleMark(y: .value("Low", 40))
                .foregroundStyle(DS.Color.warning.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .trailing) {
                    Text("Low").font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                }
        }
        .frame(height: 160)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 40, 75, 100]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%").font(DS.Font.footnote)
                    }
                }
                AxisGridLine()
            }
        }
    }

    private var legendView: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: DS.Spacing.xs
        ) {
            ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                HStack(spacing: DS.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: index))
                        .frame(width: 12, height: 4)
                    Text(sensor.name)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Not enough data for selected period")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
