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
                            Label(ar ? "ميزة من غاف برو" : "Pro feature", systemImage: "lock.fill")
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
        GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true)
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
                VStack(spacing: 12) {
                    GhafAIOrb(theme: theme, mood: yearly ? .thinking : .idle)
                        .frame(width: 112, height: 112)
                        .scaleEffect(yearly ? 1 : 0.94)
                        .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.12), value: yearly)
                    // Owner 1.31: the headline is a subscribe call to action.
                    Text(ar ? "اشترك في غاف برو" : "Subscribe to Ghaf Pro").font(GhafTypography.display(30, languageCode: lang))
                        .multilineTextAlignment(.center)
                    Text(ar ? "اشترك لتستمتع بغاف AI والإدخال الصوتي والإحصائيات المتقدمة وكل الودجات."
                            : "Subscribe to enjoy Ghaf AI, voice entry, advanced statistics and every widget.")
                        .foregroundStyle(.white.opacity(0.72))
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
                            .font(GhafTypography.heading(18, languageCode: lang)).foregroundStyle(.white)
                        Text(ar ? "خصم 25٪ لمرة واحدة على غاف برو" : "One-time 25% off Ghaf Pro")
                            .font(GhafTypography.body(15, languageCode: lang)).foregroundStyle(.white.opacity(0.72))
                        Button(ar ? "استرداد العرض" : "Claim offer") { redeeming = true }
                            .ghafProminentButton(theme: theme, languageCode: lang)
                            .disabled(!GhafFeatureFlags.appStoreAccount)
                            .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
                        Text(ar ? "يتوفر عند إطلاق غاف في متجر التطبيقات." : "Available when Ghaf is on the App Store.")
                            .font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                    }
                    .padding(16).frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label(ar ? "تقارير المتاجر والحسابات" : "Merchant and account reports", systemImage: "chart.bar")
                    Label(ar ? "ودجات للشاشة الرئيسية وشاشة القفل" : "Home and Lock Screen widgets", systemImage: "square.grid.2x2")
                    Label(ar ? "متابعة العمليات بالأنشطة المباشرة" : "Transaction updates with Live Activities", systemImage: "bolt")
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                GeometryReader { geometry in
                    let cardWidth = min(350, max(270, geometry.size.width - 48))
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            planRow(annual: true, width: cardWidth)
                            planRow(annual: false, width: cardWidth)
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 24)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("ghaf.pro.plan.carousel")
                }
                .frame(height: 190)
                purchaseControls
                HStack {
                    // Shown in every build; inactive until the App Store account exists.
                    Button(ar ? "استرداد رمز" : "Redeem code") { redeeming = true }
                        .disabled(!GhafFeatureFlags.appStoreAccount)
                        .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
                    NavigationLink(ar ? "الشروط" : "Terms") { GhafTermsView(settings: settings) }
                    NavigationLink(ar ? "الخصوصية" : "Privacy") { GhafPrivacyPolicyView(settings: settings) }
                }.font(.footnote)
            }
            .foregroundStyle(.white)
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(immersiveBackground)
        .preferredColorScheme(.dark)
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
            if GhafFeatureFlags.appStoreAccount { await refreshEntitlements() }
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

    private var immersiveBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(red: 0.018, green: 0.021, blue: 0.029)
                Circle().fill(theme.accent.opacity(0.32))
                    .frame(width: geometry.size.width * 0.86, height: geometry.size.width * 0.86)
                    .blur(radius: 100)
                    .offset(x: -geometry.size.width * 0.28, y: -geometry.size.width * 0.34)
                Circle().fill(Color(red: 0.18, green: 0.30, blue: 0.48).opacity(0.18))
                    .frame(width: geometry.size.width * 0.74, height: geometry.size.width * 0.74)
                    .blur(radius: 96)
                    .offset(x: geometry.size.width * 0.38, y: geometry.size.width * 0.05)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func allowance(annual: Bool) -> String {
        let count = annual ? VoiceAllowance.yearlySpokenAnswers : VoiceAllowance.monthlySpokenAnswers
        let localizedCount = count.formatted(.number.locale(GhafLocalization.locale(languageCode: lang)))
        return ar ? "نحو \(localizedCount) إجابة صوتية شهريًا" : "About \(count) spoken answers a month"
    }

    @ViewBuilder private var purchaseControls: some View {
        let selected = products.first { $0.id == (yearly ? yearlyID : monthlyID) }
        let active = GhafProAccess.hasAccess
        let canStartTrial = selected?.subscription?.introductoryOffer != nil
            && introOfferEligibility[selected?.id ?? ""] == true
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
            Text(GhafProAccess.hasAccessCode ? (ar ? "غاف برو فعّال (رمز)" : "Pro active (code)") : active ? (ar ? "اشتراك غاف برو فعّال" : "Pro is active") : selected == nil ? (ar ? "الأسعار غير متاحة" : "Prices unavailable") : canStartTrial ? (ar ? "ابدأ التجربة المجانية" : "Start free trial") : (ar ? "اشترك" : "Subscribe"))
        }.ghafProminentButton(theme: theme, languageCode: ar ? "ar" : "en")
            .ghafLightSweep(!active && !busy && canStartTrial)
            .disabled(!GhafFeatureFlags.appStoreAccount || active || busy || selected == nil || isLoadingProducts)
        Text(ar
             ? (yearly ? "بعدها 99 د.إ سنويًا. ألغِ قبل 24 ساعة." : "بعدها 10 د.إ شهريًا. ألغِ قبل 24 ساعة.")
             : (yearly ? "Then AED 99 a year. Cancel 24 hours before." : "Then AED 10 a month. Cancel 24 hours before."))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
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
                Text(ar ? "غاف برو فعّال (رمز)" : "Pro active (code)")
            .font(GhafTypography.body(13, languageCode: lang, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Button(ar ? "إزالة الرمز" : "Remove code") {
                    GhafProAccess.removeAccessCode()
                    accessRevision += 1
                    notice = nil
                }
                .font(GhafTypography.body(13, languageCode: lang, weight: .medium)).foregroundStyle(.white.opacity(0.68))
            }
            .id(accessRevision)
        } else if codeEntryVisible {
            VStack(spacing: 10) {
                TextField(ar ? "أدخل الرمز" : "Enter your code", text: $accessCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(GhafTypography.body(16, languageCode: lang))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16), lineWidth: 1))
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
                            notice = ar ? "تم تفعيل غاف برو باستخدام الرمز" : "Pro active (code)"
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

    private func planRow(annual: Bool, width: CGFloat) -> some View {
        let product = products.first(where: { $0.id == (annual ? yearlyID : monthlyID) })
        let offer = product?.subscription?.introductoryOffer
        return Button { yearly = annual } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(annual ? (ar ? "سنوي" : "Yearly") : (ar ? "شهري" : "Monthly"),
                          systemImage: yearly == annual ? "checkmark.circle.fill" : "circle")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(yearly == annual ? theme.accent : .white.opacity(0.72))
                    Spacer()
                    if annual {
                        Text(ar ? "أفضل قيمة" : "Best value")
                            .font(GhafTypography.body(10, languageCode: lang, weight: .bold))
                            .foregroundStyle(.black.opacity(0.82))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.white.opacity(0.88), in: Capsule())
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(annual ? (ar ? "الكاملة" : "Complete") : (ar ? "الأساسية" : "Essentials"))
                            .font(GhafTypography.heading(18, languageCode: lang))
                        Text(allowance(annual: annual))
                            .font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                        if let product, let offer, introOfferEligibility[product.id] == true {
                            Text(trialText(offer.period))
                                .font(GhafTypography.body(11, languageCode: lang, weight: .semibold)).foregroundStyle(theme.accent)
                                .accessibilityIdentifier("ghaf.pro.trial.\(annual ? "yearly" : "monthly")")
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        if let product {
                            priceLabel(product, annual: annual)
                        }
                        else if isLoadingProducts || !productLoadFailed { ProgressView().tint(.white).controlSize(.small) }
                        else { Text(ar ? "غير متاح" : "Unavailable").foregroundStyle(.white.opacity(0.55)) }
                    }
                    .font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 22)
            .frame(width: width, height: 164, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(yearly == annual ? theme.accent.opacity(0.85) : .white.opacity(0.16), lineWidth: yearly == annual ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(yearly == annual ? .isSelected : [])
    }

    private func priceLabel(_ product: Product, annual: Bool) -> some View {
        let currency = product.priceFormatStyle.currencyCode
        let amount = GhafMoneyLabel.formatter(languageCode: lang, currency: currency).string(from: product.price as NSDecimalNumber)
            ?? NSDecimalNumber(decimal: product.price).stringValue
        return HStack(spacing: 4) {
            GhafCurrencyIcon(currency: currency, size: 15)
            Text(amount).font(GhafTypography.number(15, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currency) \(amount)")
        .accessibilityIdentifier("ghaf.pro.price.\(annual ? "yearly" : "monthly")")
    }

    private func trialText(_ period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        let localizedCount = count.formatted(.number.locale(GhafLocalization.locale(languageCode: lang)))
        let unit: (String, String)
        switch period.unit {
        case .day: unit = ("day", count == 1 ? "يوم واحد" : count == 2 ? "يومين" : "أيام")
        case .week: unit = ("week", count == 1 ? "أسبوع واحد" : count == 2 ? "أسبوعين" : "أسابيع")
        case .month: unit = ("month", count == 1 ? "شهر واحد" : count == 2 ? "شهرين" : "أشهر")
        case .year: unit = ("year", count == 1 ? "سنة واحدة" : count == 2 ? "سنتين" : "سنوات")
        @unknown default: unit = ("period", "فترة")
        }
        // Arabic says "one day" / "two days" with the word alone; 3+ takes the number.
        return ar ? "تجربة مجانية لمدة \(count <= 2 ? unit.1 : "\(localizedCount) \(unit.1)")" : "\(count)-\(unit.0) free trial"
    }
}

/// Why Ghaf asks for money, in the voice of the person who makes it. Shown on the Pro page.
enum GhafWhyPaidView {
    static func message(ar: Bool) -> String {
        ar ? "أريد أن تكون تجربة غاف هادئة وسلسة للجميع. لن تظهر فيها إعلانات أبداً. يساعد غاف برو على إبقاء غاف مستقلاً ودعم تطويره. وسيظل الإصدار المجاني مفيداً."
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
                Text(ar ? "شروط اشتراك غاف برو" : "Ghaf Pro terms")
                    .font(GhafTypography.body(24, languageCode: lang, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity)
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("\(index + 1).\u{00a0}").font(.system(size: 16, weight: .bold))
                            Text(section.0).font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        }.foregroundStyle(theme.primaryText)
                        // `leading` resolves to the visual right in Arabic RTL.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        legalParagraph(section.1)
                            .foregroundStyle(theme.secondaryText)
                            .lineSpacing(3)
                            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ghafStatsCard(theme: theme, radius: 18)
                }
                Group {
                    if ar { HStack { Text("آخر تحديث: نوفمبر"); Text("2026").font(.system(size: 12)); }.font(GhafTypography.body(12, languageCode: lang)) }
                    else { Text("Last updated: November 2026").font(GhafTypography.body(12, languageCode: lang)) }
                }
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
            ("الخطط", "يتوفر غاف برو باشتراك شهري أو سنوي يتجدد تلقائياً."),
            ("الدفع والتجديد", "يتم الدفع عبر حساب آبل عند تأكيد الشراء. يتجدد الاشتراك تلقائياً بالسعر نفسه ما لم يُوقف التجديد قبل نهاية الفترة الحالية بـ 24 ساعة على الأقل. يمكنك إدارة الاشتراك أو إلغاؤه من الإعدادات › حساب آبل › الاشتراكات. يوقف الإلغاء التجديد القادم فقط، ويبقى غاف برو فعّالاً حتى نهاية الفترة المدفوعة."),
            ("لا استرداد ولا إرجاع", "كل المبيعات نهائية. لا يقدّم غاف أي استرداد أو إرجاع أو تعويض بعد الشراء، بما في ذلك الفترات الجزئية أو الوقت غير المستخدم أو المزايا التي لم تُستخدم. تتم المدفوعات عبر آبل، ويُقدّم طلب الاسترداد إلى آبل وحدها لتقرّر فيه وفق سياساتها. لا يستطيع غاف إصدار الاسترداد بنفسه."),
            ("المزايا", "قد تُضاف مزايا غاف برو أو تُعدّل أو تُحسّن مع الوقت. لا يضمن الاشتراك توفر ميزة بعينها على كل جهاز أو إصدار من iOS."),
            ("إخلاء مسؤولية مالية", "غاف أداة لتنظيم سجلك المالي الشخصي. تستند الأرقام إلى سجلاتك ورسائل البنك، وقد تحتوي على أخطاء. غاف ليس بنكاً ولا مستشاراً مالياً، ولا يُعدّ أي محتوى فيه نصيحة مالية أو استثمارية. أنت مسؤول عن قراراتك المالية."),
            ("حدود المسؤولية", "يُقدَّم غاف كما هو. إلى أقصى حد يسمح به القانون، لا يتحمل المطوّر مسؤولية الخسائر أو الأضرار المباشرة أو غير المباشرة الناتجة عن استخدام التطبيق أو تعذّر استخدامه. وفي جميع الأحوال، لا تتجاوز مسؤوليته المبلغ الذي دفعته خلال الأشهر الاثني عشر السابقة."),
            ("التعديل والقانون", "قد تُحدَّث هذه الشروط، ويعني استمرار الاستخدام قبولها. تخضع هذه الشروط لقوانين دولة الإمارات العربية المتحدة، إلى جانب اتفاقية ترخيص التطبيقات القياسية من آبل (EULA).")
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

    private func legalParagraph(_ value: String) -> Text {
        enum Script { case arabic, latin, number }
        func script(_ character: Character) -> Script? {
            guard let scalar = character.unicodeScalars.first else { return nil }
            if CharacterSet.decimalDigits.contains(scalar) { return .number }
            if (0x0600...0x06FF).contains(scalar.value) || (0x0750...0x077F).contains(scalar.value) || (0x08A0...0x08FF).contains(scalar.value) { return .arabic }
            if (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value) { return .latin }
            return nil
        }
        func font(_ script: Script) -> Font {
            switch script {
            case .arabic: GhafTypography.body(14, languageCode: "ar")
            case .latin: .custom("IBMPlexSans-Regular", size: 14)
            case .number: .system(size: 14)
            }
        }
        var runs: [(Script, String)] = []
        var current: Script = ar ? .arabic : .latin
        var text = ""
        for character in value {
            if let next = script(character), next != current, !text.isEmpty {
                runs.append((current, text)); text = ""; current = next
            }
            text.append(character)
        }
        if !text.isEmpty { runs.append((current, text)) }
        return runs.reduce(Text("")) { $0 + Text($1.1).font(font($1.0)) }
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
