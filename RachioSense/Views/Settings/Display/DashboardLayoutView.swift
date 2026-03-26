import SwiftUI

struct DashboardLayoutView: View {
    @AppStorage(AppStorageKey.trendChartPeriod) private var chartPeriod = "24h"
    @AppStorage(AppStorageKey.quickActionsOnCards) private var quickActions = true
    @AppStorage(AppStorageKey.dashboardCardOrder) private var cardOrderJSON = ""
    @AppStorage(AppStorageKey.dashboardCardVisibility) private var cardVisibilityJSON = ""

    private let defaultCards = ["moisture", "zones", "weather", "history", "schedule"]

    private var cardOrder: [String] {
        guard !cardOrderJSON.isEmpty,
              let data = cardOrderJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return defaultCards }
        return arr
    }

    private var hiddenCards: Set<String> {
        guard !cardVisibilityJSON.isEmpty,
              let data = cardVisibilityJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private let cardInfo: [String: (icon: String, label: String)] = [
        "moisture":  ("drop.fill", "Moisture"),
        "zones":     ("water.waves", "Zones"),
        "weather":   ("cloud.sun.fill", "Weather"),
        "history":   ("chart.line.uptrend.xyaxis", "History"),
        "schedule":  ("calendar", "Schedule"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(cardOrder, id: \.self) { cardId in
                    let info = cardInfo[cardId]
                    let isHidden = hiddenCards.contains(cardId)

                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(DS.Color.textTertiary)
                            .font(.system(size: 13))

                        Image(systemName: info?.icon ?? "square")
                            .foregroundStyle(isHidden ? DS.Color.textTertiary : DS.Color.accent)
                            .frame(width: 20)

                        Text(info?.label ?? cardId.capitalized)
                            .foregroundStyle(isHidden ? DS.Color.textTertiary : DS.Color.textPrimary)

                        Spacer()

                        Button {
                            toggleCard(cardId)
                        } label: {
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .foregroundStyle(isHidden ? DS.Color.textTertiary : DS.Color.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    var order = cardOrder
                    order.move(fromOffsets: from, toOffset: to)
                    saveOrder(order)
                }
            } header: {
                HStack {
                    Text("Card Order")
                    Spacer()
                    Text("Drag to reorder")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            } footer: {
                Text("Tap the eye icon to show or hide a card on the dashboard.")
            }

            Section {
                Picker("Trend Chart Period", selection: $chartPeriod) {
                    Text("6 Hours").tag("6h")
                    Text("12 Hours").tag("12h")
                    Text("24 Hours").tag("24h")
                    Text("7 Days").tag("7d")
                }
            } header: { Text("Charts") }

            Section {
                Toggle("Quick Actions on Cards", isOn: $quickActions)
                    .tint(DS.Color.accent)
            } header: { Text("Quick Actions") }
             footer: { Text("Show Start/Stop buttons directly on zone cards in the dashboard.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dashboard Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func toggleCard(_ id: String) {
        var hidden = hiddenCards
        if hidden.contains(id) {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
        if let data = try? JSONEncoder().encode(Array(hidden)) {
            cardVisibilityJSON = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func saveOrder(_ order: [String]) {
        if let data = try? JSONEncoder().encode(order) {
            cardOrderJSON = String(data: data, encoding: .utf8) ?? ""
        }
    }
}
