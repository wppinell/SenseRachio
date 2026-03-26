import SwiftUI
import SwiftData

struct ZonesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ZonesViewModel()
    @State private var showStopAllConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ScrollView {
                        DSLoadingState(label: "Loading zones…")
                            .padding(DS.Spacing.lg)
                    }
                    .dsBackground()
                } else {
                    mainContent
                }
            }
            .navigationTitle("Zones")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadZones(modelContext: modelContext)
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = viewModel.errorMessage {
                    DSInlineBanner(message: message, style: .error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.lg)
                }

                if viewModel.devices.isEmpty {
                    DSSectionHeader(title: "Zones")
                    DSEmptyState(
                        icon: "drop.fill",
                        title: "No Zones Found",
                        message: "No irrigation devices were found in your Rachio account.",
                        action: { Task { await viewModel.loadZones(modelContext: modelContext) } },
                        actionLabel: "Refresh"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    ForEach(viewModel.devices) { device in
                        deviceSection(device)
                    }
                }

                // STOP ALL ZONES button
                if !viewModel.devices.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Divider()
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.lg)

                        Button(role: .destructive) {
                            showStopAllConfirmation = true
                        } label: {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Stop All Zones")
                                    .font(DS.Font.buttonLabel)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(DS.Color.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.md)
                            .background(DS.Color.errorMuted)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xl)
                    }
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .refreshable {
            await viewModel.loadZones(modelContext: modelContext)
        }
        .confirmationDialog(
            "Stop All Zones",
            isPresented: $showStopAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop All Zones", role: .destructive) {
                Task { await viewModel.stopAllZones() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop all currently running zones.")
        }
    }

    @ViewBuilder
    private func deviceSection(_ device: RachioDevice) -> some View {
        let enabledZones = device.zones.filter(\.enabled)

        VStack(alignment: .leading, spacing: 0) {
            // Device header
            HStack(spacing: DS.Spacing.sm) {
                DSStatusDot(status: device.on == true ? .online : .offline, size: 8)
                Text(device.name.uppercased())
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tracking(0.8)
                Spacer()
                Text("\(enabledZones.count) zones")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)

            LazyVStack(spacing: DS.Spacing.sm) {
                ForEach(enabledZones) { zone in
                    NavigationLink {
                        ZoneDetailView(
                            zone: zone,
                            device: device,
                            isActive: viewModel.activeZoneId == zone.id,
                            onStart: { duration in
                                Task { await viewModel.startZone(id: zone.id, duration: duration, modelContext: modelContext) }
                            },
                            onStop: {
                                Task { await viewModel.stopZone(id: zone.id) }
                            }
                        )
                    } label: {
                        ZoneRowView(
                            zone: zone,
                            device: device,
                            isActive: viewModel.activeZoneId == zone.id,
                            onStart: { duration in
                                Task { await viewModel.startZone(id: zone.id, duration: duration, modelContext: modelContext) }
                            },
                            onStop: {
                                Task { await viewModel.stopZone(id: zone.id) }
                            }
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }
}

#Preview {
    ZonesView()
}
