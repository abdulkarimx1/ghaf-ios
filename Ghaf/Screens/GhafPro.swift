import SwiftUI

/// Ghaf Pro: three plans, a 3-day trial on the renewing ones, and the terms. Purchases are not
/// connected yet, so the buy button is shown but disabled; nothing in Ghaf is locked today.
/// shortcut: prices are placeholders; replace with StoreKit `Product.displayPrice` when the products exist.
enum GhafProPlan: String, CaseIterable, Identifiable {
    case monthly, yearly, lifetime
    var id: String { rawValue }

    func title(_ ar: Bool) -> String {
        switch self {
        case .monthly: ar ? "شهري" : "Monthly"
        case .yearly: ar ? "سنوي" : "Yearly"
        case .lifetime: ar ? "مدى الحياة" : "Lifetime"
        }
    }
    var price: String {
        switch self { case .monthly: "AED 9.99"; case .yearly: "AED 79.99"; case .lifetime: "AED 199.99" }
    }
    func cadence(_ ar: Bool) -> String {
        switch self {
        case .monthly: ar ? "شهرياً" : "per month"
        case .yearly: ar ? "سنوياً" : "per year"
        case .lifetime: ar ? "دفعة واحدة · لا تجديد" : "one payment · never renews"
        }
    }
    var renews: Bool { self != .lifetime }
}

struct GhafProView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    var showsClose = true

    @State private var plan: GhafProPlan = .yearly
    @State private var proUnlocked = UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked")
    @State private var restoreMessage: String?

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var features: [(String, String, String)] {
        [("chart.xyaxis.line", ar ? "إحصائيات متقدمة" : "Advanced statistics",
          ar ? "مقارنات أطول، وتقارير لكل متجر وحساب." : "Longer comparisons, reports per merchant and account."),
         ("rectangle.3.group.fill", ar ? "ودجت للشاشة الرئيسية والقفل" : "Home and Lock Screen widgets",
          ar ? "رصيدك وصرف اليوم بنظرة." : "Your balance and today's spending at a glance."),
         ("bolt.badge.clock.fill", ar ? "النشاط المباشر" : "Live Activities",
          ar ? "كل عملية جديدة تظهر على شاشة القفل وفي Dynamic Island." : "Each new purchase on the Lock Screen and in the Dynamic Island."),
         ("waveform", ar ? "صوت غاف AI المتقدم" : "Ghaf AI advanced voice",
          ar ? "محادثة صوتية طبيعية بالعربي والإنجليزي." : "Natural voice conversation in Arabic and English."),
         ("heart.fill", ar ? "ادعم تطبيقاً من الإمارات" : "Support an app built in the UAE",
          ar ? "كل اشتراك يبني غاف وتطبيقات أفضل." : "Every plan builds Ghaf and better apps.")]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Ghaf Pro")
                        .font(GhafTypography.display(30, languageCode: lang))
                        .foregroundStyle(theme.primaryText)
                    Text(ar ? "تقارير أعمق وأدوات إضافية لإدارة أموالك." : "Deeper reports and more tools to manage your money.")
                        .font(GhafTypography.body(14, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Text(ar ? "إحصائيات متقدمة · ودجات · أنشطة مباشرة · صوت غاف AI" : "Advanced stats · widgets · Live Activities · Ghaf AI voice")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    ForEach(GhafProPlan.allCases) { item in planRow(item) }
                }
                .padding(8)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(ar ? "تجربة مجانية ٣ أيام للخطتين المتجدّدتين" : "3-day free trial on renewing plans")
                    .font(GhafTypography.body(13, languageCode: lang, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                if proUnlocked {
                    Label(ar ? "أنت على Pro (تجريبي)" : "You're on Pro (test)", systemImage: "checkmark.circle.fill")
                        .font(GhafTypography.body(16, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.credit)
                        .frame(minHeight: 44)
                    Button(ar ? "إنهاء الاختبار" : "End test") {
                        UserDefaults.standard.set(false, forKey: "ghaf.pro.testUnlocked")
                        proUnlocked = false
                    }
                    .font(GhafTypography.body(15, languageCode: lang, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .frame(minHeight: 44)
                } else {
                    Button {
                        UserDefaults.standard.set(true, forKey: "ghaf.pro.testUnlocked")
                        proUnlocked = true
                        restoreMessage = nil
                    } label: {
                        Text(ar ? "متابعة شراء تجريبي" : "Continue with test purchase")
                            .frame(maxWidth: .infinity)
                    }
                    .ghafProminentButton(theme: theme, languageCode: lang)

                    Button {
                        proUnlocked = UserDefaults.standard.bool(forKey: "ghaf.pro.testUnlocked")
                        restoreMessage = proUnlocked ? (ar ? "تمت استعادة Pro (تجريبي)" : "Pro (test) restored") : (ar ? "لا توجد مشتريات لاستعادتها" : "Nothing to restore")
                    } label: { Text(ar ? "استعادة المشتريات" : "Restore purchases") }
                        .font(GhafTypography.body(15, languageCode: lang, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(minHeight: 44)
                    if let restoreMessage {
                        Text(restoreMessage).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                    }
                }

                Text(ar ? "الأسعار أمثلة فقط. هذا الإصدار لا يتصل بمتجر Apple ولا يأخذ أي دفعة." : "Example prices only. This build does not connect to the App Store or take payment.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .ghafScreenPadding()
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ghafBackground(theme: theme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                        .accessibilityLabel(ar ? "إغلاق" : "Close")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: plan)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func planRow(_ item: GhafProPlan) -> some View {
        let selected = plan == item
        return Button { withAnimation(.snappy) { plan = item } } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? theme.accent : theme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title(ar)).font(GhafTypography.body(15, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text(item.cadence(ar)).font(GhafTypography.body(11, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 4)
                Text(item.price).font(GhafTypography.number(14, weight: .heavy)).foregroundStyle(theme.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            ("الخطط", "يتوفر غاف Pro بثلاث خطط: شهرية وسنوية تتجددان تلقائياً، ومدى الحياة بدفعة واحدة لا تتجدد."),
            ("التجربة المجانية", "الخطتان الشهرية والسنوية تبدآن بتجربة مجانية مدتها ٣ أيام، مرة واحدة لكل حساب Apple. إن لم تُلغِ قبل نهاية التجربة بـ ٢٤ ساعة على الأقل، يبدأ الاشتراك المدفوع تلقائياً. لا توجد تجربة مجانية لخطة مدى الحياة."),
            ("الدفع والتجديد", "يتم الدفع عبر حساب Apple الخاص بك عند تأكيد الشراء. يتجدد الاشتراك تلقائياً بنفس السعر ما لم يُوقف التجديد قبل نهاية الفترة الحالية بـ ٢٤ ساعة على الأقل. يمكنك إدارة الاشتراك وإلغاؤه من الإعدادات › حساب Apple › الاشتراكات. الإلغاء يوقف التجديد القادم فقط، ويبقى Pro فعّالاً حتى نهاية الفترة المدفوعة."),
            ("لا استرداد ولا إرجاع", "كل المبيعات نهائية. لا يقدّم غاف أي استرداد أو إرجاع أو تعويض بعد الشراء، بما في ذلك الفترات الجزئية أو الوقت غير المستخدم أو المزايا التي لم تُستخدم. المدفوعات تتم عبر Apple، وأي طلب استرداد يُقدّم إلى Apple وحدها وتقرّر فيه وفق سياساتها، وغاف لا يستطيع إصدار استرداد بنفسه."),
            ("المزايا", "قد تُضاف مزايا Pro أو تُعدّل أو تُحسّن مع الوقت. لا يضمن الاشتراك توفر ميزة بعينها في كل جهاز أو إصدار من iOS."),
            ("ليس نصيحة مالية", "غاف أداة لتنظيم سجلك المالي الشخصي. الأرقام من سجلاتك ومن رسائل البنك وقد تحتوي على أخطاء. غاف ليس بنكاً ولا مستشاراً مالياً، ولا يُعدّ أي محتوى فيه نصيحة مالية أو استثمارية. أنت المسؤول عن قراراتك المالية."),
            ("حدود المسؤولية", "يُقدَّم غاف كما هو. إلى أقصى حد يسمح به القانون، لا يتحمل المطوّر أي مسؤولية عن خسائر أو أضرار مباشرة أو غير مباشرة ناتجة عن استخدام التطبيق أو تعذّر استخدامه، ولا تتجاوز مسؤوليته في كل الأحوال المبلغ الذي دفعته خلال الأشهر الاثني عشر السابقة."),
            ("التعديل والقانون", "قد تُحدَّث هذه الشروط، ويعني استمرار الاستخدام قبولها. تخضع هذه الشروط لقوانين دولة الإمارات العربية المتحدة، مع شروط Apple القياسية لاستخدام التطبيقات (EULA).")
        ] : [
            ("Plans", "Ghaf Pro comes in three plans: Monthly and Yearly, which renew automatically, and Lifetime, a single payment that never renews."),
            ("Free trial", "Monthly and Yearly start with a 3-day free trial, once per Apple Account. Unless you cancel at least 24 hours before the trial ends, the paid subscription starts automatically. Lifetime has no free trial."),
            ("Payment and renewal", "Payment is charged to your Apple Account when you confirm the purchase. Subscriptions renew automatically at the same price unless auto-renew is turned off at least 24 hours before the current period ends. Manage or cancel in Settings › Apple Account › Subscriptions. Cancelling stops the next renewal only; Pro stays active until the end of the paid period."),
            ("No refunds or returns", "All sales are final. Ghaf provides no refunds, returns or credits after purchase, including for partial periods, unused time or unused features. Payments are processed by Apple; any refund request can only be made to Apple, which decides it under its own policies. Ghaf cannot issue refunds itself."),
            ("Features", "Pro features may be added, changed or improved over time. A subscription does not guarantee that a specific feature is available on every device or iOS version."),
            ("Not financial advice", "Ghaf is a tool for organising your personal records. Figures come from your records and bank messages and may contain errors. Ghaf is not a bank or a financial adviser, and nothing in it is financial or investment advice. You are responsible for your financial decisions."),
            ("Limitation of liability", "Ghaf is provided as is. To the fullest extent the law allows, the developer is not liable for any direct or indirect loss or damage arising from using, or being unable to use, the app, and in any case liability is limited to the amount you paid in the previous twelve months."),
            ("Changes and law", "These terms may be updated; continued use means you accept them. They are governed by the laws of the United Arab Emirates, together with Apple's standard Licensed Application End User License Agreement (EULA).")
        ]
    }
}

/// The bottom sheet shown when a Pro feature is tapped. Purchases are not open yet, so the buy button is
/// disabled and "Skip for now" carries on to the feature, which stays free until then.
struct GhafProSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    let feature: (en: String, ar: String)
    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(ar ? "الترقية إلى Pro" : "Upgrade to Pro")
                    .font(GhafTypography.heading(24, languageCode: lang))
                    .foregroundStyle(theme.primaryText)
                Text(ar ? "تقارير أعمق وودجات وأنشطة مباشرة." : "Deeper reports, widgets, and Live Activities.")
                    .font(GhafTypography.body(15, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                NavigationLink {
                    GhafProView(settings: settings, showsClose: false)
                } label: {
                    Text(ar ? "عرض الخطط" : "See plans")
                        .font(GhafTypography.body(17, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(ar ? "عرض خطط غاف Pro." : "Opens Ghaf Pro plans for \(feature.en).")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

}
