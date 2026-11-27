import SwiftUI
import GhafCore

// First-launch experience: story, three feature cards and the setup question screens.
// Rebuilt from the owner-approved HTML prototype. In-app recreations only (no WidgetKit/ActivityKit).

// MARK: - Copy (ONE place for every user-facing string of this flow; swap wording here only)

struct GhafFirstLaunchCopy {
    struct Message { let bank: String; let text: String; let code: String }
    struct CalmRow { let name: String; let category: String; let amount: String }

    let skip, storyHeadline, start, restore: String
    let f1Headline, tapToPay, debitCard, groceriesJustNow, logged, f1Hint, f1Body, next: String
    let f2Headline, f2Hint, f2Body, f2Note, pro: String
    let f3Headline, f3Hint, f3Body, setUp: String
    let markPaid, remindLater, markedPaid, willRemind, renewsTomorrow, lockDate: String
    let qName, namePlaceholder, qAddress, male, female, addressWhy: String
    let qCurrency, currencyWhy, qBudget, budgetWhy, finish: String
    let pastName, pastAddress, pastCurrency: String
    let categories: [String]
    let leftThisMonth, of: String
    let messages: [Message]
    let typing, now, shop, subscription: String
    let islandTitle, islandSubtitle: String
    let calm: [CalmRow]
    // Setup steps the prototype does not have (kept from the previous onboarding).
    let accountsTitle, accountsWhy, incomeTitle, incomeWhy, setUpAutomation, back: String

    static func forLanguage(_ code: String) -> GhafFirstLaunchCopy { code == "ar" ? .ar : .en }

    static let en = GhafFirstLaunchCopy(
        skip: "Skip", storyHeadline: "Managing your payments just got easier.", start: "Get started", restore: "Restore a backup",
        f1Headline: "Every payment, logged automatically.", tapToPay: "Tap to pay", debitCard: "Debit", groceriesJustNow: "Groceries · just now", logged: "Logged",
        f1Hint: "Tap the card", f1Body: "Bank messages turn into logged payments, with the shop and category filled in.", next: "Continue",
        f2Headline: "Your spending, clear at a glance.", f2Hint: "Tap a petal", f2Body: "Each petal is a category. It fills as you spend and changes colour when you go over.", f2Note: "Some advanced statistics and widgets need a subscription.", pro: "Pro",
        f3Headline: "All your subscriptions in one view.", f3Hint: "Try the buttons", f3Body: "A reminder the day before each renewal, right on your Lock Screen.", setUp: "Set up",
        markPaid: "Mark paid", remindLater: "Remind me later", markedPaid: "Marked as paid", willRemind: "We'll remind you at 6 PM", renewsTomorrow: "Renews tomorrow",
        lockDate: "Tuesday 25 November",
        qName: "What's your name?", namePlaceholder: "Your name", qAddress: "Choose how we address you", male: "Male", female: "Female",
        addressWhy: "Only used to speak to you with the right Arabic forms.", qCurrency: "Pick your currency", currencyWhy: "You can add accounts in other currencies later.",
        qBudget: "Choose how to split your budget", budgetWhy: "A starting point. You can change every petal later.", finish: "Finish",
        pastName: "Name", pastAddress: "Address", pastCurrency: "Currency",
        categories: ["Groceries", "Dining", "Transport", "Bills", "Shopping", "Fun"], leftThisMonth: "left this month", of: "of",
        messages: [.init(bank: "Emirates NBD", text: "Purchase of AED 45.00 at CARREFOUR", code: "EN"), .init(bank: "Al Rajhi Bank", text: "Purchase of SAR 120.00 at JARIR", code: "RJ"),
                   .init(bank: "ADCB", text: "Card ending 4021 used for AED 18.50", code: "AD"), .init(bank: "FAB", text: "AED 230.00 debited at ADNOC", code: "FA"),
                   .init(bank: "Mashreq", text: "Txn AED 64.00 at NOON.COM", code: "MQ"), .init(bank: "Emirates NBD", text: "Purchase of AED 12.00 at CAFE", code: "EN")],
        typing: "Typing them in one by one…", now: "now", shop: "Carrefour", subscription: "Netflix",
        islandTitle: "6 payments logged", islandSubtitle: "Sorted into 4 categories · just now",
        calm: [.init(name: "Carrefour", category: "Groceries", amount: "−45.00"), .init(name: "ADNOC", category: "Transport", amount: "−230.00"),
               .init(name: "Noon", category: "Shopping", amount: "−64.00"), .init(name: "Salary", category: "Income", amount: "+9,500.00")],
        accountsTitle: "Where do you keep your money?", accountsWhy: "Each balance stays separate in its own currency.",
        incomeTitle: "Your income and salary day", incomeWhy: "These numbers help calculate a realistic daily spending limit.",
        setUpAutomation: "Set up automatic tracking", back: "Back")

    static let ar = GhafFirstLaunchCopy(
        skip: "تخطي", storyHeadline: "أصبحت إدارة مدفوعاتك أسهل.", start: "ابدأ", restore: "استعد نسخة احتياطية",
        f1Headline: "تُسجَّل كل معاملة تلقائياً.", tapToPay: "اضغط للدفع", debitCard: "بطاقة خصم", groceriesJustNow: "بقالة · الآن", logged: "سُجِّلت",
        f1Hint: "اضغط على البطاقة", f1Body: "تتحول رسائل البنك إلى معاملات مسجلة، مع اسم المتجر وتصنيفه.", next: "متابعة",
        f2Headline: "تابع إنفاقك بوضوح.", f2Hint: "اضغط على إحدى البتلات", f2Body: "تمثل كل بتلة فئة إنفاق؛ وتزداد مع زيادة إنفاقك، ويتغير لونها عند تجاوز الحد.", f2Note: "تتطلب بعض الإحصاءات المتقدمة والودجات اشتراكاً.", pro: "غاف برو",
        f3Headline: "تابع اشتراكاتك كلها في مكان واحد.", f3Hint: "جرّب الأزرار", f3Body: "يصلك تنبيه قبل موعد التجديد بيوم، على شاشة القفل.", setUp: "أكمل إعداد حسابك",
        markPaid: "تم الدفع", remindLater: "ذكّرني لاحقاً", markedPaid: "تم تسجيله مدفوعاً", willRemind: "سيصلك تذكير عند الساعة 6 مساءً", renewsTomorrow: "يتجدد غداً",
        lockDate: "الثلاثاء 25 نوفمبر",
        qName: "ما اسمك؟", namePlaceholder: "اسمك", qAddress: "اختر صيغة المخاطبة", male: "ذكر", female: "أنثى",
        addressWhy: "نستخدم هذا الاسم لمخاطبتك بالصيغة المناسبة.", qCurrency: "اختر عملتك", currencyWhy: "يمكنك إضافة حسابات بعملات أخرى لاحقاً.",
        qBudget: "اختر طريقة توزيع ميزانيتك", budgetWhy: "ابدأ بهذا التوزيع، ويمكنك تعديل كل فئة لاحقاً.", finish: "تم",
        pastName: "الاسم", pastAddress: "المخاطبة", pastCurrency: "العملة",
        categories: ["بقالة", "مطاعم", "مواصلات", "فواتير", "تسوق", "ترفيه"], leftThisMonth: "المتبقي هذا الشهر", of: "من",
        messages: [.init(bank: "الإمارات دبي الوطني", text: "شراء بمبلغ 45.00 درهم من كارفور", code: "EN"), .init(bank: "مصرف الراجحي", text: "شراء بمبلغ 120.00 ريال من جرير", code: "RJ"),
                   .init(bank: "أبوظبي التجاري", text: "دفعت 18.50 درهم ببطاقة 4021", code: "AD"), .init(bank: "بنك أبوظبي الأول", text: "خصم 230.00 درهم في أدنوك", code: "FA"),
                   .init(bank: "المشرق", text: "عملية بمبلغ 64.00 درهم في نون", code: "MQ"), .init(bank: "الإمارات دبي الوطني", text: "شراء بمبلغ 12.00 درهم من مقهى", code: "EN")],
        typing: "تُسجَّل العمليات واحدة تلو الأخرى…", now: "الآن", shop: "كارفور", subscription: "نتفليكس",
        islandTitle: "سُجِّلت 6 معاملات", islandSubtitle: "وُزِّعت على 4 فئات · الآن",
        calm: [.init(name: "كارفور", category: "بقالة", amount: "−45.00"), .init(name: "أدنوك", category: "مواصلات", amount: "−230.00"),
               .init(name: "نون", category: "تسوّق", amount: "−64.00"), .init(name: "الراتب", category: "دخل", amount: "+9,500.00")],
        accountsTitle: "أين تحتفظ بأموالك؟", accountsWhy: "يظل كل رصيد منفصلاً بعملته.",
        incomeTitle: "دخلك وموعد الراتب", incomeWhy: "تساعد هذه الأرقام على حساب حد يومي واقعي للإنفاق.",
        setUpAutomation: "إعداد التتبع التلقائي", back: "رجوع")
}

// MARK: - Palette (owner approved with the HTML prototype; the only hex literals allowed in this flow)

enum GhafFirstLaunchPalette {
    struct Card { let base: Color; let blobs: [(color: Color, x: CGFloat, y: CGFloat)] }
    static let payment = Card(base: hex(0x1B1E3B), blobs: [(hex(0x5D7BFF), 0.2, 0.25), (hex(0x9B5CFF), 0.85, 0.6), (hex(0x1BC6D9), 0.3, 0.95)])
    static let widget = Card(base: hex(0xE25A4F), blobs: [(hex(0xFFB36B), 0.8, 0.2), (hex(0xFF6F7D), 0.15, 0.7), (hex(0xFFD9A8), 0.85, 0.95)])
    static let renewal = Card(base: hex(0x0F6E5C), blobs: [(hex(0x7FE3C3), 0.2, 0.2), (hex(0x2BA88C), 0.85, 0.7), (hex(0xCFF5E8), 0.2, 0.95)])
    static let payCardTop = hex(0x2A2C33), payCardBottom = hex(0x0C0D10)
    static let chipTop = hex(0xD9C38A), chipBottom = hex(0xA8935A)
    static let renewalLogo = hex(0xE50914)

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Audio hook (voiceover is parked; every screen calls this when it appears)

enum GhafFirstLaunchScreen: String {
    case story, payment, widget, renewal, name, address, currency, budget, accounts, income
}

enum GhafFirstLaunchAudio {
    /// No-op for now. Voiceover and the music bed attach here later, one clip per screen and language.
    static func onScreenAppear(_ screen: GhafFirstLaunchScreen, languageCode: String) {
        if screen == .name { fadeMusicOutAndStop(over: 1.2) } // setup steps have no voice and no music
    }
    /// No-op for now. Entering the name step fades the music bed out over `seconds` and stops it.
    static func fadeMusicOutAndStop(over seconds: Double) {}
}

// MARK: - Small shared pieces

private extension View {
    /// Keeps amounts and digits in reading order inside right-to-left layouts.
    func firstLaunchLTR() -> some View { environment(\.layoutDirection, .leftToRight) }
}

/// Hardware Dynamic Island position: 11 pt below the top on a 59 pt inset, scaling with the inset.
private func islandTop(_ safeTop: CGFloat) -> CGFloat { max(safeTop - 48, 11) }

private struct GhafIslandTickShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 44
        var p = Path()
        p.move(to: CGPoint(x: 15 * s, y: 22.5 * s))
        p.addLine(to: CGPoint(x: 19.5 * s, y: 27 * s))
        p.addLine(to: CGPoint(x: 28.5 * s, y: 17.5 * s))
        return p
    }
}

/// Green ring and tick that draw themselves.
private struct GhafIslandCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring = false
    @State private var tick = false

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.11))
            Circle().trim(from: 0, to: ring ? 1 : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).padding(2)
            GhafIslandTickShape().trim(from: 0, to: tick ? 1 : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 44)
        .onAppear {
            if reduceMotion { ring = true; tick = true; return }
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) { ring = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.85)) { tick = true }
        }
        .accessibilityHidden(true)
    }
}

enum GhafIslandContent: Equatable {
    case rest
    case counter(Int)
    case message(title: String, subtitle: String, amount: String?)
}

/// A simulated Dynamic Island drawn in-app at the hardware island position.
private struct GhafSimulatedIsland: View {
    let content: GhafIslandContent
    let maxWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var size: CGSize {
        switch content {
        case .rest: CGSize(width: 124, height: 36)
        case .counter: CGSize(width: 220, height: 36)
        case .message: CGSize(width: min(362, maxWidth - 28), height: 88)
        }
    }

    var body: some View {
        ZStack {
            switch content {
            case .rest: EmptyView()
            case .counter(let n):
                HStack {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.green.opacity(pulse ? 0 : 0.6), lineWidth: 4).scaleEffect(pulse ? 2 : 1))
                    Spacer()
                    Text("\(n)").font(GhafTypography.number(14, weight: .semibold)).foregroundStyle(Color.green)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).firstLaunchLTR()
                .transition(.opacity.animation(.easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.18)))
            case .message(let title, let subtitle, let amount):
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let amount { Text(amount).font(GhafTypography.number(17, weight: .semibold)).firstLaunchLTR() }
                    GhafIslandCheck().id(title)
                }
                .padding(.horizontal, 20)
                .transition(.opacity.animation(.easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.18)))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height)
        .background(Color.black, in: RoundedRectangle(cornerRadius: size.height / 2, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: size.height / 2, style: .continuous))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2), value: content)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

private struct GhafFirstLaunchWhiteButtonStyle: ButtonStyle {
    let theme: GhafTheme
    let languageCode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }
}

private struct GhafChoiceStyle: ButtonStyle {
    let theme: GhafTheme
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22).frame(minHeight: 52)
            .foregroundStyle(selected ? theme.inkText : theme.ink)
            .background(selected ? theme.ink : theme.background, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }
}

// MARK: - 1. Story

struct GhafStoryScreen: View {
    let copy: GhafFirstLaunchCopy
    let theme: GhafTheme
    let languageCode: String
    let safeTop: CGFloat
    let onStart: () -> Void
    let onRestore: () -> Void
    let onToggleLanguage: () -> Void

    private enum Pose { case hidden, shown, gone }
    private let rowStep: CGFloat = 70

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var poses = Array(repeating: Pose.hidden, count: 6)
    @State private var typing = false
    @State private var island = GhafIslandContent.rest
    @State private var calm = false
    @State private var ended = false

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                theme.surface
                    .contentShape(Rectangle())
                    .onTapGesture { ended = true }
                    .accessibilityHidden(true)

                Group {
                    pile.padding(.top, safeTop + 58).padding(.horizontal, 16)
                    Text(copy.typing)
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, safeTop + 18)
                        .opacity(typing ? 1 : 0)
                    calmList.padding(.top, safeTop + 54).padding(.horizontal, 22)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onToggleLanguage) {
                            Text(ar ? "EN" : "ع").font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                                .padding(.horizontal, 14).frame(minHeight: 44)
                        }
                        .accessibilityLabel(ar ? "English" : "العربية")
                        Spacer()
                        Button { ended = true } label: {
                            Text(copy.skip).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                                .padding(.horizontal, 10).frame(minHeight: 44)
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 10).padding(.top, safeTop + 2)
                    Spacer(minLength: 0)
                    footer
                }

                GhafSimulatedIsland(content: island, maxWidth: proxy.size.width)
                    .padding(.top, islandTop(safeTop))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: ended) { if ended { endState() } else { await loop() } }
        .onAppear { if reduceMotion { ended = true }; GhafFirstLaunchAudio.onScreenAppear(.story, languageCode: languageCode) }
    }

    private var pile: some View {
        ZStack(alignment: .top) {
            ForEach(Array(copy.messages.enumerated()), id: \.offset) { index, message in
                messageRow(message)
                    .offset(y: CGFloat(index) * rowStep + (poses[index] == .gone ? -(96 + CGFloat(index) * rowStep) : (poses[index] == .hidden ? -30 : 0)))
                    .scaleEffect(poses[index] == .gone ? 0.2 : (poses[index] == .hidden ? 0.96 : 1), anchor: .top)
                    .opacity(poses[index] == .shown ? 1 : 0)
                    .zIndex(Double(index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private func messageRow(_ message: GhafFirstLaunchCopy.Message) -> some View {
        HStack(spacing: 10) {
            Text(message.code).font(GhafTypography.number(11, weight: .bold)).foregroundStyle(theme.secondaryText)
                .frame(width: 34, height: 34).background(theme.secondaryText.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(message.bank).font(GhafTypography.body(13, languageCode: languageCode, weight: .bold))
                Text(message.text).font(GhafTypography.body(13, languageCode: languageCode))
            }
            .lineLimit(1).foregroundStyle(theme.primaryText)
            Spacer(minLength: 4)
            Text(copy.now).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(height: 58)
        .background(theme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var calmList: some View {
        VStack(spacing: 2) {
            ForEach(Array(copy.calm.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Circle().fill(theme.background).frame(width: 34, height: 34)
                        .overlay(Circle().fill(theme.ink).frame(width: 10, height: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        Text(row.category).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Text(row.amount).font(GhafTypography.number(15, weight: .semibold)).firstLaunchLTR()
                        .foregroundStyle(row.amount.hasPrefix("+") ? theme.credit : theme.primaryText)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.outline).frame(height: 1) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(calm ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.storyHeadline)
                .font(GhafTypography.display(ar ? 38 : 34, languageCode: languageCode))
                .tracking(ar ? 0 : -0.8).lineSpacing(ar ? 4 : 0)
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
            Button(copy.start, action: onStart).ghafProminentButton(theme: theme, languageCode: languageCode)
            Button(copy.restore, action: onRestore).ghafGlassButton(theme: theme, languageCode: languageCode)
        }
        .padding(.horizontal, 22).padding(.bottom, 34).padding(.top, 70)
        .background(LinearGradient(stops: [.init(color: theme.surface.opacity(0), location: 0), .init(color: theme.surface, location: 0.28)], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Timeline (8.2 s loop)

    private func loop() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            resetInstantly()
            let start = clock.now
            var events: [(Int, () -> Void)] = []
            for i in 0..<copy.messages.count {
                events.append((150 + i * 260, { withAnimation(.spring(duration: 0.45, bounce: 0.1)) { poses[i] = .shown } }))
            }
            events.append((900, { withAnimation(.easeOut(duration: 0.3)) { typing = true } }))
            events.append((2600, {
                withAnimation(.easeOut(duration: 0.3)) { typing = false }
                island = .counter(0)
                for i in 0..<copy.messages.count {
                    withAnimation(.timingCurve(0.55, 0, 0.75, 0.2, duration: 0.55).delay(Double(i) * 0.09)) { poses[i] = .gone }
                }
            }))
            for i in 0..<copy.messages.count {
                events.append((3050 + i * 90, { withAnimation { island = .counter(i + 1) } }))
            }
            events.append((3600, { island = .message(title: copy.islandTitle, subtitle: copy.islandSubtitle, amount: nil) }))
            events.append((5200, {
                island = .rest
                withAnimation(.easeOut(duration: 0.6)) { calm = true }
            }))
            for (ms, action) in events.sorted(by: { $0.0 < $1.0 }) {
                try? await clock.sleep(until: start + .milliseconds(ms))
                if Task.isCancelled { return }
                action()
            }
            try? await clock.sleep(until: start + .milliseconds(8200))
        }
    }

    private func resetInstantly() {
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) {
            poses = Array(repeating: .hidden, count: copy.messages.count)
            typing = false; calm = false; island = .rest
        }
    }

    private func endState() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.3)) {
            poses = Array(repeating: .gone, count: copy.messages.count)
            typing = false; island = .rest; calm = true
        }
    }
}

// MARK: - 2-4. Feature cards

enum GhafFeatureKind: Int { case payment = 1, widget, renewal }

struct GhafFeatureCardScreen: View {
    let kind: GhafFeatureKind
    let copy: GhafFirstLaunchCopy
    let theme: GhafTheme
    let languageCode: String
    let currency: String
    let safeTop: CGFloat
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var island = GhafIslandContent.rest
    @State private var payTick = 0
    @State private var liveActivity = false
    @State private var selectedPetal: Int?
    @State private var renewal: Renewal = .pending
    @State private var hintPing = false
    @State private var petalsIn = false

    private enum Renewal { case pending, paid, later }
    private var ar: Bool { languageCode == "ar" }
    private var palette: GhafFirstLaunchPalette.Card {
        switch kind { case .payment: GhafFirstLaunchPalette.payment; case .widget: GhafFirstLaunchPalette.widget; case .renewal: GhafFirstLaunchPalette.renewal }
    }
    private var headline: String { [copy.f1Headline, copy.f2Headline, copy.f3Headline][kind.rawValue - 1] }
    private var hint: String { [copy.f1Hint, copy.f2Hint, copy.f3Hint][kind.rawValue - 1] }
    private var body_: String { [copy.f1Body, copy.f2Body, copy.f3Body][kind.rawValue - 1] }
    private var screenKind: GhafFirstLaunchScreen { [.payment, .widget, .renewal][kind.rawValue - 1] }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                background(size: proxy.size)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { index in
                            Capsule().fill(Color.white.opacity(index <= kind.rawValue ? 1 : 0.35)).frame(height: 3)
                        }
                    }
                    .padding(.top, safeTop + 8).accessibilityHidden(true)
                    Text(headline)
                        .font(GhafTypography.display(40, languageCode: languageCode))
                        .tracking(ar ? 0 : -1.3).lineSpacing(ar ? 6 : 0).minimumScaleFactor(0.7)
                        .foregroundStyle(.white).padding(.top, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    stage
                    Spacer(minLength: 12)
                    foot
                }
                .padding(.horizontal, 22).padding(.bottom, 34)
                if kind == .payment {
                    GhafSimulatedIsland(content: island, maxWidth: proxy.size.width).padding(.top, islandTop(safeTop))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            GhafFirstLaunchAudio.onScreenAppear(screenKind, languageCode: languageCode)
            if reduceMotion { petalsIn = true } else { DispatchQueue.main.async { petalsIn = true } }
        }
        .task(id: payTick) {
            guard payTick > 0 else { return }
            liveActivity = false
            island = .message(title: copy.shop, subtitle: copy.groceriesJustNow, amount: "−45.00")
            try? await Task.sleep(for: .seconds(2.2))
            if Task.isCancelled { return }
            island = .rest
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.15)) { liveActivity = true }
        }
    }

    private func background(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                palette.base
                ForEach(Array(palette.blobs.enumerated()), id: \.offset) { index, blob in
                    let d = Double(index) * 2.1
                    Circle().fill(RadialGradient(colors: [blob.color, blob.color.opacity(0)], center: .center, startRadius: 0, endRadius: size.width * 0.55))
                        .frame(width: size.width * 1.1, height: size.width * 1.1)
                        .position(x: size.width * blob.x + CGFloat(sin(t / 7 + d)) * size.width * 0.05,
                                  y: size.height * blob.y + CGFloat(cos(t / 9 + d)) * size.height * 0.03)
                }
            }
            .frame(width: size.width, height: size.height).clipped()
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }

    @ViewBuilder private var stage: some View {
        switch kind {
        case .payment: paymentStage
        case .widget: widgetStage
        case .renewal: renewalStage
        }
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                    .scaleEffect(hintPing ? 1.6 : 1).opacity(hintPing ? 0.3 : 1)
                Text(hint).font(GhafTypography.body(12, languageCode: languageCode, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { hintPing = true }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(body_).font(GhafTypography.body(14, languageCode: languageCode))
                    .foregroundStyle(Color.white.opacity(0.72)).lineSpacing(3)
                if kind == .widget {
                    Text(copy.f2Note).font(GhafTypography.body(12, languageCode: languageCode))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            Button(kind == .renewal ? copy.setUp : copy.next, action: onNext)
                .buttonStyle(GhafFirstLaunchWhiteButtonStyle(theme: theme, languageCode: languageCode))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Card 1: tap the card, the island shows the payment, then a Lock Screen live activity appears.
    private var paymentStage: some View {
        VStack(spacing: 14) {
            Button { payTick += 1 } label: {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [GhafFirstLaunchPalette.payCardTop, GhafFirstLaunchPalette.payCardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(copy.debitCard).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).opacity(0.8).padding(.leading, 20).padding(.top, 16)
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [GhafFirstLaunchPalette.chipTop, GhafFirstLaunchPalette.chipBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 26).padding(.leading, 20).padding(.top, 50)
                    Text("•••• 4021").font(GhafTypography.number(14, weight: .medium)).tracking(1.6).opacity(0.85)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 20).padding(.bottom, 18)
                    Text(copy.tapToPay).font(GhafTypography.body(11, languageCode: languageCode, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.14), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 16).padding(.bottom, 14)
                }
                .foregroundStyle(.white).firstLaunchLTR()
                .frame(width: 250, height: 158)
                .rotationEffect(.degrees(reduceMotion ? 0 : -6))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 20)
            }
            .buttonStyle(.plain).accessibilityLabel(copy.tapToPay)
            if liveActivity {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white).frame(width: 40, height: 40)
                        .overlay(Circle().fill(theme.ink).frame(width: 14, height: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(copy.shop).font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                        Text(copy.groceriesJustNow).font(GhafTypography.body(13, languageCode: languageCode))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("−45.00").font(GhafTypography.number(17, weight: .semibold)).firstLaunchLTR()
                        Text(copy.logged).font(GhafTypography.body(11, languageCode: languageCode, weight: .medium)).foregroundStyle(Color.green)
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color(white: 0.11).opacity(0.72), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Card 2: the home-screen widget with Graphite petals; tap a petal for its spent/of.
    private let shares: [Double] = [0.24, 0.18, 0.14, 0.2, 0.14, 0.1]
    private let spent = [620, 410, 180, 900, 520, 160]
    private let budget = [800, 500, 400, 900, 450, 300]

    private func number(_ value: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = GhafLocale.locale(identifier: "en_US")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var widgetStage: some View {
        let apps = HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.28)).aspectRatio(1, contentMode: .fit) }
        }
        return VStack(spacing: 18) {
            apps
            HStack(spacing: 14) {
                petals.frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 4) {
                    if let i = selectedPetal {
                        Text(copy.categories[i]).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                        Text(number(spent[i])).font(GhafTypography.number(24, weight: .bold))
                        Text("\(copy.of) \(number(budget[i]))").font(GhafTypography.body(12, languageCode: languageCode, weight: .medium)).foregroundStyle(theme.glow)
                    } else {
                        Text(currency).font(GhafTypography.number(12, weight: .medium)).foregroundStyle(theme.secondaryText)
                        Text(number(budget.reduce(0, +) - spent.reduce(0, +))).font(GhafTypography.number(24, weight: .bold))
                        Text(copy.leftThisMonth).font(GhafTypography.body(12, languageCode: languageCode, weight: .medium)).foregroundStyle(theme.glow)
                    }
                }
                .foregroundStyle(theme.primaryText).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Text(copy.pro).font(GhafTypography.body(11, languageCode: "en", weight: .bold)).foregroundStyle(theme.ink)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(theme.outline, lineWidth: 1))
                    .padding(10)
            }
            .shadow(color: .black.opacity(0.25), radius: 20, y: 20)
            .rotationEffect(.degrees(reduceMotion ? 0 : -3))
            .offset(x: reduceMotion ? 0 : (ar ? -14 : 14))
            apps
        }
    }

    private var petals: some View {
        let radius: CGFloat = 66, inner: CGFloat = 0.34
        let gap = 3 / radius * 180 / .pi
        var cursor = -90.0
        let ranges: [(Double, Double)] = shares.map { share in
            defer { cursor += 360 * share }
            return (cursor + gap / 2, cursor + 360 * share - gap / 2)
        }
        return ZStack {
            ForEach(0..<shares.count, id: \.self) { i in
                let ratio = Double(spent[i]) / Double(budget[i])
                let color = ratio > 1 ? theme.over : theme.accent
                let fillOuter = inner + (1 - inner) * CGFloat(max(0.08, min(ratio, 1)))
                GhafPetalSegment(start: ranges[i].0, end: ranges[i].1, inner: inner, outer: 1)
                    .fill(color.opacity(0.18)).frame(width: radius * 2, height: radius * 2)
                    .overlay {
                        GhafAnimatedPetalFill(start: ranges[i].0, end: ranges[i].1, inner: inner, outer: petalsIn ? fillOuter : inner + 0.02).fill(color)
                            .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.1).delay(0.08 * Double(i)), value: petalsIn)
                    }
                    .opacity(selectedPetal == nil || selectedPetal == i ? 1 : 0.35)
                    .contentShape(GhafPetalSegment(start: ranges[i].0, end: ranges[i].1, inner: inner, outer: 1))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { selectedPetal = selectedPetal == i ? nil : i } }
                    .accessibilityElement().accessibilityLabel("\(copy.categories[i]), \(number(spent[i])) \(copy.of) \(number(budget[i]))")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    // Card 3: Lock Screen renewal with working buttons.
    private var renewalStage: some View {
        VStack(spacing: 0) {
            Text("9:41").font(GhafTypography.number(86, weight: .semibold)).tracking(-2.5).foregroundStyle(Color.white.opacity(0.95)).firstLaunchLTR()
            Text(copy.lockDate).font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85)).padding(.bottom, 26)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("N").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(GhafFirstLaunchPalette.renewalLogo, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(copy.subscription).font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                        Text(copy.renewsTomorrow).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Text("56.00").font(GhafTypography.number(18, weight: .bold)).firstLaunchLTR()
                }
                if renewal == .pending {
                    HStack(spacing: 8) {
                        Button(copy.markPaid) { withAnimation(.easeOut(duration: 0.2)) { renewal = .paid } }
                            .buttonStyle(GhafRenewalButton(theme: theme, languageCode: languageCode, primary: true))
                        Button(copy.remindLater) { withAnimation(.easeOut(duration: 0.2)) { renewal = .later } }
                            .buttonStyle(GhafRenewalButton(theme: theme, languageCode: languageCode, primary: false))
                    }
                } else {
                    Label(renewal == .paid ? copy.markedPaid : copy.willRemind, systemImage: "checkmark")
                        .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.credit)
                        .frame(minHeight: 40, alignment: .leading)
                }
            }
            .foregroundStyle(theme.ink).padding(16)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 20)
            .rotationEffect(.degrees(reduceMotion ? 0 : 2)).offset(x: reduceMotion ? 0 : (ar ? 10 : -10))
        }
    }
}

/// GhafPetalSegment with an animatable outer radius, so the fill can grow in. Draws the same path.
private struct GhafAnimatedPetalFill: Shape {
    var start: Double, end: Double, inner: CGFloat, outer: CGFloat
    var animatableData: CGFloat { get { outer } set { outer = newValue } }
    func path(in rect: CGRect) -> Path { GhafPetalSegment(start: start, end: end, inner: inner, outer: outer).path(in: rect) }
}

private struct GhafRenewalButton: ButtonStyle {
    let theme: GhafTheme
    let languageCode: String
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(primary ? theme.inkText : theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(primary ? theme.ink : theme.ink.opacity(0.07), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }
}

// MARK: - Setup scaffold (one question per screen)

struct GhafSetupScaffold<Content: View>: View {
    let theme: GhafTheme
    let languageCode: String
    let backLabel: String
    let safeTop: CGFloat
    let title: String
    var past: [(label: String, value: String)] = []
    var longForm = false
    var why: String?
    let button: String
    var secondaryButton: String?
    var secondaryAction: () -> Void = {}
    var enabled = true
    let onBack: () -> Void
    let onToggleLanguage: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: Content

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        ZStack(alignment: .top) {
            theme.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44).background(theme.background, in: Circle())
                            .scaleEffect(x: ar ? -1 : 1)
                    }.accessibilityLabel(backLabel)
                    Spacer()
                    Button(action: onToggleLanguage) {
                        Text(ar ? "EN" : "ع").font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                    }.accessibilityLabel(ar ? "English" : "العربية")
                }
                .buttonStyle(.plain).foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14).padding(.top, safeTop + 4)

                // Previous answers, faded, above the question.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(past.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            Text(row.label).fontWeight(.semibold).foregroundStyle(theme.secondaryText.opacity(0.7))
                            Text(row.value).foregroundStyle(theme.secondaryText.opacity(0.45))
                        }
                        .font(GhafTypography.body(15, languageCode: languageCode)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: longForm ? 12 : 96, alignment: .top)
                .padding(.horizontal, 24).padding(.top, longForm ? 4 : 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(title)
                            .font(GhafTypography.display(ar ? 36 : 34, languageCode: languageCode))
                            .tracking(ar ? 0 : -0.7).lineSpacing(ar ? 4 : 0)
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        content
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                if let why {
                    Text(why).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText.opacity(0.85))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                Button(button, action: onNext).ghafProminentButton(theme: theme, languageCode: languageCode).disabled(!enabled)
                if let secondaryButton {
                    Button(secondaryButton, action: secondaryAction).ghafGlassButton(theme: theme, languageCode: languageCode)
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 34)
            .background(theme.surface)
        }
        .foregroundStyle(theme.primaryText)
    }
}

/// Choice chip used by the address, currency and budget-split questions.
struct GhafSetupChoice<Label: View>: View {
    let theme: GhafTheme
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    var body: some View {
        Button(action: action) { label.frame(maxWidth: .infinity) }
            .buttonStyle(GhafChoiceStyle(theme: theme, selected: selected))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Simple wrapping flow of chips.
struct GhafFlow: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}

/// Budget split drawn as petals (same GhafPetalSegment as the Budget screen). Ten equal petals, grouped
/// by share (needs, wants, savings), because the segment shape only approximates arcs well below ~90 degrees.
struct GhafSplitPetals: View {
    let theme: GhafTheme
    let shares: [Double]
    var body: some View {
        let radius: CGFloat = 115, inner: CGFloat = 0.34, count = 10
        let gap = 3 / radius * 180 / .pi
        let step = 360.0 / Double(count)
        let groupEnds = shares.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1) }
        let opacities = [1.0, 0.6, 0.32]
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let start = -90 + Double(i) * step + gap / 2, end = -90 + Double(i + 1) * step - gap / 2
                let group = groupEnds.firstIndex { Double(i) + 0.5 < $0 * Double(count) } ?? max(shares.count - 1, 0)
                GhafPetalSegment(start: start, end: end, inner: inner, outer: 1)
                    .fill(theme.accent.opacity(0.12)).frame(width: radius * 2, height: radius * 2)
                    .overlay { GhafPetalSegment(start: start, end: end, inner: inner, outer: inner + (1 - inner) * 0.7).fill(theme.accent.opacity(opacities[min(group, 2)])) }
            }
        }
        .frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}
