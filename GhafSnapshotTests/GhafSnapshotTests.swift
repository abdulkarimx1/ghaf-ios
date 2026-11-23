import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Ghaf

enum SnapshotScreen: String, CaseIterable, Sendable {
    case home
    case transactions
    case statsWeek
    case statsMonth
    case statsQuarter
    case statsYear
    case budget
    case wallet
    case subscriptions
    case more
    case profile
    case widgets
    case pro
    case bankAutomation
}

struct SnapshotCase: Sendable, CustomTestStringConvertible {
    let screen: SnapshotScreen
    let appearance: String
    let language: String

    var testDescription: String { "\(screen.rawValue)-\(appearance.lowercased())-\(language)" }
    var snapshotName: String { testDescription }

    static let all: [SnapshotCase] = SnapshotScreen.allCases.flatMap { screen in
        ["Light", "Dark"].flatMap { appearance in
            ["en", "ar"].map { language in
                SnapshotCase(screen: screen, appearance: appearance, language: language)
            }
        }
    }
}

@Suite(.serialized, .snapshots(record: .missing))
struct GhafSnapshotTests {
    @Test
    @MainActor
    func primaryScreensMatchReference() async throws {
        for sample in SnapshotCase.all {
            try await assertScreen(sample)
        }
    }

    @MainActor
    private func assertScreen(_ sample: SnapshotCase) async throws {
        // The automation reference's Mashreq sample is 15 hours old; freeze that view's anchor
        // to the capture time used for that reference instead of reading wall-clock time.
        let fixedNow = fixedSnapshotDate().addingTimeInterval(sample.screen == .bankAutomation ? 60 * 60 : 0)
        GhafClock.snapshotNow = fixedNow
        GhafScreenshotFixture.snapshotTestingEnabled = true
        GhafScreenshotFixture.snapshotScreenOverride = sample.screen == .profile ? "profile-proof" : nil
        let defaults = UserDefaults.standard
        let savedAutomationDefaults = sample.screen == .bankAutomation
            ? defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("ghaf.automation.") }
            : [:]
        if sample.screen == .bankAutomation { GhafScreenshotFixture.applyAutomation(state: "working") }
        defer {
            if sample.screen == .bankAutomation {
                for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ghaf.automation.") {
                    defaults.removeObject(forKey: key)
                }
                for (key, value) in savedAutomationDefaults { defaults.set(value, forKey: key) }
            }
            GhafClock.snapshotNow = nil
            GhafScreenshotFixture.snapshotTestingEnabled = false
            GhafScreenshotFixture.snapshotScreenOverride = nil
            GhafScreenshotFixture.snapshotPeriodOverride = nil
        }

        let container = try GhafScreenshotFixture.makeContainer()
        let settings = try #require(container.mainContext.fetch(FetchDescriptor<GhafSettings>()).first)
        settings.themeName = "Graphite"
        settings.appearanceMode = sample.appearance
        settings.languageCode = sample.language

        let root = makeScreen(sample.screen, settings: settings)
            .modelContainer(container)
            .environment(GhafTabRouter())
            .environment(\.colorScheme, sample.appearance == "Dark" ? .dark : .light)
            .environment(\.locale, Locale(identifier: sample.language == "ar" ? "ar_AE" : "en_AE"))
            .environment(\.calendar, snapshotCalendar())
            .environment(\.layoutDirection, sample.language == "ar" ? .rightToLeft : .leftToRight)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }

        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = sample.appearance == "Dark" ? .dark : .light
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        UIView.setAnimationsEnabled(false)
        defer {
            window.isHidden = true
            UIView.setAnimationsEnabled(true)
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let iPhone17Pro = ViewImageConfig(
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 402, height: 874),
            traits: UITraitCollection()
        )
        assertSnapshot(of: controller, as: .image(on: iPhone17Pro), named: sample.snapshotName)
    }

    @MainActor
    private func makeScreen(_ screen: SnapshotScreen, settings: GhafSettings) -> AnyView {
        switch screen {
        case .home:
            AnyView(GhafHomeView(settings: settings))
        case .transactions:
            AnyView(GhafTransactionsView(settings: settings))
        case .statsWeek:
            AnyView(GhafStatsView(settings: settings, initialPeriod: .week))
        case .statsMonth:
            AnyView(GhafStatsView(settings: settings, initialPeriod: .month))
        case .statsQuarter:
            AnyView(GhafStatsView(settings: settings, initialPeriod: .quarter))
        case .statsYear:
            AnyView(GhafStatsView(settings: settings, initialPeriod: .year))
        case .budget:
            AnyView(GhafBudgetView(settings: settings))
        case .wallet:
            AnyView(GhafAccountsView(settings: settings))
        case .subscriptions:
            AnyView(GhafSubscriptionsView(settings: settings))
        case .more, .profile:
            AnyView(GhafSettingsView(settings: settings))
        case .widgets:
            AnyView(GhafWidgetGalleryView(settings: settings))
        case .pro:
            AnyView(GhafProView(settings: settings, showsClose: false))
        case .bankAutomation:
            AnyView(GhafAutomationGuideView(settings: settings))
        }
    }

    private func fixedSnapshotDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 41))!
    }

    private func snapshotCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        calendar.firstWeekday = 1
        return calendar
    }
}
