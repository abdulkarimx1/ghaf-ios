import SwiftUI
import StoreKit

private struct GhafProHeroEntrance: ViewModifier {
    let isActive: Bool
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.94)
                .offset(y: isVisible ? 0 : 10)
        } else {
            content
        }
    }
}

struct GhafProFeatureMask<Content: View>: View {
    let isUnlocked: Bool
    let theme: GhafTheme
    let languageCode: String
    let action: () -> Void
    let content: Content

    init(isUnlocked: Bool, theme: GhafTheme, languageCode: String, action: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.isUnlocked = isUnlocked
        self.theme = theme
        self.languageCode = languageCode
        self.action = action
        self.content = content()
    }

    private var ar: Bool { languageCode == "ar" }

    var body: some View {
        content
            .overlay {
                if !isUnlocked {
                    Rectangle().fill(theme.background.opacity(0.35)).overlay {
                        Button(action: action) {
                            Label(ar ? "ميزة Pro" : "Pro feature", systemImage: "lock.fill")
                                .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                                .foregroundStyle(theme.primaryText).padding(.horizontal, 18).frame(minHeight: 48)
                                .background(theme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))
    }
}

struct GhafProView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let settings: GhafSettings
    var showsClose = true
    var allowsHeroMotion = true

    @State private var yearly = true
    private let monthlyID = "com.ghaf.app.pro.monthly"
    private let yearlyID = "com.ghaf.app.pro.yearly"
    @State private var products: [Product] = []
    @State private var isLoadingProducts = false
    @State private var productLoadFailed = false
    @State private var introOfferEligibility: [String: Bool] = [:]
    @State private var busy = false
    @State private var redeeming = false
    @AppStorage("ghaf.pro.offerHighlight") private var offerHighlight = false
    @State private var notice: String?
    @State private var codeEntryVisible = false
    @State private var accessCode = ""
    @State private var redeemingAccessCode = false
    @State private var accessRevision = 0
    @State private var heroAppeared: Bool
    private enum VoiceAllowance {
        // Keep aligned with backend/ghaf-ai-worker/worker.js voiceCharacterAllowance() (15k / 20k characters ≈ 250 per answer).
        static let monthlySpokenAnswers = 60
        static let yearlySpokenAnswers = 80
    }
    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    init(settings: GhafSettings, showsClose: Bool = true, allowsHeroMotion: Bool = true) {
        self.settings = settings
        self.showsClose = showsClose
        self.allowsHeroMotion = allowsHeroMotion
        _heroAppeared = State(initialValue: !allowsHeroMotion)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(theme.accent)
                    // Owner 1.31: the headline is a subscribe call to action.
                    Text(ar ? "اشترك في غاف Pro" : "Subscribe to Ghaf Pro").font(GhafTypography.display(30, languageCode: lang))
                        .multilineTextAlignment(.center)
                    Text(ar ? "اشترك لتستمتع بغاف AI والإدخال الصوتي والإحصائيات المتقدمة وكل الودجات."
                            : "Subscribe to enjoy Ghaf AI, voice entry, advanced statistics and every widget.")
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .modifier(GhafProHeroEntrance(isActive: allowsHeroMotion && !reduceMotion, isVisible: heroAppeared))
                .onAppear {
                    guard !heroAppeared else { return }
                    guard allowsHeroMotion && !reduceMotion else {
                        heroAppeared = true
                        return
                    }
                    withAnimation(.spring(duration: 0.58, bounce: 0.12).delay(0.05)) {
                        heroAppeared = true
                    }
                }
                if offerHighlight {
                    VStack(spacing: 10) {
                        Label(ar ? "هدية قبل الرحيل" : "A gift before you go", systemImage: "gift.fill")
                            .font(GhafTypography.heading(18, languageCode: lang)).foregroundStyle(theme.primaryText)
                        Text(ar ? "خصم ٢٥٪ لمرة واحدة على Ghaf Pro" : "One-time 25% off Ghaf Pro")
                            .font(GhafTypography.body(15, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        Button(ar ? "استرداد العرض" : "Claim offer") { redeeming = true }
                            .ghafProminentButton(theme: theme, languageCode: lang)
                            .disabled(!GhafFeatureFlags.appStoreAccount)
                            .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
                        Text(ar ? "يتوفر عند إطلاق غاف في App Store." : "Available when Ghaf is on the App Store.")
                            .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16).frame(maxWidth: .infinity).ghafCard(theme: theme)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label(ar ? "تقارير المتاجر والحسابات" : "Merchant and account reports", systemImage: "chart.bar")
                    Label(ar ? "ودجات للشاشة الرئيسية وشاشة القفل" : "Home and Lock Screen widgets", systemImage: "square.grid.2x2")
                    Label(ar ? "متابعة العمليات بالأنشطة المباشرة" : "Transaction updates with Live Activities", systemImage: "bolt")
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                VStack(spacing: 8) {
                    planRow(annual: false)
                    planRow(annual: true)
                }
                purchaseControls
                // Apple 3.1.2: renewal terms on the paywall itself, next to the price.
                VStack(spacing: 1) {
                    Text(ar ? "يتجدد تلقائيًا بالسعر نفسه؛ ألغِ قبل نهاية الفترة بـ٢٤ ساعة على الأقل." : "Auto-renews at the same price; cancel at least 24 hours before the period ends.")
                    Text(ar ? "يمكنك الإلغاء في أي وقت من إعدادات حساب Apple." : "Cancel anytime in your Apple Account settings.")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .font(.system(size: 10)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
                HStack {
                    // Shown in every build; inactive until the App Store account exists.
                    Button(ar ? "استرداد رمز" : "Redeem code") { redeeming = true }
                        .disabled(!GhafFeatureFlags.appStoreAccount)
                        .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
                    NavigationLink(ar ? "الشروط" : "Terms") { GhafTermsView(settings: settings) }
                    NavigationLink(ar ? "الخصوصية" : "Privacy") { GhafPrivacyPolicyView(settings: settings) }
                }.font(.footnote)
            }
            .foregroundStyle(theme.primaryText)
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ghafBackground(theme: theme)
        .offerCodeRedemption(isPresented: $redeeming)
        .onDisappear { offerHighlight = false }
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(ar ? "إغلاق" : "Close")
                }
            }
        }
        .task {
            guard GhafFeatureFlags.appStoreAccount else { return }
            await refreshEntitlements()
            await loadProducts()
        }
        .task {
            guard GhafFeatureFlags.appStoreAccount else { return }
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update,
                      [monthlyID, yearlyID].contains(transaction.productID) else { continue }
                await refreshEntitlements()
                await transaction.finish()
            }
        }
        .sensoryFeedback(.selection, trigger: yearly)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var availability: String {
        ar ? "قريباً على App Store" : "Coming soon to the App Store"
    }

    private func allowance(annual: Bool) -> String {
        let count = annual ? VoiceAllowance.yearlySpokenAnswers : VoiceAllowance.monthlySpokenAnswers
        let localizedCount = count.formatted(.number.locale(Locale(identifier: lang)))
        return ar ? "نحو \(localizedCount) إجابة صوتية شهريًا" : "About \(count) spoken answers a month"
    }

    @ViewBuilder private var purchaseControls: some View {
        let selected = products.first { $0.id == (yearly ? yearlyID : monthlyID) }
        let active = GhafProAccess.hasAccess
        Button {
            busy = true
            Task {
                defer { busy = false }
                guard let selected else { await loadProducts(); return }
                do {
                    switch try await selected.purchase() {
                    case .success(.verified(let transaction)):
                        await refreshEntitlements()
                        await transaction.finish()
                    case .pending: notice = ar ? "بانتظار الموافقة" : "Awaiting approval"
                    case .userCancelled: break
                    default: notice = ar ? "تعذّر التحقق من الشراء" : "Could not verify the purchase"
                    }
                } catch { notice = error.localizedDescription }
            }
        } label: {
            Text(GhafProAccess.hasAccessCode ? (ar ? "Pro فعّال (رمز)" : "Pro active (code)") : !GhafFeatureFlags.appStoreAccount ? availability : active ? (ar ? "اشتراكك فعّال" : "Pro is active") : selected == nil ? (ar ? "تحديث الأسعار" : "Reload prices") : (ar ? "اشتراك" : "Subscribe"))
        }.ghafProminentButton(theme: theme, languageCode: ar ? "ar" : "en")
            .ghafLightSweep(GhafFeatureFlags.appStoreAccount && !active && !busy)
            .disabled(!GhafFeatureFlags.appStoreAccount || active || busy || selected == nil || isLoadingProducts)
        accessCodeControls
        do {
            Button(ar ? "استعادة المشتريات" : "Restore purchases") {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await AppStore.sync()
                        await refreshEntitlements()
                        notice = GhafProAccess.hasAccess ? nil : (ar ? "لا يوجد اشتراك فعّال" : "No active subscription found")
                    } catch { notice = error.localizedDescription }
                }
            }
            .disabled(busy || !GhafFeatureFlags.appStoreAccount)
            .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
        }
        if let notice { Text(notice).font(.footnote) }
    }

    private func loadProducts() async {
        isLoadingProducts = true
        productLoadFailed = false
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [monthlyID, yearlyID])
            if products.isEmpty {
                productLoadFailed = true
                notice = ar ? "الأسعار غير متاحة" : "Prices are unavailable"
                introOfferEligibility = [:]
                return
            }
            var eligibility: [String: Bool] = [:]
            for product in products {
                guard let subscription = product.subscription, subscription.introductoryOffer != nil else { continue }
                eligibility[product.id] = await subscription.isEligibleForIntroOffer
            }
            introOfferEligibility = eligibility
            notice = nil
        } catch {
            products = []
            introOfferEligibility = [:]
            productLoadFailed = true
            notice = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        _ = await GhafAITier.refreshVerifiedEntitlement()
        accessRevision += 1
    }

    @ViewBuilder private var accessCodeControls: some View {
        if GhafProAccess.hasAccessCode {
            HStack {
                Text(ar ? "Pro فعّال (رمز)" : "Pro active (code)")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .medium)).foregroundStyle(theme.accent)
                Spacer()
                Button(ar ? "إزالة الرمز" : "Remove code") {
                    GhafProAccess.removeAccessCode()
                    accessRevision += 1
                    notice = nil
                }
                .font(GhafTypography.body(13, languageCode: lang, weight: .medium)).foregroundStyle(theme.secondaryText)
            }
            .id(accessRevision)
        } else if codeEntryVisible {
            VStack(spacing: 10) {
                TextField(ar ? "أدخل الرمز" : "Enter your code", text: $accessCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(GhafTypography.body(16, languageCode: lang))
                    .padding(14)
                    .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline, lineWidth: 1))
                    .accessibilityIdentifier("ghaf.pro.access-code")
                Button {
                    let code = accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty, !redeemingAccessCode else { return }
                    redeemingAccessCode = true
                    Task {
                        defer { redeemingAccessCode = false }
                        switch await GhafCloudAI.redeemAccessCode(code) {
                        case .success:
                            GhafProAccess.saveAccessCode(code)
                            accessCode = ""
                            codeEntryVisible = false
                            accessRevision += 1
                            notice = ar ? "تم تفعيل Pro باستخدام الرمز" : "Pro active (code)"
                        case .invalid:
                            notice = ar ? "الرمز غير صالح أو انتهت محاولات اليوم" : "That code is invalid, or today's attempts are used"
                        case .unavailable:
                            notice = ar ? "تعذّر الاتصال. حاول مرة أخرى." : "Couldn't connect. Try again."
                        }
                    }
                } label: {
                    Text(redeemingAccessCode ? (ar ? "جارٍ التحقق…" : "Checking…") : (ar ? "تفعيل الرمز" : "Activate code"))
                        .frame(maxWidth: .infinity)
                }
                .ghafProminentButton(theme: theme, languageCode: lang)
                .disabled(redeemingAccessCode || accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            Button(ar ? "لديك رمز؟" : "Have a code?") { codeEntryVisible = true }
                .font(GhafTypography.body(14, languageCode: lang, weight: .medium))
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("ghaf.pro.have-code")
        }
    }

    private func planRow(annual: Bool) -> some View {
        let product = products.first(where: { $0.id == (annual ? yearlyID : monthlyID) })
        let offer = product?.subscription?.introductoryOffer
        return Button { yearly = annual } label: {
            HStack(spacing: 12) {
                Image(systemName: yearly == annual ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(yearly == annual ? theme.accent : theme.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(annual ? (ar ? "الكاملة" : "Complete") : (ar ? "الأساسية" : "Essentials"))
                        .font(GhafTypography.heading(16, languageCode: lang))
                    Text(annual ? (ar ? "سنوي" : "Yearly") : (ar ? "شهري" : "Monthly"))
                        .font(GhafTypography.body(10, languageCode: lang, weight: .medium)).foregroundStyle(theme.secondaryText)
                    Text(allowance(annual: annual))
                        .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    if let product, let offer, introOfferEligibility[product.id] == true {
                        Text(trialText(offer.period))
                            .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(theme.accent)
                    }
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 3) {
                    if let product { Text(product.displayPrice) }
                    else if isLoadingProducts || (!productLoadFailed && GhafFeatureFlags.appStoreAccount) { ProgressView().controlSize(.small) }
                    else { Text(ar ? "غير متاح" : "Unavailable").foregroundStyle(theme.secondaryText) }
                }
                .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 96)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(yearly == annual ? theme.accent : theme.outline, lineWidth: yearly == annual ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if annual {
                    Text(ar ? "أفضل قيمة" : "Best value")
                        .font(GhafTypography.body(9, languageCode: lang, weight: .bold))
                        .foregroundStyle(theme.accentContrast)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.accent, in: Capsule())
                        .padding(.top, 8).padding(.trailing, 12)
                }
            }
        }.buttonStyle(.plain).accessibilityAddTraits(yearly == annual ? .isSelected : [])
    }

    private func trialText(_ period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        let localizedCount = count.formatted(.number.locale(Locale(identifier: lang)))
        let unit: (String, String)
        switch period.unit {
        case .day: unit = ("day", count == 1 ? "يوم واحد" : count == 2 ? "يومين" : "أيام")
        case .week: unit = ("week", count == 1 ? "أسبوع واحد" : count == 2 ? "أسبوعين" : "أسابيع")
        case .month: unit = ("month", count == 1 ? "شهر واحد" : count == 2 ? "شهرين" : "أشهر")
        case .year: unit = ("year", count == 1 ? "سنة واحدة" : count == 2 ? "سنتين" : "سنوات")
        @unknown default: unit = ("period", "فترة")
        }
        return ar ? "تجربة مجانية لمدة \(localizedCount) \(unit.1)" : "\(count)-\(unit.0) free trial"
    }
}

/// Why Ghaf asks for money, in the voice of the person who makes it. Shown on the Pro page.
enum GhafWhyPaidView {
    static func message(ar: Bool) -> String {
        ar ? "أريد أن تكون تجربة غاف هادئة وسلسة للجميع. لن تظهر فيه إعلانات أبداً. يساعد Ghaf Pro على إبقاء غاف مستقلاً ودعم تطويره. وسيظل الإصدار المجاني مفيداً."
           : "I want Ghaf to feel calm and easy for everyone. There will never be ads. Ghaf Pro keeps Ghaf independent and supports its development. The free version will remain useful."
    }
}

/// Subscription terms, written to protect the developer while staying true to how the App Store works.
struct GhafTermsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ar ? "شروط اشتراك غاف Pro" : "Ghaf Pro terms")
                    .font(GhafTypography.display(28, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity)
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). \(section.0)")
                            .font(GhafTypography.heading(16, languageCode: lang))
                            .foregroundStyle(theme.primaryText)
                        Text(section.1)
                            .font(GhafTypography.body(14, languageCode: lang))
                            .foregroundStyle(theme.secondaryText)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ghafStatsCard(theme: theme, radius: 18)
                }
                Text(ar ? "آخر تحديث: نوفمبر ٢٠٢٦" : "Last updated: November 2026")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .ghafScreenPadding().padding(.vertical, 16)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .ghafPageTitle(ar ? "الشروط" : "Terms", languageCode: lang, theme: theme)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private var sections: [(String, String)] {
        ar ? [
            ("الخطط", "يتوفر غاف Pro باشتراك شهري أو سنوي يتجدد تلقائياً."),
            ("الدفع والتجديد", "يتم الدفع عبر حساب Apple الخاص بك عند تأكيد الشراء. يتجدد الاشتراك تلقائياً بنفس السعر ما لم يُوقف التجديد قبل نهاية الفترة الحالية بـ ٢٤ ساعة على الأقل. يمكنك إدارة الاشتراك وإلغاؤه من الإعدادات › حساب Apple › الاشتراكات. الإلغاء يوقف التجديد القادم فقط، ويبقى Pro فعّالاً حتى نهاية الفترة المدفوعة."),
            ("لا استرداد ولا إرجاع", "كل المبيعات نهائية. لا يقدّم غاف أي استرداد أو إرجاع أو تعويض بعد الشراء، بما في ذلك الفترات الجزئية أو الوقت غير المستخدم أو المزايا التي لم تُستخدم. المدفوعات تتم عبر Apple، وأي طلب استرداد يُقدّم إلى Apple وحدها وتقرّر فيه وفق سياساتها، وغاف لا يستطيع إصدار استرداد بنفسه."),
            ("المزايا", "قد تُضاف مزايا Pro أو تُعدّل أو تُحسّن مع الوقت. لا يضمن الاشتراك توفر ميزة بعينها في كل جهاز أو إصدار من iOS."),
            ("ليس نصيحة مالية", "غاف أداة لتنظيم سجلك المالي الشخصي. الأرقام من سجلاتك ومن رسائل البنك وقد تحتوي على أخطاء. غاف ليس بنكاً ولا مستشاراً مالياً، ولا يُعدّ أي محتوى فيه نصيحة مالية أو استثمارية. أنت المسؤول عن قراراتك المالية."),
            ("حدود المسؤولية", "يُقدَّم غاف كما هو. إلى أقصى حد يسمح به القانون، لا يتحمل المطوّر أي مسؤولية عن خسائر أو أضرار مباشرة أو غير مباشرة ناتجة عن استخدام التطبيق أو تعذّر استخدامه، ولا تتجاوز مسؤوليته في كل الأحوال المبلغ الذي دفعته خلال الأشهر الاثني عشر السابقة."),
            ("التعديل والقانون", "قد تُحدَّث هذه الشروط، ويعني استمرار الاستخدام قبولها. تخضع هذه الشروط لقوانين دولة الإمارات العربية المتحدة، مع شروط Apple القياسية لاستخدام التطبيقات (EULA).")
        ] : [
            ("Plans", "Monthly and yearly subscriptions renew automatically."),
            ("Payment and renewal", "Payment is charged to your Apple Account when you confirm the purchase. Subscriptions renew automatically at the same price unless auto-renew is turned off at least 24 hours before the current period ends. Manage or cancel in Settings › Apple Account › Subscriptions. Cancelling stops the next renewal only; Pro stays active until the end of the paid period."),
            ("No refunds or returns", "All sales are final. Ghaf provides no refunds, returns or credits after purchase, including for partial periods, unused time or unused features. Payments are processed by Apple; any refund request can only be made to Apple, which decides it under its own policies. Ghaf cannot issue refunds itself."),
            ("Features", "Pro features may be added, changed or improved over time. A subscription does not guarantee that a specific feature is available on every device or iOS version."),
            ("Not financial advice", "Ghaf is a tool for organising your personal records. Figures come from your records and bank messages and may contain errors. Ghaf is not a bank or a financial adviser, and nothing in it is financial or investment advice. You are responsible for your financial decisions."),
            ("Limitation of liability", "Ghaf is provided as is. To the fullest extent the law allows, the developer is not liable for any direct or indirect loss or damage arising from using, or being unable to use, the app, and in any case liability is limited to the amount you paid in the previous twelve months."),
            ("Changes and law", "These terms may be updated; continued use means you accept them. They are governed by the laws of the United Arab Emirates, together with Apple's standard Licensed Application End User License Agreement (EULA).")
        ]
    }
}

extension View {
    func ghafProSheet(isPresented: Binding<Bool>, settings: GhafSettings) -> some View {
        sheet(isPresented: isPresented) { GhafProSheet(settings: settings) }
    }
}

struct GhafProSheet: View {
    let settings: GhafSettings
    init(settings: GhafSettings, feature: (en: String, ar: String)? = nil) {
        self.settings = settings
    }

    var body: some View {
        NavigationStack { GhafProView(settings: settings) }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .ghafDirection(settings.languageCode)
    }
}
