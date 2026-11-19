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
        case .monthly: ar ? "شهرياً · تجربة مجانية ٣ أيام" : "per month · 3-day free trial"
        case .yearly: ar ? "سنوياً · تجربة مجانية ٣ أيام" : "per year · 3-day free trial"
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

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    private var features: [(String, String, String)] {
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
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 36, weight: .bold)).foregroundStyle(theme.accentContrast)
                        .frame(width: 84, height: 84)
                        .background(LinearGradient(colors: [theme.glow, theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: theme.accent.opacity(0.35), radius: 18, y: 8)
                    Text("Ghaf Pro")
                        .font(GhafTypography.display(34, languageCode: lang))
                        .foregroundStyle(theme.primaryText)
                    Text(ar ? "كل ما في غاف اليوم يبقى لك. Pro يضيف المزيد، ويدعم من يبنيه."
                            : "Everything in Ghaf today stays yours. Pro adds more, and supports the person building it.")
                        .font(GhafTypography.body(15, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.0)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 38, height: 38)
                                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.1).font(GhafTypography.body(15, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                                Text(item.2).font(GhafTypography.body(13, languageCode: lang)).foregroundStyle(theme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 11)
                        if index < features.count - 1 { Divider().overlay(theme.outline).padding(.leading, 52) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .ghafCard(theme: theme)

                VStack(spacing: 10) {
                    ForEach(GhafProPlan.allCases) { item in planRow(item) }
                }

                VStack(spacing: 10) {
                    Button {} label: {
                        Text(plan.renews ? (ar ? "ابدأ التجربة المجانية ٣ أيام" : "Start 3-day free trial")
                                         : (ar ? "اشترِ مدى الحياة" : "Buy lifetime"))
                            .frame(maxWidth: .infinity)
                    }
                    .ghafProminentButton(theme: theme, languageCode: lang)
                    .disabled(true)
                    Text(ar ? "الاشتراك متاح قريباً. كل مزايا غاف الحالية مجانية حتى ذلك الحين."
                            : "Subscriptions open soon. Everything in Ghaf stays free until then.")
                        .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                    Button(ar ? "استعادة المشتريات" : "Restore purchases") {}
                        .font(GhafTypography.body(14, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .disabled(true)
                        .frame(minHeight: 44)
                }

                // Why Ghaf is paid, in the developer's own words, where the decision is made.
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.accent)
                    Text(ar ? "لماذا غاف مدفوع؟" : "Why Ghaf is paid")
                        .font(GhafTypography.heading(20, languageCode: lang)).foregroundStyle(theme.primaryText)
                    Text(GhafWhyPaidView.message(ar: ar))
                        .font(GhafTypography.body(15, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        .lineSpacing(4)
                    Text(ar ? "— مطوّر غاف" : "— Ghaf's developer")
                        .font(GhafTypography.body(13, languageCode: lang, weight: .semibold)).foregroundStyle(theme.primaryText)
                }
                .multilineTextAlignment(.center)
                .padding(GhafMetrics.cardPadding)
                .frame(maxWidth: .infinity)
                .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: GhafMetrics.cardRadius, style: .continuous))

                Text(plan.renews
                     ? (ar ? "بعد التجربة المجانية لمدة ٣ أيام يُخصم \(plan.price) من حساب Apple الخاص بك \(plan == .monthly ? "كل شهر" : "كل سنة") ويتجدد تلقائياً ما لم تُلغِه قبل نهاية الفترة بـ ٢٤ ساعة على الأقل من إعدادات Apple ID › الاشتراكات. كل المبيعات نهائية، ولا يقدّم غاف أي استرداد أو إرجاع بعد الشراء."
                           : "After the 3-day free trial, \(plan.price) is charged to your Apple Account \(plan == .monthly ? "every month" : "every year") and renews automatically unless cancelled at least 24 hours before the period ends, in Settings › Apple Account › Subscriptions. All sales are final; Ghaf offers no refunds or returns after purchase.")
                     : (ar ? "دفعة واحدة بقيمة \(plan.price) من حساب Apple الخاص بك، بدون تجديد. كل المبيعات نهائية، ولا يقدّم غاف أي استرداد أو إرجاع بعد الشراء."
                           : "One payment of \(plan.price) to your Apple Account, never renewed. All sales are final; Ghaf offers no refunds or returns after purchase."))
                    .font(GhafTypography.body(11, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    NavigationLink { GhafTermsView(settings: settings) } label: { Text(ar ? "شروط الاشتراك" : "Terms of subscription") }
                    NavigationLink { GhafPrivacyPolicyView(settings: settings) } label: { Text(ar ? "سياسة الخصوصية" : "Privacy policy") }
                }
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.accent)
            }
            .ghafScreenPadding()
            .padding(.bottom, 30)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
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
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? theme.accent : theme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.title(ar)).font(GhafTypography.body(17, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                        if item == .yearly {
                            Text(ar ? "وفّر ٣٣٪" : "Save 33%")
                                .font(GhafTypography.body(11, languageCode: lang, weight: .bold))
                                .foregroundStyle(theme.accentContrast)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(theme.accent, in: Capsule())
                        }
                    }
                    Text(item.cadence(ar)).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Text(item.price)
                    .font(GhafTypography.number(17, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(16)
            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 20, style: .continuous), fallback: theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? theme.accent : theme.outline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.ghafPress)
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
                    .ghafCard(theme: theme, radius: 18)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    /// What the user tapped, e.g. "Widgets" ("الودجت").
    let feature: (en: String, ar: String)

    @State private var plan: GhafProPlan = .yearly

    private var lang: String { settings.languageCode }
    private var ar: Bool { lang == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Ghaf Pro")
                        .font(GhafTypography.body(13, languageCode: "en", weight: .heavy))
                        .foregroundStyle(theme.accentContrast)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.accent, in: Capsule())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.primaryText)
                            .frame(width: 44, height: 44).ghafGlassShape(theme: theme, shape: Circle(), fallback: theme.elevatedSurface)
                    }
                    .accessibilityLabel(ar ? "إغلاق" : "Close")
                }
                VStack(spacing: 6) {
                    Text(ar ? "\(feature.ar) ميزة في Pro" : "\(feature.en) is a Pro feature")
                        .font(GhafTypography.display(28, languageCode: lang))
                        .foregroundStyle(theme.primaryText)
                    Text(ar ? "الودجت، والنشاط المباشر، وتقارير أعمق، وصوت غاف AI المتقدم."
                            : "Widgets, Live Activities, deeper reports and Ghaf AI's advanced voice.")
                        .font(GhafTypography.body(15, languageCode: lang))
                        .foregroundStyle(theme.secondaryText)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(GhafProPlan.allCases) { item in
                        let selected = plan == item
                        Button { withAnimation(.snappy) { plan = item } } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title(ar)).font(GhafTypography.body(16, languageCode: lang, weight: .bold)).foregroundStyle(theme.primaryText)
                                    Text(item.cadence(ar)).font(GhafTypography.body(12, languageCode: lang)).foregroundStyle(theme.secondaryText)
                                }
                                Spacer()
                                Text(item.price).font(GhafTypography.number(16, weight: .heavy)).foregroundStyle(theme.primaryText)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                            .background(selected ? theme.accent.opacity(0.14) : theme.elevatedSurface,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selected ? theme.primaryText : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.ghafPress)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                VStack(spacing: 4) {
                    Button {} label: {
                        Text(plan.renews ? (ar ? "ابدأ التجربة المجانية ٣ أيام" : "Start 3-day free trial")
                                         : (ar ? "اشترِ مدى الحياة" : "Buy lifetime"))
                            .frame(maxWidth: .infinity)
                    }
                    .ghafProminentButton(theme: theme, languageCode: lang)
                    .disabled(true)
                    Button { dismiss() } label: {
                        Text(ar ? "تخطَّ الآن" : "Skip for now").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .font(GhafTypography.body(16, languageCode: lang, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                }

                Text(ar ? "الشراء غير متاح بعد في هذه النسخة، والميزة مجانية حتى ذلك الحين. بعد التجربة يتجدد الاشتراك حتى تلغيه. لا استرداد."
                        : "Purchases are not open yet in this version, so the feature stays free until then. After the trial a plan renews until cancelled. No refunds.")
                    .font(GhafTypography.body(12, languageCode: lang))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .ghafScreenPadding().padding(.top, 16).padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ghafGlassShape(theme: theme, shape: Rectangle(), fallback: theme.surface)
        .presentationDetents([.large, .fraction(0.78)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .sensoryFeedback(.selection, trigger: plan)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }
}
