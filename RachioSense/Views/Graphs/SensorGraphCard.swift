import SwiftUI
import Charts

struct SensorGraphCard: View {
    let title: String
    let sensors: [SensorConfig]
    let readingsFor: (String, String) -> [(Date, Double)]
    @Binding var chartPeriod: String          // shared — double-tap syncs here
    var showPeriodPicker: Bool = true
    var isFetching: Bool = false
    @AppStorage(AppStorageKey.graphYMin) private var graphYMin = 15.0
    @AppStorage(AppStorageKey.graphYMax) private var graphYMax = 45.0
    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40

    @State private var localPeriod: String = "4d" // per-card — single tap changes only this
    @State private var syncFlash: Bool = false    // brief visual feedback on double-tap

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
            readingsFor(sensor.eui, localPeriod).map { date, moisture in
                DataPoint(date: date, moisture: moisture, sensorName: sensor.displayName, colorIndex: index)
            }
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
    private var yAxisValues: [Double] {
        let min = graphYMin
        let max = graphYMax
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

    private var hasData: Bool {
        sensors.contains { readingsFor($0.eui, localPeriod).count >= 2 }
    }

    private var isWaitingForData: Bool {
        // No data at all for the current period
        !sensors.isEmpty && sensors.allSatisfy { readingsFor($0.eui, localPeriod).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            headerRow
            if hasData {
                chartView
                legendView
            } else {
                emptyState
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
        .onAppear {
            localPeriod = chartPeriod
        }
        .onChange(of: chartPeriod) { _, newVal in
            // External broadcast (double-tap on another card) → sync local
            localPeriod = newVal
        }
        .overlay(alignment: .topTrailing) {
            if syncFlash {
                Text("Synced")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Color.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .padding(DS.Spacing.md)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: syncFlash)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text(title)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)
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
                    .font(.system(size: 12, weight: localPeriod == period ? .semibold : .regular))
                    .foregroundStyle(localPeriod == period ? .white : DS.Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
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
        .frame(height: 160)
        .chartXScale(domain: periodStart...Date())
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisStride)) { value in
                AxisValueLabel(format: xAxisFormat, centered: true)
                AxisGridLine()
            }
        }
        .chartYScale(domain: graphYMin...graphYMax)
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
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: DS.Spacing.xs
        ) {
            ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                HStack(spacing: DS.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: index))
                        .frame(width: 12, height: 4)
                    Text(sensor.displayName)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
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
            Text("card EUIs: \(sensors.map{$0.eui.suffix(4)}.joined(separator:","))")
            Text("pts: \(allPoints.count) · readings: \(sensors.map{ s in String(readingsFor(s.eui, localPeriod).count) }.joined(separator:","))")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
