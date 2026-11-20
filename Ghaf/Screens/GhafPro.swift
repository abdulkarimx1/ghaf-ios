import SwiftUI
import StoreKit

struct GhafProView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    var showsClose = true

    @State private var yearly = true
    private let monthlyID = "com.ghaf.app.pro.monthly"
    private let yearlyID = "com.ghaf.app.pro.yearly"
    @State private var products: [Product] = []
    @State private var entitled = false
    @State private var busy = false
    @State private var redeeming = false
    @State private var notice: String?
    private var testUnlocked: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked")
        #else
        false
        #endif
    }

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "leaf.fill").font(.largeTitle).foregroundStyle(theme.accent)
                Text("Ghaf Pro").font(GhafTypography.display(30, languageCode: lang))
                Text(ar ? "تابع إنفاقك بتفاصيل أكثر" : "See where your money goes.")
                    .foregroundStyle(theme.secondaryText)
                VStack(alignment: .leading, spacing: 16) {
                    Label(ar ? "تقارير الإنفاق حسب المتجر والحساب" : "Spending reports by merchant and account", systemImage: "chart.bar")
                    Label(ar ? "ودجات للشاشة الرئيسية وشاشة القفل" : "Home and Lock Screen widgets", systemImage: "square.grid.2x2")
                    Label(ar ? "متابعة العمليات بالأنشطة المباشرة" : "Transaction updates with Live Activities", systemImage: "bolt")
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                VStack(spacing: 8) {
                    planRow(annual: false)
                    planRow(annual: true)
                }
                purchaseControls
                HStack {
                    // Shown in every build; inactive until the App Store account exists.
                    Button(ar ? "استرداد رمز" : "Redeem code") { redeeming = true }
                        .offerCodeRedemption(isPresented: $redeeming)
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

    @ViewBuilder private var purchaseControls: some View {
        let selected = products.first { $0.id == (yearly ? yearlyID : monthlyID) }
        let active = entitled || testUnlocked
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
            Text(testUnlocked ? (ar ? "اشتراك تجريبي فعّال" : "Pro is active (debug)") : !GhafFeatureFlags.appStoreAccount ? availability : active ? (ar ? "اشتراكك فعّال" : "Pro is active") : selected == nil ? (ar ? "تحديث الأسعار" : "Reload prices") : (ar ? "اشتراك" : "Subscribe"))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(theme.accentContrast)
                .background(theme.accent, in: Capsule())
        }.disabled(!GhafFeatureFlags.appStoreAccount || active || busy)
        do {
            Button(ar ? "استعادة المشتريات" : "Restore purchases") {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await AppStore.sync()
                        await refreshEntitlements()
                        notice = entitled ? nil : (ar ? "لا يوجد اشتراك فعّال" : "No active subscription found")
                    } catch { notice = error.localizedDescription }
                }
            }
            .disabled(busy || !GhafFeatureFlags.appStoreAccount)
            .opacity(GhafFeatureFlags.appStoreAccount ? 1 : 0.4)
        }
        if let notice { Text(notice).font(.footnote) }
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: [monthlyID, yearlyID])
            notice = products.isEmpty ? (ar ? "الأسعار غير متاحة" : "Prices are unavailable") : nil
        } catch { notice = error.localizedDescription }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               [monthlyID, yearlyID].contains(transaction.productID),
               transaction.revocationDate == nil, !transaction.isUpgraded {
                active = true
            }
        }
        entitled = active
    }

    private func planRow(annual: Bool) -> some View {
        Button { yearly = annual } label: {
            HStack {
                Image(systemName: yearly == annual ? "checkmark.circle.fill" : "circle")
                Text(annual ? (ar ? "سنوي" : "Yearly") : (ar ? "شهري" : "Monthly"))
                if annual { Text(ar ? "أفضل قيمة" : "Best value").font(.caption) }
                Spacer()
                if let product = products.first(where: { $0.id == (annual ? yearlyID : monthlyID) }) { Text(product.displayPrice) }
                else { Text(annual ? (ar ? "‏79.99 د.إ / سنة" : "AED 79.99 / year") : (ar ? "‏9.99 د.إ / شهر" : "AED 9.99 / month")).foregroundStyle(theme.secondaryText) }
            }.padding(.horizontal).frame(minHeight: 64)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityAddTraits(yearly == annual ? .isSelected : [])
    }
}

/// Why Ghaf asks for money, in the voice of the person who makes it. Shown on the Pro page.
enum GhafWhyPaidView {
    static func message(ar: Bool) -> String {
        ar ? "الإمارات كانت دائماً سنداً لكل من يبني ويبدع. غاف صُنع هنا بيد مطوّر واحد وبنفس هذه الروح، واشتراكك هو طريقتك في رد هذا الحب. كل اشتراك يذهب لتطوير غاف وبناء تطبيقات أجدد وأفضل، وبياناتك لن تكون ثمناً له أبداً: لا إعلانات ولا بيع للبيانات."
           : "The UAE has always stood behind the people who build. Ghaf is made here by one developer in that same spirit, and a plan is your way of passing that love on. Every plan goes into making Ghaf better and building newer apps, and your data will never be the price: no ads, no selling data."
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
