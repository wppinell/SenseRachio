import SwiftUI
import Charts

struct MissionControlView: View {
    let viewModel: GraphsViewModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.trendChartPeriod) private var chartPeriod = "24h"

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            if viewModel.missionCards.isEmpty {
                DSEmptyState(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Linked Sensors",
                    message: "Link sensors to zones in Settings > Configuration > Sensor-Zone Links."
                )
                .padding(DS.Spacing.xl)
            } else {
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    ForEach(viewModel.missionCards) { card in
                        MissionCardView(
                            card: card,
                            viewModel: viewModel,
                            chartPeriod: chartPeriod,
                            onAction: {
                                Task {
                                    guard let zoneId = card.zoneId else { return }
                                    if viewModel.isZoneActive(zoneId) {
                                        await viewModel.stopZone(id: zoneId)
                                    } else {
                                        await viewModel.startZone(id: zoneId, modelContext: modelContext)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(DS.Spacing.lg)
            }
        }
        .dsBackground()
    }
}

// MARK: - Mission Card

private struct MissionCardView: View {
    let card: GraphsViewModel.MissionCard
    let viewModel: GraphsViewModel
    let chartPeriod: String
    let onAction: () -> Void

    private var isActive: Bool {
        card.zoneId.map { viewModel.isZoneActive($0) } ?? false
    }

    private var avgMoisture: Double? {
        let values = card.sensors.compactMap { viewModel.latestByEUI[$0.eui]?.moisture }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var lastWateredText: String? {
        guard let zoneId = card.zoneId,
              let date = viewModel.lastRunAt(for: zoneId) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Header
            HStack {
                Text(card.title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                statusIndicator
            }

            // Mini chart
            miniChart

            // Avg moisture
            if let avg = avgMoisture {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "humidity.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.moisture(avg))
                    Text("\(Int(avg))% avg")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.moisture(avg))
                }
            }

            // Last watered
            if let lastWatered = lastWateredText {
                Label(lastWatered, systemImage: "clock")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            // Run / Stop button
            if card.zoneId != nil {
                Button(action: onAction) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: isActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isActive ? "Stop" : "Run")
                            .font(DS.Font.label)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(isActive ? DS.Color.error : DS.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.md)
        .dsCard()
    }

    private var statusIndicator: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(isActive ? DS.Color.online : DS.Color.textTertiary)
                .frame(width: 6, height: 6)
            Text(isActive ? "Running" : "Idle")
                .font(DS.Font.footnote)
                .foregroundStyle(isActive ? DS.Color.online : DS.Color.textTertiary)
        }
    }

    @ViewBuilder
    private var miniChart: some View {
        let points: [(Date, Double, Int)] = card.sensors.enumerated().flatMap { index, sensor in
            viewModel.readings(for: sensor.eui, period: chartPeriod).map { date, moisture in
                (date, moisture, index)
            }
        }

        if points.count >= 2 {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("Moisture", point.1)
                    )
                    .foregroundStyle(
                        SensorGraphCard.lineColors[point.2 % SensorGraphCard.lineColors.count]
                    )
                    .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Dry", 25))
                    .foregroundStyle(DS.Color.error.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .frame(height: 80)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.badge)
                .fill(DS.Color.background)
                .frame(height: 80)
                .overlay {
                    Text("No data")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textTertiary)
                }
        }
    }
}
