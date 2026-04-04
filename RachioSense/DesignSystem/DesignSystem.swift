// DesignSystem.swift — UniFi-inspired design tokens, components, and utilities
import SwiftUI

// MARK: - Design System Namespace

enum DS {

    // MARK: Colors
    enum Color {
        static let background    = SwiftUI.Color(hex: "F5F7FA")
        static let card          = SwiftUI.Color.white
        static let accent        = SwiftUI.Color(hex: "0066FF")
        static let accentMuted   = SwiftUI.Color(hex: "0066FF").opacity(0.12)
        static let online        = SwiftUI.Color(hex: "22C55E")
        static let onlineMuted   = SwiftUI.Color(hex: "22C55E").opacity(0.12)
        static let warning       = SwiftUI.Color(hex: "F59E0B")
        static let warningMuted  = SwiftUI.Color(hex: "F59E0B").opacity(0.12)
        static let error         = SwiftUI.Color(hex: "EF4444")
        static let errorMuted    = SwiftUI.Color(hex: "EF4444").opacity(0.12)
        static let textPrimary   = SwiftUI.Color(hex: "1A1A2E")
        static let textSecondary = SwiftUI.Color(hex: "6B7280")
        static let textTertiary  = SwiftUI.Color(hex: "9CA3AF")
        static let separator     = SwiftUI.Color(hex: "E5E7EB")
        static let cardShadow    = SwiftUI.Color.black.opacity(0.06)
        static let overlay       = SwiftUI.Color.black.opacity(0.4)

        // Status-aware moisture color
        static func moisture(_ value: Double) -> SwiftUI.Color {
            if value >= 40 { return online }
            if value >= 25 { return warning }
            return error
        }

        // Accent color palette options
        static let accentOptions: [String: SwiftUI.Color] = [
            "Blue":   SwiftUI.Color(hex: "0066FF"),
            "Green":  SwiftUI.Color(hex: "22C55E"),
            "Purple": SwiftUI.Color(hex: "8B5CF6"),
            "Orange": SwiftUI.Color(hex: "F97316"),
            "Leaf":   SwiftUI.Color(hex: "16A34A"),
        ]
    }

    // MARK: Typography
    enum Font {
        static let pageTitle     = SwiftUI.Font.system(size: 28, weight: .bold)
        static let sectionHeader = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let cardTitle     = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let cardBody      = SwiftUI.Font.system(size: 13, weight: .regular)
        static let stat          = SwiftUI.Font.system(size: 32, weight: .bold, design: .rounded)
        static let statSmall     = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let label         = SwiftUI.Font.system(size: 11, weight: .medium)
        static let mono          = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let caption       = SwiftUI.Font.system(size: 12, weight: .regular)
        static let footnote      = SwiftUI.Font.system(size: 11, weight: .regular)
        static let buttonLabel   = SwiftUI.Font.system(size: 15, weight: .semibold)
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 16
        static let xl: CGFloat  = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let card: CGFloat   = 12
        static let button: CGFloat = 10
        static let badge: CGFloat  = 6
        static let chip: CGFloat   = 20
    }

    // MARK: Shadow
    static func cardShadow() -> some View {
        EmptyView()
    }
}

// MARK: - AppStorage Key Registry

enum AppStorageKey {
    // Display
    static let theme                   = "display_theme"               // "system"|"light"|"dark"
    static let accentColor             = "display_accent_color"        // "Blue"|"Green"|"Purple"|"Orange"|"Leaf"
    static let animationsEnabled       = "display_animations"
    static let hapticsEnabled          = "display_haptics"
    static let iconStyle               = "display_icon_style"          // "filled"|"outlined"
    static let temperatureUnit         = "display_temperature_unit"    // "fahrenheit"|"celsius"
    static let moistureUnit            = "display_moisture_unit"       // "percent"|"raw"
    static let durationUnit            = "display_duration_unit"       // "minutes"|"hoursMinutes"|"seconds"
    static let volumeUnit              = "display_volume_unit"         // "gallons"|"liters"
    static let dashboardCardOrder      = "display_dashboard_card_order"
    static let dashboardCardVisibility = "display_dashboard_card_visibility"
    static let trendChartPeriod        = "display_trend_chart_period"  // "1d"|"2d"|"3d"|"4d"|"5d"|"1w"|"2w"
    static let graphYMin               = "display_graph_y_min"         // Double default 15
    static let graphYMax               = "display_graph_y_max"         // Double default 45
    static let quickActionsOnCards     = "display_quick_actions"
    static let sensorPrimaryLabel      = "display_sensor_primary"      // "name"|"eui"|"group"
    static let sensorSecondaryLabel    = "display_sensor_secondary"    // "moistureTemp"|"moisture"|"lastUpdated"|"group"
    static let statusIndicatorStyle    = "display_status_indicator"    // "coloredDot"|"coloredBackground"|"none"

    // Thresholds
    static let dryThreshold            = "threshold_dry"               // Double default 25
    static let lowThreshold            = "threshold_low"               // Double default 40
    static let autoWaterThreshold      = "threshold_auto_water"        // Double default 20
    static let subscriptionAlertDays   = "threshold_subscription_days" // Int default 30

    // Notifications
    static let dryAlertsEnabled        = "notif_dry_alerts"
    static let lowAlertsEnabled        = "notif_low_alerts"
    static let sensorOfflineEnabled    = "notif_sensor_offline"
    static let zoneStartedEnabled      = "notif_zone_started"
    static let zoneStoppedEnabled      = "notif_zone_stopped"
    static let zoneSkipEnabled         = "notif_zone_skip"
    static let scheduleRunEnabled      = "notif_schedule_run"
    static let serviceAlertsEnabled    = "notif_service_alerts"
    static let dailySummaryEnabled     = "notif_daily_summary"
    static let dailySummaryHour        = "notif_daily_summary_hour"    // Int 0-23
    static let dailySummaryMinute      = "notif_daily_summary_minute"
    static let weeklyReportEnabled     = "notif_weekly_report"
    static let weeklyReportDay         = "notif_weekly_report_day"     // Int 0=Sun
    static let quietHoursEnabled       = "notif_quiet_hours"
    static let quietHoursStartHour     = "notif_quiet_start_hour"      // Int
    static let quietHoursEndHour       = "notif_quiet_end_hour"
    static let notificationCooldownHours  = "notif_cooldown_hours"      // Int default 4
    static let predictiveAlertEnabled     = "notif_predictive_alert"    // Bool default true
    static let predictiveAlertWindowHours = "notif_predictive_window"   // Int default 6

    // Refresh Rate
    static let foregroundRefresh       = "refresh_foreground"          // Int seconds: 15|30|60|300
    static let backgroundRefresh       = "refresh_background"          // Int seconds: 600|900|1800|3600
    static let pushNotificationsEnabled = "refresh_push_notifications"

    // Weather
    static let weatherSource           = "weather_source"              // "rachio"|"national"|"openmeteo"
    static let rainSkipEnabled         = "weather_rain_skip"
    static let rainSkipThreshold       = "weather_rain_threshold"      // Double mm
    static let freezeSkipEnabled       = "weather_freeze_skip"
    static let freezeSkipThreshold     = "weather_freeze_threshold"    // Double degrees
    static let windSkipEnabled         = "weather_wind_skip"
    static let windSkipThreshold       = "weather_wind_threshold"      // Double mph
    static let saturationSkipEnabled   = "weather_saturation_skip"
    static let saturationSkipThreshold = "weather_saturation_threshold"
    static let forecastLookahead       = "weather_forecast_lookahead"  // Int hours: 24|48|72

    // Data
    static let historyRetention        = "data_history_retention"      // Int days: 7|30|90|365|-1
    static let analyticsEnabled        = "data_analytics"
    static let crashReportsEnabled     = "data_crash_reports"
    static let exportFormat            = "data_export_format"          // "csv"|"json"|"sqlite"
    static let exportDateRange         = "data_export_range"           // "7d"|"30d"|"all"|"custom"

    // Grouping
    static let sensorGrouping          = "grouping_sensors"            // group id or "none"
    static let zoneGrouping            = "grouping_zones"
}

// MARK: - Color Hex Extension

extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - View Modifiers

struct DSCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .shadow(color: DS.Color.cardShadow, radius: 4, x: 0, y: 2)
    }
}

struct DSPageBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.Color.background.ignoresSafeArea())
    }
}

extension View {
    func dsCard() -> some View { modifier(DSCardModifier()) }
    func dsBackground() -> some View { modifier(DSPageBackgroundModifier()) }
}

// MARK: - Reusable Components

// MARK: DSCard
struct DSCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = DS.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .dsCard()
    }
}

// MARK: DSStatCard
struct DSStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var trend: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.badge))
                Spacer()
                if let trend {
                    Text(trend)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            Text(value)
                .font(DS.Font.statSmall)
                .foregroundStyle(DS.Color.textPrimary)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }
}

// MARK: DSStatusDot
struct DSStatusDot: View {
    enum Status { case online, offline, warning, unknown }
    let status: Status
    var size: CGFloat = 8

    var color: Color {
        switch status {
        case .online:  return DS.Color.online
        case .offline: return DS.Color.error
        case .warning: return DS.Color.warning
        case .unknown: return DS.Color.textTertiary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: 2)
    }
}

// MARK: DSBadge
struct DSBadge: View {
    let text: String
    let color: Color
    var small: Bool = false

    var body: some View {
        Text(text)
            .font(small ? DS.Font.footnote : DS.Font.label)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, small ? 6 : DS.Spacing.sm)
            .padding(.vertical, small ? 2 : DS.Spacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: DSMoistureBar
struct DSMoistureBar: View {
    let value: Double // 0–100
    var height: CGFloat = 6
    var showLabel: Bool = false
    var criticalThreshold: Double = 20
    var dryThreshold: Double = 25
    var highThreshold: Double = 40

    var color: Color {
        if value < criticalThreshold { return DS.Color.error }
        if value < dryThreshold { return DS.Color.warning }
        if value >= highThreshold { return Color(hex: "0EA5E9") } // blue for high moisture
        return DS.Color.online
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if showLabel {
                Text("\(Int(value))%")
                    .font(DS.Font.footnote)
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(DS.Color.separator)
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(value, 100)) / 100))
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: DSCircleGauge
struct DSCircleGauge: View {
    let value: Double // 0–100
    let size: CGFloat
    var lineWidth: CGFloat = 8
    var label: String? = nil

    var color: Color { DS.Color.moisture(value) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.Color.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(value, 100)) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: value)
            VStack(spacing: 0) {
                Text("\(Int(value))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if let label {
                    Text(label)
                        .font(.system(size: size * 0.13))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: DSEmptyState
struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Refresh"

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(message)
                    .font(DS.Font.cardBody)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "arrow.clockwise")
                        .font(DS.Font.buttonLabel)
                }
                .buttonStyle(.bordered)
                .tint(DS.Color.accent)
            }
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}

// MARK: DSLoadingState
struct DSLoadingState: View {
    var label: String = "Loading…"

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView()
                .tint(DS.Color.accent)
            Text(label)
                .font(DS.Font.cardBody)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .dsCard()
    }
}

// MARK: DSErrorBanner
struct DSErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(DS.Font.cardBody)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.error)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.badge))
        .shadow(color: DS.Color.error.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, DS.Spacing.lg)
    }
}

// MARK: DSInlineBanner
struct DSInlineBanner: View {
    enum Style { case info, success, warning, error }
    let message: String
    var style: Style = .info
    var icon: String? = nil

    var color: Color {
        switch style {
        case .info:    return DS.Color.accent
        case .success: return DS.Color.online
        case .warning: return DS.Color.warning
        case .error:   return DS.Color.error
        }
    }

    var defaultIcon: String {
        switch style {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon ?? defaultIcon)
                .foregroundStyle(color)
            Text(message)
                .font(DS.Font.cardBody)
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.badge))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.badge).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

// MARK: DSPrimaryButton
struct DSPrimaryButton: View {
    let label: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var tintColor: Color { isDestructive ? DS.Color.error : DS.Color.accent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(label)
            }
            .font(DS.Font.buttonLabel)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(tintColor)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
        }
        .disabled(isLoading)
    }
}

// MARK: DSRowChevron
struct DSRowChevron: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var badgeColor: Color = DS.Color.accent

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Spacer()

            if let badge {
                DSBadge(text: badge, color: badgeColor, small: true)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: DSSectionHeader
struct DSSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(title.uppercased())
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textSecondary)
                .tracking(0.8)
            if let count {
                Text("(\(count))")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
    }
}

// MARK: DSSettingRow (for Settings lists)
struct DSSettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(DS.Color.textPrimary)

            Spacer()

            if let value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }
}

// MARK: - Haptic Feedback Helper

struct HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(type)
    }
}

// MARK: - Date Extensions

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
