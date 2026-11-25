import Foundation
import SwiftData
import WidgetKit
import ActivityKit
import SwiftUI
import UIKit
import AppIntents
import StoreKit
import OSLog
import GhafCore

enum GhafLiveActivityBalance: String, CaseIterable {
    case total = "total"
    case card = "card"
    case hidden = "hidden"
}

/// Keeps the widgets and the purchase Live Activity in step with the ledger.
@MainActor
enum GhafWidgetSync {
    private static let activityProofLogger = Logger(subsystem: "com.ghaf.app", category: "ActivityProof")
    static let liveActivityKey = "ghaf.liveActivity"
    static let liveActivityBalanceKey = "ghaf.liveActivity.balance"
    static let liveActivityEnabledKey = "ghaf.liveActivity.enabled"
    static let liveActivityDurationKey = "ghaf.liveActivity.duration"

    private static var liveActivityDefaults: UserDefaults? {
        GhafWidgetSnapshot.groupIDs.first.flatMap(UserDefaults.init(suiteName:))
    }

    // Only the app reads these, so they live in standard defaults: sideloaded installs often have no
    // working App Group, and writes there were silently lost (settings snapped back to defaults).
    private static func liveActivityValue(_ key: String) -> Any? {
        UserDefaults.standard.object(forKey: key) ?? liveActivityDefaults?.object(forKey: key)
    }

    static var liveActivityEnabled: Bool {
        liveActivityValue(liveActivityEnabledKey) as? Bool
            ?? UserDefaults.standard.object(forKey: liveActivityKey) as? Bool ?? true
    }

    static var liveActivityBalance: GhafLiveActivityBalance {
        (liveActivityValue(liveActivityBalanceKey) as? String).flatMap(GhafLiveActivityBalance.init(rawValue:)) ?? .card
    }

    static var liveActivityDuration: Int {
        liveActivityValue(liveActivityDurationKey) as? Int ?? 300
    }

    static func setLiveActivityPreferences(enabled: Bool, balance: GhafLiveActivityBalance, duration: Int) {
        for defaults in [UserDefaults.standard, liveActivityDefaults].compactMap({ $0 }) {
            defaults.set(enabled, forKey: liveActivityEnabledKey)
            defaults.set(balance.rawValue, forKey: liveActivityBalanceKey)
            defaults.set(duration, forKey: liveActivityDurationKey)
        }
        UserDefaults.standard.set(enabled, forKey: liveActivityKey)
    }
    /// Which channels the last refresh could write, shown in Notifications & widgets so a broken install is visible.
    static private(set) var lastChannels: (group: Bool, keychain: Bool)? = {
        guard let values = UserDefaults.standard.dictionary(forKey: "ghaf.widget.channels"),
              let group = values["group"] as? Bool, let keychain = values["keychain"] as? Bool else { return nil }
        return (group, keychain)
    }()

    /// Recomputes what the widgets show and asks WidgetKit to redraw them.
    static func refresh(context: ModelContext) {
        Task { await refreshWidgetProAccess() }
        guard let settings = try? GhafPersistence.settings(in: context),
              let transactions = try? context.fetch(FetchDescriptor<GhafTransaction>()),
              let accounts = try? context.fetch(FetchDescriptor<GhafAccount>()) else { return }
        let currency = settings.currency
        let calendar = GhafCalendar.current
        let active = accounts.filter { !$0.isArchived && $0.includeInTotal }
        let balance = GhafAccountBalanceCalculator.balancesByCurrency(accounts: active, transactions: transactions)
            .first { $0.currency == currency }?.amount
        let spending = transactions.filter { $0.currency == currency && $0.isExpense }
        let today = spending.filter { calendar.isDateInToday($0.date) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let month = spending.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(Decimal.zero) { $0 + $1.spendingAmount }
        let last = transactions.filter { $0.direction == "debit" && $0.isSpendingOrIncome }.max { $0.date < $1.date }
        let todays = spending.filter { calendar.isDateInToday($0.date) }
        let byCategory = Dictionary(grouping: todays) { GhafLocalization.category($0.category, languageCode: settings.languageCode) }
            .map { GhafWidgetSnapshot.CategorySpend(name: $0.key, amount: $0.value.reduce(Decimal.zero) { $0 + $1.spendingAmount }) }
            .sorted { $0.amount > $1.amount }
        let startOfToday = calendar.startOfDay(for: .now)
        let week: [Decimal] = (0..<7).reversed().map { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: startOfToday) else { return 0 }
            return spending.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(Decimal.zero) { $0 + $1.spendingAmount }
        }
        var snapshot = GhafWidgetSnapshot(currency: currency, balance: balance, spentToday: today, spentThisMonth: month,
                           lastPurchase: last.map { .init(merchant: GhafFormat.balancesHidden ? GhafLocalization.category($0.category, languageCode: settings.languageCode) : (GhafMerchantAliasStore.displayName($0.rawMerchant ?? $0.merchant) ?? GhafLocalization.category($0.category, languageCode: settings.languageCode)),
                                                          amount: $0.amount, currency: $0.currency, date: $0.date) },
                           hidden: GhafFormat.balancesHidden, arabic: settings.languageCode == "ar", updated: .now)
        snapshot.todayCategories = Array(byCategory.prefix(4))
        snapshot.lastSevenDays = week
        let budget = BudgetCalculator.snapshot(settings: settings, transactions: transactions)
        if settings.budgetMode != "Category", budget.hasBudget {
            snapshot.dailyBudgetUsed = NSDecimalNumber(decimal: budget.spent / budget.limit).doubleValue
        }
        let lit = GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true)
        snapshot.accent = hex(lit.accent)
        snapshot.glow = hex(lit.glow)
        snapshot.glass = UserDefaults.standard.object(forKey: "ghaf.glass.enabled") as? Bool ?? true

        let language = settings.languageCode
        let name = { (category: String) in GhafLocalization.category(category, languageCode: language) }
        snapshot.day = period(.day, slices: 8, slice: (.hour, 3), spending: spending, calendar: calendar, name: name)
        snapshot.week = period(.weekOfYear, slices: 7, slice: (.day, 1), spending: spending, calendar: calendar, name: name)
        snapshot.month = period(.month, slices: 5, slice: (.day, 7), spending: spending, calendar: calendar, name: name)

        if let latest = transactions.max(by: { $0.createdAt < $1.createdAt }) {
            snapshot.recent = .init(merchant: GhafFormat.balancesHidden ? name(latest.category) : GhafMerchantAliasStore.displayName(latest.rawMerchant ?? latest.merchant), category: name(latest.category),
                                    symbol: GhafCategoryIcon.builtIn(latest.category)?.symbol ?? (latest.direction == "credit" ? "arrow.down" : "bag.fill"),
                                    amount: latest.amount, currency: latest.currency, date: latest.date,
                                    isCredit: latest.direction == "credit",
                                    account: GhafFormat.balancesHidden ? nil : accounts.first { $0.id == latest.accountID }?.name,
                                    bank: GhafFormat.balancesHidden ? nil : latest.bank, needsReview: latest.needsReview)
        }

        if budget.hasBudget {
            let ar = language == "ar"
            let daily = settings.budgetMode != "Category"
            let end: Date
            if daily {
                end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            } else if settings.salaryEnabled == true, let salaryDay = settings.salaryDay {
                let start = GhafSalaryCycle.startDate(for: .now, salaryDay: salaryDay)
                end = calendar.date(byAdding: .day, value: GhafSalaryCycle.daysInCycle(for: .now, salaryDay: salaryDay), to: start) ?? start
            } else {
                end = calendar.dateInterval(of: .month, for: .now)?.end ?? startOfToday
            }
            snapshot.budget = .init(limit: budget.limit, spent: budget.spent,
                                    title: daily ? (ar ? "ميزانية اليوم" : "Today's budget") : (ar ? "ميزانية الشهر" : "Monthly budget"),
                                    end: end)
        }

        let reviewed = transactions.filter { !$0.needsReview }
        let streakDates = reviewed.map(\.date)
        snapshot.streak = .init(
            days: GhafLoggingStreak.count(streakDates, through: .now, calendar: Calendar.current),
            week: (0..<7).reversed().map { back in
                guard let day = Calendar.current.date(byAdding: .day, value: -back, to: .now) else { return false }
                return streakDates.contains { Calendar.current.isDate($0, inSameDayAs: day) }
            })

        let areas = GhafPlaces.savedAreasByTransaction()
        let monthSpending = spending.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
        snapshot.places = Array(Dictionary(grouping: monthSpending.compactMap { transaction in
            areas[transaction.id.uuidString].map { ($0, transaction.spendingAmount) }
        }, by: \.0)
            .map { GhafWidgetSnapshot.PlaceSpend(name: $0.key, amount: $0.value.reduce(Decimal.zero) { $0 + $1.1 }) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }.prefix(3))

        let innerRadius = 0.16
        // Same petals as the Budget screen: up to 8, with the tail folded into "Other" past 8.
        let petalRows = GhafBudgetPlan(settings: settings, transactions: transactions, calendar: GhafCalendar.current, now: GhafClock.now)
            .categoryRows.filter { $0.spent > 0 && $0.budget > 0 }
        let groupedPetals = petalRows.count > 8
        let shownPetals: [(name: String, spent: Decimal, budget: Decimal)] = Array(petalRows.prefix(groupedPetals ? 7 : 8)).map { ($0.name, $0.spent, $0.budget) }
            + (groupedPetals ? [(settings.languageCode == "ar" ? "أخرى" : "Other",
                                 petalRows.dropFirst(7).reduce(Decimal.zero) { $0 + $1.spent },
                                 petalRows.dropFirst(7).reduce(Decimal.zero) { $0 + $1.budget })] : [])
        snapshot.petals = shownPetals.map {
            // Anything spent stays visible: floor the fill at 8% of the band (same rule as the Budget screen).
            let radii = BudgetAllocation.petalRadii(budget: $0.budget, spent: $0.spent, innerRadius: innerRadius)
            return .init(name: name($0.name), spent: $0.spent, budget: $0.budget,
                         fill: max(radii.fill, innerRadius + (1 - innerRadius) * 0.08), over: $0.spent > $0.budget)
        }
        snapshot.overColor = hex(lit.over)

        if let subscriptions = try? context.fetch(FetchDescriptor<GhafSubscription>()) {
            snapshot.upcoming = subscriptions.filter(\.isActive).sorted { $0.nextPaymentDate < $1.nextPaymentDate }.prefix(6)
                .map { .init(name: $0.name, amount: $0.amount, currency: $0.currency, date: $0.nextPaymentDate,
                             symbol: GhafCategoryIcon.builtIn($0.category)?.symbol ?? "repeat") }
        }
        lastChannels = snapshot.save()
        UserDefaults.standard.set(["group": lastChannels?.group ?? false, "keychain": lastChannels?.keychain ?? false],
                                  forKey: "ghaf.widget.channels")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func refreshWidgetProAccess() async {
        _ = await GhafAITier.refreshVerifiedEntitlement()
        GhafProAccess.syncWidgetFlag()
    }

    /// Call from a LiveActivityIntent's perform() to start while automation runs in the background.
    static func showPurchase(transactionID: UUID) async throws {
        let context = try GhafPersistence.shared().mainContext
        guard let transaction = try context.fetch(FetchDescriptor<GhafTransaction>(predicate: #Predicate { $0.id == transactionID })).first else { return }
        let accounts = try context.fetch(FetchDescriptor<GhafAccount>())
        let account = accounts.first { $0.id == transaction.accountID }
        let transactions = try context.fetch(FetchDescriptor<GhafTransaction>())
        let balance = account.map { GhafAccountBalanceCalculator.balance(for: $0, transactions: transactions) }
        let arabic = (try? GhafPersistence.settings(in: context).languageCode) == "ar"
        await showPurchase(transaction, account: account, balance: balance, accounts: accounts,
                           transactions: transactions, needsReview: transaction.needsReview, arabic: arabic)
    }

    /// One purchase at a time; stale after five minutes and then dismissed at its expiry date.
    static func showPurchase(_ transaction: GhafTransaction, account: GhafAccount?, balance: Decimal?,
                             needsReview: Bool, arabic: Bool) async {
        let context = try? GhafPersistence.shared().mainContext
        let accounts = (try? context?.fetch(FetchDescriptor<GhafAccount>())) ?? []
        let transactions = (try? context?.fetch(FetchDescriptor<GhafTransaction>())) ?? []
        await showPurchase(transaction, account: account, balance: balance, accounts: accounts,
                           transactions: transactions, needsReview: needsReview, arabic: arabic)
    }

    private static func showPurchase(_ transaction: GhafTransaction, account: GhafAccount?, balance: Decimal?,
                                    accounts: [GhafAccount], transactions: [GhafTransaction],
                                    needsReview: Bool, arabic: Bool) async {
        guard liveActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endAll()
        let remainingBalance: Decimal?
        switch liveActivityBalance {
        case .hidden:
            remainingBalance = nil
        case .card:
            remainingBalance = account?.currency == transaction.currency ? balance : nil
        case .total:
            let active = accounts.filter { !$0.isArchived && $0.includeInTotal }
            let currencies = Set(active.map(\.currency))
            if currencies == [transaction.currency] {
                remainingBalance = GhafAccountBalanceCalculator.balancesByCurrency(accounts: active, transactions: transactions)
                    .first { $0.currency == transaction.currency }?.amount
            } else {
                remainingBalance = account?.currency == transaction.currency ? balance : nil
            }
        }
        let expires = Date.now.addingTimeInterval(TimeInterval(liveActivityDuration))
        let state = GhafPurchaseAttributes.ContentState(
            merchant: GhafFormat.balancesHidden ? GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en") : (GhafMerchantAliasStore.displayName(transaction.rawMerchant ?? transaction.merchant) ?? GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en")),
            amount: transaction.amount, currency: transaction.currency, isCredit: transaction.direction == "credit",
            accountName: GhafFormat.balancesHidden ? nil : account?.name,
            balance: GhafFormat.balancesHidden ? nil : remainingBalance, needsReview: needsReview,
            symbol: GhafCategoryIcon.builtIn(transaction.category)?.symbol ?? (transaction.direction == "credit" ? "arrow.down" : "bag.fill"),
            category: GhafLocalization.category(transaction.category, languageCode: arabic ? "ar" : "en"),
            recordedAt: .now, expiresAt: expires, hidden: GhafFormat.balancesHidden, transactionID: transaction.id)
        // The Dynamic Island is always dark, so it takes the theme's dark-mode colours.
        let settings = try? GhafPersistence.settings(in: GhafPersistence.shared().mainContext)
        let theme = GhafTheme.resolve(name: settings?.themeName ?? "Abu Dhabi", appearanceMode: "Dark", systemIsDark: true)
        guard let activity = try? Activity.request(
            attributes: GhafPurchaseAttributes(arabic: arabic, accent: hex(theme.accent), glow: hex(theme.glow)),
            content: .init(state: state, staleDate: expires)
        ) else { return }
        // R4: ending it here (even with .after) removed it from the Dynamic Island at once.
        // Keep it live; end it when it expires (best effort while running; the stale date covers suspension).
        Task {
            try? await Task.sleep(for: .seconds(max(1, expires.timeIntervalSinceNow)))
            await activity.end(.init(state: state, staleDate: expires), dismissalPolicy: .immediate)
        }
    }

    /// Spending in the current day/week/month (main currency, transfers excluded by `isExpense`), cut into
    /// equal slices for the widget bars, plus the whole previous period for comparison.
    private static func period(_ unit: Calendar.Component, slices: Int, slice: (Calendar.Component, Int),
                               spending: [GhafTransaction], calendar: Calendar,
                               name: (String) -> String) -> GhafWidgetSnapshot.Period? {
        guard let now = calendar.dateInterval(of: unit, for: .now),
              let before = calendar.date(byAdding: unit, value: -1, to: now.start),
              let previous = calendar.dateInterval(of: unit, for: before) else { return nil }
        let inside = spending.filter { now.contains($0.date) && $0.date < now.end }
        let sum = { (items: [GhafTransaction]) in items.reduce(Decimal.zero) { $0 + $1.spendingAmount } }
        let bars: [Decimal] = (0..<slices).map { index in
            guard let from = calendar.date(byAdding: slice.0, value: index * slice.1, to: now.start),
                  let to = calendar.date(byAdding: slice.0, value: (index + 1) * slice.1, to: now.start) else { return 0 }
            return sum(inside.filter { $0.date >= from && $0.date < to })
        }
        let categories = Dictionary(grouping: inside, by: \.category)
            .map { GhafWidgetSnapshot.CategorySpend(name: name($0.key), amount: sum($0.value),
                                                    symbol: GhafCategoryIcon.builtIn($0.key)?.symbol) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
        return .init(end: now.end, spent: sum(inside),
                     previous: sum(spending.filter { $0.date >= previous.start && $0.date < previous.end }),
                     count: inside.filter { $0.spendingAmount > 0 }.count, bars: bars, categories: Array(categories.prefix(5)))
    }

    private static func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(max(0, min(255, r * 255))) << 16 | UInt32(max(0, min(255, g * 255))) << 8 | UInt32(max(0, min(255, b * 255)))
    }

    /// Purchases are moments, not ongoing events: clear old ones when Ghaf opens or a new one arrives.
    static func endAll() async {
        for activity in Activity<GhafPurchaseAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func endStale() async {
        for activity in Activity<GhafPurchaseAttributes>.activities where activity.content.staleDate.map({ $0 <= .now }) ?? false {
            await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

#if DEBUG
    /// Starts a fictional purchase so lock screen and Dynamic Island layouts can be captured safely.
    static func runVisualProof() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endAll()
        let start = Date.now
        let expires = start.addingTimeInterval(300)
        let state = GhafPurchaseAttributes.ContentState(
            merchant: "Kookh Al Shay", amount: 3, currency: "AED", isCredit: false,
            accountName: "Mashreq Current", balance: 8_497, needsReview: false,
            symbol: "fork.knife", category: "Food", recordedAt: start, expiresAt: expires)
        do {
            let activity = try Activity.request(
                attributes: GhafPurchaseAttributes(arabic: false, accent: 0x1B6B66, glow: 0x6FD0CC),
                content: ActivityContent(state: state, staleDate: expires))
            await activity.end(ActivityContent(state: state, staleDate: expires), dismissalPolicy: .after(expires))
            activityProofLogger.notice("GHAF_ACTIVITY_VISUAL_PROOF started id=\(activity.id, privacy: .public)")
        } catch {
            activityProofLogger.error("GHAF_ACTIVITY_VISUAL_PROOF request_failed")
        }
    }

    /// Simulator proof hook: request a two-second activity, end it on completion, then record the system's activity inventory.
    static func runLifecycleProof() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activityProofLogger.notice("GHAF_ACTIVITY_PROOF unavailable: Live Activities disabled")
            return
        }
        await endAll()
        let started = Date.now
        let expires = started.addingTimeInterval(2)
        let state = GhafPurchaseAttributes.ContentState(
            merchant: "Lifecycle proof", amount: 1, currency: "AED", isCredit: false,
            accountName: nil, balance: nil, needsReview: false, symbol: "checkmark",
            category: "Proof", recordedAt: started, expiresAt: expires)
        do {
            let activity = try Activity.request(
                attributes: GhafPurchaseAttributes(arabic: false, accent: 0x1B6B66, glow: 0x6FD0CC),
                content: ActivityContent(state: state, staleDate: expires))
            await activity.end(ActivityContent(state: state, staleDate: expires), dismissalPolicy: .after(expires))
            try? await Task.sleep(for: .seconds(3))
            await endStale()
            let count = Activity<GhafPurchaseAttributes>.activities.count
            activityProofLogger.notice("GHAF_ACTIVITY_PROOF ended=\(String(describing: activity.activityState), privacy: .public) active_count=\(count, privacy: .public)")
        } catch {
            activityProofLogger.error("GHAF_ACTIVITY_PROOF request_failed")
        }
    }
#endif
}
