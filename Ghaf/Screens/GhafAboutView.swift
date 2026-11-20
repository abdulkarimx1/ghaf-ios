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
        ScrollViewReader { proxy in
            ScrollView {
            VStack(spacing: 14) {
                hero
                featureList.ghafEntrance(1)
                actions.ghafEntrance(2).id("about-actions")
                socials.ghafEntrance(3)
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
#if DEBUG
            .task {
                if GhafScreenshotFixture.enabled, GhafScreenshotFixture.destination == "about-proof" {
                    await Task.yield()
                    proxy.scrollTo("about-actions", anchor: .bottom)
                }
            }
#endif
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image("GhafBrandMark")
                .resizable().scaledToFit()
                .frame(width: 76, height: 76)
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
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var featureList: some View {
        VStack(spacing: 12) {
            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 48, height: 48)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(feature.title).font(GhafTypography.heading(19, languageCode: lang)).foregroundStyle(theme.primaryText)
                    Text(feature.body).font(GhafTypography.body(14, languageCode: lang)).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).ghafCard(theme: theme)
            }
        }
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
