import SwiftUI

/// Social and support links. shortcut: placeholders until the real accounts exist; replace the URLs here.
enum GhafLinks {
    static let instagram = URL(string: "https://instagram.com/")!
    static let x = URL(string: "https://x.com/")!
    static let tiktok = URL(string: "https://tiktok.com/")!
    static let website = URL(string: "https://example.com/")!
    static let feedback = URL(string: "mailto:?subject=Ghaf%20feedback")!
    static let appStore = URL(string: "https://apps.apple.com/")!
}

struct GhafAboutView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let settings: GhafSettings
    @State private var page = 0
    @State private var appeared = false

    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: systemColorScheme == .dark)
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    private struct Feature { let symbol: String; let title: String; let body: String }
    private var features: [Feature] {
        [
            Feature(symbol: "lock.shield.fill", title: ar ? "خاص منذ البداية" : "Private from the start",
                    body: ar ? "بياناتك على جهازك. لا حساب ولا تسجيل دخول بنكي." : "Your data lives on your iPhone. No account, no bank login."),
            Feature(symbol: "bolt.fill", title: ar ? "يسجّل وحده" : "Logs itself",
                    body: ar ? "رسائل البنك وApple Pay تتحول إلى عمليات دون أن تكتب شيئاً." : "Bank messages and Apple Pay become transactions without typing."),
            Feature(symbol: "sparkles", title: ar ? "يتعلم منك" : "Learns from you",
                    body: ar ? "صحّح الفئة مرة، ويتذكر غاف في كل مرة بعدها." : "Fix a category once and Ghaf remembers every time after."),
            Feature(symbol: "chart.line.uptrend.xyaxis", title: ar ? "يرى ما هو قادم" : "Sees what's coming",
                    body: ar ? "توقع نهاية الشهر وتنبيه عند أي عملية غير معتادة." : "A month-end forecast and a heads-up on unusual charges.")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                featureCarousel.ghafEntrance(1)
                story.ghafEntrance(2)
                actions.ghafEntrance(3)
                socials.ghafEntrance(4)
                footer
            }
            .ghafScreenPadding()
            .padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .ghafBackground(theme: theme)
        .ghafPageTitle(ar ? "عن غاف" : "About Ghaf", languageCode: lang, theme: theme)
        .environment(\.locale, Locale(identifier: lang))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.3)) { appeared = true } }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("GhafBrandMark")
                .resizable().scaledToFit()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .scaleEffect(appeared ? 1 : 0.7)
                .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -8))
            Text(ar ? "غاف" : "Ghaf")
                .font(GhafTypography.display(36, languageCode: lang))
            Text(ar ? "أموالك، بوضوح." : "Your money, clearly.")
                .font(GhafTypography.body(16, languageCode: lang, weight: .medium))
                .opacity(0.85)
            Text((ar ? "الإصدار " : "Version ") + version)
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(theme.accentContrast.opacity(0.15), in: Capsule())
        }
        // Text follows the accent's own contrast colour, so light accents (Graphite, dark mode) get dark text.
        .foregroundStyle(theme.accentContrast)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background {
            ZStack {
                LinearGradient(colors: [theme.accent, theme.glow], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 220))
                    .foregroundStyle(theme.accentContrast.opacity(0.08))
                    .rotationEffect(.degrees(-20))
                    .offset(x: 110, y: 40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var featureCarousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 48, height: 48)
                            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .symbolEffect(.bounce, value: page == index)
                        Text(feature.title)
                            .font(GhafTypography.heading(19, languageCode: lang))
                            .foregroundStyle(theme.primaryText)
                        Text(feature.body)
                            .font(GhafTypography.body(14, languageCode: lang))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ghafCard(theme: theme)
                    .padding(.horizontal, 2)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 176)
            HStack(spacing: 6) {
                ForEach(features.indices, id: \.self) { index in
                    Capsule().fill(index == page ? theme.accent : theme.secondaryText.opacity(0.3))
                        .frame(width: index == page ? 20 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityHidden(true)
        }
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ar ? "لماذا غاف؟" : "Why Ghaf?", systemImage: "leaf.fill")
                .font(GhafTypography.body(13, languageCode: lang, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(ar ? "الغاف شجرة الإمارات الوطنية. تعيش في الصحراء بقليل من الماء، وتمنح الظل لكل من حولها. هكذا نريد غاف لأموالك: هادئ، صبور، وحاضر حين تحتاجه."
                    : "The Ghaf is the UAE's national tree. It thrives in the desert on very little water and gives shade to everyone around it. That's what we want Ghaf to be for your money: calm, patient, and there when you need it.")
                .font(GhafTypography.body(15, languageCode: lang))
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ghafCard(theme: theme)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            ShareLink(item: GhafLinks.appStore, message: Text(ar ? "جرّب غاف لمتابعة أموالك" : "Try Ghaf to keep track of your money")) {
                row(ar ? "شارك غاف" : "Share Ghaf", "square.and.arrow.up")
            }
            Divider().overlay(theme.outline).padding(.leading, 58)
            Link(destination: GhafLinks.appStore) { row(ar ? "قيّم غاف" : "Rate Ghaf", "star.fill") }
            Divider().overlay(theme.outline).padding(.leading, 58)
            Link(destination: GhafLinks.feedback) { row(ar ? "أرسل ملاحظاتك" : "Send feedback", "bubble.left.and.text.bubble.right.fill") }
            Divider().overlay(theme.outline).padding(.leading, 58)
            NavigationLink { GhafTermsView(settings: settings) } label: { row(ar ? "شروط الاشتراك" : "Terms of subscription", "doc.text.fill") }
            Divider().overlay(theme.outline).padding(.leading, 58)
            NavigationLink { GhafPrivacyPolicyView(settings: settings) } label: { row(ar ? "سياسة الخصوصية" : "Privacy policy", "hand.raised.fill") }
        }
        .buttonStyle(.ghafPress)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .ghafCard(theme: theme)
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        GhafListRow(icon: symbol, tint: theme.accent, title: title, theme: theme, languageCode: lang, chevron: true) { EmptyView() }
    }

    private var socials: some View {
        HStack(spacing: 12) {
            social("Instagram", "camera.fill", GhafLinks.instagram)
            social("X", "xmark", GhafLinks.x)
            social("TikTok", "music.note", GhafLinks.tiktok)
            social(ar ? "الموقع" : "Website", "globe", GhafLinks.website)
        }
    }

    private func social(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .ghafGlassShape(theme: theme, shape: Circle(), fallback: theme.surface)
                    .foregroundStyle(theme.primaryText)
                Text(name)
                    .font(GhafTypography.body(11, languageCode: lang, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ghafPress)
        .accessibilityLabel(name)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(ar ? "صُنع بحب في الإمارات" : "Made with love in the UAE")
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text("© 2026 Abdulkarim Bayassi")
                .font(GhafTypography.body(11, languageCode: lang))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
        .padding(.top, 4)
    }
}
