import AppIntents
import SwiftUI
import WidgetKit

// Settings people pick when they long-press a Ghaf widget > Edit Widget, and the buttons inside the widgets.
// These run in the widget extension. The ledger lives in the app, so a refresh re-reads the latest numbers
// Ghaf wrote (it writes them on every recorded transaction and whenever it opens or closes).

enum GhafWidgetPeriod: String, AppEnum {
    case day, week, month
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [GhafWidgetPeriod: DisplayRepresentation] = [
        .day: "Today", .week: "This week", .month: "This month"
    ]
}

enum GhafWidgetStyle: String, AppEnum {
    case ink, theme, light, midnight
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Colour"
    static let caseDisplayRepresentations: [GhafWidgetStyle: DisplayRepresentation] = [
        .ink: "Dark", .theme: "Theme colour", .light: "Light", .midnight: "Midnight blue"
    ]
}

enum GhafWidgetFont: String, AppEnum {
    case standard, rounded, serif, mono
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Font"
    static let caseDisplayRepresentations: [GhafWidgetFont: DisplayRepresentation] = [
        .standard: "Standard", .rounded: "Rounded", .serif: "Serif", .mono: "Monospaced"
    ]
    var design: Font.Design {
        switch self { case .standard: .default; case .rounded: .rounded; case .serif: .serif; case .mono: .monospaced }
    }
    /// Monospaced pulls Arabic letters apart (no joining), so Arabic widgets fall back to the standard design.
    func design(arabic: Bool?) -> Font.Design { arabic == true && self == .mono ? .default : design }
}

/// What tapping the widget does: open Ghaf, or flip the widget to its next view (period, display, window) in place.
enum GhafWidgetTap: String, AppEnum {
    case open, switchView
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "When tapped"
    static let caseDisplayRepresentations: [GhafWidgetTap: DisplayRepresentation] = [
        .open: "Open Ghaf", .switchView: "Switch view"
    ]
}

enum GhafBudgetDisplay: String, AppEnum {
    case left, used
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [GhafBudgetDisplay: DisplayRepresentation] = [
        .left: "What's left", .used: "What's used"
    ]
}

enum GhafBillWindow: Int, AppEnum {
    case week = 7, fortnight = 14, month = 31
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Due within"
    static let caseDisplayRepresentations: [GhafBillWindow: DisplayRepresentation] = [
        .week: "7 days", .fortnight: "14 days", .month: "A month"
    ]
}

// MARK: Configuration intents

struct GhafRecentConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Latest transaction"
    static let description = IntentDescription("The last transaction Ghaf recorded.")
    @Parameter(title: "Colour", default: .theme) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .standard) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Show merchant", default: true) var showMerchant: Bool
    @Parameter(title: "Show account", default: true) var showAccount: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafSpendingConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spending"
    static let description = IntentDescription("What you spent today, this week or this month.")
    @Parameter(title: "Start on", default: .week) var period: GhafWidgetPeriod
    @Parameter(title: "Colour", default: .ink) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .rounded) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Compare with last period", default: true) var compare: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafBudgetConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Budget"
    static let description = IntentDescription("How much of your budget is left.")
    @Parameter(title: "Show", default: .left) var display: GhafBudgetDisplay
    @Parameter(title: "Colour", default: .theme) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .serif) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Show last 7 days", default: true) var showWeek: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafCategoriesConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Where it went"
    static let description = IntentDescription("Your top spending categories.")
    @Parameter(title: "Start on", default: .month) var period: GhafWidgetPeriod
    @Parameter(title: "Colour", default: .ink) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .mono) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Show amounts", default: true) var showAmounts: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafBillsConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Upcoming payments"
    static let description = IntentDescription("Subscriptions due soon.")
    @Parameter(title: "Due within", default: .fortnight) var window: GhafBillWindow
    @Parameter(title: "Colour", default: .ink) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .rounded) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Show total", default: true) var showTotal: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafBalanceConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Balance"
    static let description = IntentDescription("Your total balance and this month's spending.")
    @Parameter(title: "Colour", default: .ink) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .standard) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Show last 7 days", default: true) var showWeek: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafTodayConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Today"
    static let description = IntentDescription("What you spent today, by category.")
    @Parameter(title: "Colour", default: .theme) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .standard) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .open) var onTap: GhafWidgetTap
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

struct GhafTrendsConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Trends"
    static let description = IntentDescription("How your spending is moving, like a stock chart.")
    @Parameter(title: "Start on", default: .week) var period: GhafWidgetPeriod
    @Parameter(title: "Colour", default: .midnight) var style: GhafWidgetStyle
    @Parameter(title: "Font", default: .standard) var font: GhafWidgetFont
    @Parameter(title: "When tapped", default: .switchView) var onTap: GhafWidgetTap
    @Parameter(title: "Show change", default: true) var showChange: Bool
    @Parameter(title: "Fill under the line", default: true) var showFill: Bool
    @Parameter(title: "Glass effect", default: false) var glass: Bool
}

// MARK: Button actions

/// Moves a widget to its next view when it is tapped (see GhafWidgetTap). The step is kept per widget kind.
struct GhafNextViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Next view"
    static let isDiscoverable = false
    @Parameter(title: "Widget") var kind: String
    init() {}
    init(kind: String) { self.kind = kind }
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Self.count(kind) + 1, forKey: Self.key(kind))
        return .result()
    }
    static func key(_ kind: String) -> String { "ghaf.widget.step.\(kind)" }
    static func count(_ kind: String) -> Int { UserDefaults.standard.integer(forKey: key(kind)) }
}


/// Reloads the widget from the numbers Ghaf last wrote.
struct GhafRefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Ghaf widget"
    static let isDiscoverable = false
    @Parameter(title: "Widget") var kind: String
    init() {}
    init(kind: String) { self.kind = kind }
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        return .result()
    }
}

/// Switches a widget between today, this week and this month. The choice is kept per widget kind and per
/// configured start period, so editing the widget's "Start on" setting starts from that period again.
struct GhafSelectPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "Show period"
    static let isDiscoverable = false
    @Parameter(title: "Widget") var kind: String
    @Parameter(title: "Configured") var configured: GhafWidgetPeriod
    @Parameter(title: "Period") var period: GhafWidgetPeriod
    init() {}
    init(kind: String, configured: GhafWidgetPeriod, period: GhafWidgetPeriod) {
        self.kind = kind; self.configured = configured; self.period = period
    }
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(period.rawValue, forKey: Self.key(kind, configured))
        return .result()
    }

    static func key(_ kind: String, _ configured: GhafWidgetPeriod) -> String { "ghaf.widget.period.\(kind).\(configured.rawValue)" }
    static func current(_ kind: String, configured: GhafWidgetPeriod) -> GhafWidgetPeriod {
        UserDefaults.standard.string(forKey: key(kind, configured)).flatMap(GhafWidgetPeriod.init(rawValue:)) ?? configured
    }
}
