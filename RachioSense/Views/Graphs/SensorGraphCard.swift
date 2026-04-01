import SwiftUI
import Charts

struct SensorGraphCard: View {
    let title: String
    let sensors: [SensorConfig]
    let readingsByEUI: [String: [SensorReading]]   // direct data — SwiftUI observes changes
    var wateringEvents: [RachioWateringEvent] = [] // events for zones linked to this card's sensors
    @Binding var chartPeriod: String
    var showPeriodPicker: Bool = true
    var isFetching: Bool = false
    @Binding var syncFlash: Bool
    @AppStorage(AppStorageKey.graphYMin) private var graphYMin = 15.0
    @AppStorage(AppStorageKey.graphYMax) private var graphYMax = 45.0
    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40

    @State private var localPeriod: String = "4d" // per-card — single tap changes only this

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

    private func readings(for eui: String) -> [(Date, Double)] {
        let cutoff = cutoffDate(for: localPeriod)
        return (readingsByEUI[eui] ?? [])
            .filter { $0.recordedAt >= cutoff && $0.moisture >= 0 && $0.moisture <= 100 }
            .map { ($0.recordedAt, $0.moisture) }
            .sorted { $0.0 < $1.0 }
    }

    private var allPoints: [DataPoint] {
        sensors.enumerated().flatMap { index, sensor in
            readings(for: sensor.eui).map { date, moisture in
                DataPoint(date: date, moisture: moisture, sensorName: sensor.displayName, colorIndex: index)
            }
        }
    }

    private func cutoffDate(for period: String) -> Date {
        switch period {
        case "1d": return Date().addingTimeInterval(-1 * 86400)
        case "2d": return Date().addingTimeInterval(-2 * 86400)
        case "4d": return Date().addingTimeInterval(-4 * 86400)
        case "5d": return Date().addingTimeInterval(-5 * 86400)
        case "1w": return Date().addingTimeInterval(-7 * 86400)
        default:   return Date().addingTimeInterval(-86400)
        }
    }

    private var periodDays: Int {
        switch localPeriod {
        case "1d": return 1
        case "2d": return 2
        case "4d": return 4
        case "5d": return 5
        case "1w": return 7
        default:   return 1
        }
    }

    private var periodStart: Date {
        Date().addingTimeInterval(-Double(periodDays) * 86400)
    }

    private var xAxisStride: Calendar.Component { .day }

    private var xAxisCount: Int { periodDays }

    private var xAxisFormat: Date.FormatStyle {
        .dateTime.month(.defaultDigits).day()
    }

    /// Evenly spaced Y axis ticks within the configured range
    private var yRange: (min: Double, max: Double) {
        let moistures = allPoints.map(\.moisture)
        guard !moistures.isEmpty else { return (graphYMin, graphYMax) }
        let dataMin = (moistures.min() ?? graphYMin)
        let dataMax = (moistures.max() ?? graphYMax)
        // Always show all data — expand beyond configured range if needed, never clip
        let low  = (min(graphYMin, dataMin) - 3).rounded(.down)
        let high = (max(graphYMax, dataMax) + 3).rounded(.up)
        return (low, high)
    }

    private var yAxisValues: [Double] {
        let min = yRange.min
        let max = yRange.max
        let range = max - min
        let step = range <= 20 ? 5.0 : range <= 40 ? 10.0 : 15.0
        var values: [Double] = []
        var v = (min / step).rounded(.up) * step
        while v <= max {
            values.append(v)
            v += step
        }
        return values
    }

    private var visibleWateringEvents: [RachioWateringEvent] {
        let cutoff = cutoffDate(for: localPeriod)
        return wateringEvents.filter { $0.startDate >= cutoff && $0.startDate <= Date() }
    }

    private var hasData: Bool {
        sensors.contains { readings(for: $0.eui).count >= 2 }
    }

    private var isWaitingForData: Bool {
        !sensors.isEmpty && sensors.allSatisfy { readings(for: $0.eui).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            headerRow
            if hasData {
                chartView
                legendView
            } else {
                emptyState
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .dsCard()
        .onAppear {
            localPeriod = chartPeriod
        }
        .onChange(of: chartPeriod) { _, newVal in
            // External broadcast (double-tap on another card) → sync local
            localPeriod = newVal
        }
        .animation(.easeInOut(duration: 0.2), value: syncFlash)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer()
            if showPeriodPicker {
                periodPicker
            }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 2) {
            ForEach(["1d", "2d", "4d", "5d", "1w"], id: \.self) { period in
                Text(period)
                    .font(.system(size: 11, weight: localPeriod == period ? .semibold : .regular))
                    .foregroundStyle(localPeriod == period ? .white : DS.Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(localPeriod == period ? DS.Color.accent : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        // Double-tap: set local + broadcast to all cards
                        localPeriod = period
                        chartPeriod = period
                        syncFlash = true
                        HapticFeedback.impact(.medium)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            syncFlash = false
                        }
                    }
                    .onTapGesture(count: 1) {
                        // Single-tap: only change this card
                        localPeriod = period
                        HapticFeedback.impact(.light)
                    }
            }
        }
        .padding(3)
        .background(DS.Color.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.Color.accent, lineWidth: 2)
                .opacity(syncFlash ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: syncFlash)
        )
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
                .interpolationMethod(.linear)
            }

            // Watering event markers — vertical cyan lines
            ForEach(visibleWateringEvents) { event in
                RuleMark(x: .value("Watered", event.startDate))
                    .foregroundStyle(Color.cyan.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, spacing: 0) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.cyan.opacity(0.8))
                    }
            }

            // Auto-water threshold — red
            RuleMark(y: .value("Auto-water", autoWaterThreshold))
                .foregroundStyle(DS.Color.error.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Dry threshold — yellow
            RuleMark(y: .value("Dry", dryThreshold))
                .foregroundStyle(DS.Color.warning.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // High threshold — blue
            RuleMark(y: .value("High", highThreshold))
                .foregroundStyle(Color(hex: "0EA5E9").opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 200)
        .chartXScale(domain: periodStart...Date())
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisStride)) { value in
                AxisValueLabel(format: xAxisFormat, centered: true)
                AxisGridLine()
            }
        }
        .chartYScale(domain: yRange.min...yRange.max)
        .chartYAxis {
            AxisMarks(values: yAxisValues) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%").font(DS.Font.footnote)
                    }
                }
                AxisGridLine()
            }
        }
    }

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: index))
                            .frame(width: 10, height: 3)
                        Text(sensor.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var fetchingState: some View {
        VStack(spacing: DS.Spacing.sm) {
            ProgressView()
                .controlSize(.regular)
            Text("Refreshing data…")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var waitingState: some View {
        VStack(spacing: DS.Spacing.sm) {
            ProgressView()
                .controlSize(.regular)
            Text("Collecting data…")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Text("History will appear once readings are fetched.")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("No data for \(localPeriod)")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
