import SwiftUI

/// Social and support links. shortcut: placeholders until the real accounts exist; replace the URLs here.
enum GhafLinks {
    static let instagram = URL(string: "https://instagram.com/instagram")!
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
                story.ghafEntrance(2)
                actions.ghafEntrance(3).id("about-actions")
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
            Text(ar ? "غاف" : "Ghaf")
                .font(GhafTypography.display(36, languageCode: lang))
                .opacity(appeared || reduceMotion ? 1 : 0)
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

    @State private var featureID: Int? = 0

    /// Owner 1.31 (V19): full-bleed feature cards in a cover flow that advances every 3 s; swipe to browse.
    private var featureList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    featureCard(feature, index: index)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.84 }
                        .scrollTransition(axis: .horizontal) { view, phase in
                            view.scaleEffect(phase.isIdentity ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $featureID)
        .padding(.horizontal, -GhafMetrics.gutter)
        .frame(height: 330)
        .task(id: featureID) {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.6)) { featureID = ((featureID ?? 0) + 1) % features.count }
        }
    }

    private func featureCard(_ feature: Feature, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            GhafOutlinedText(text: feature.title, font: GhafTypography.display(30, languageCode: lang))
            Text(feature.body).font(GhafTypography.body(15, languageCode: lang, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { GhafAboutShader(theme: theme, seed: Double(index), animate: !reduceMotion) }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ar ? "لماذا غاف؟" : "Why Ghaf?", systemImage: "questionmark.circle")
                .font(GhafTypography.body(13, languageCode: lang, weight: .bold)).foregroundStyle(theme.accent)
            Text(ar ? "سمّينا غاف تيمّناً بشجرة الغاف التي تمنح الظل لمن حولها. ونشكر دولة الإمارات على دعمها لكل من يعيش على أرضها."
                    : "Ghaf is named for the ghaf tree, which offers shade to everyone around it. We’re grateful to the UAE for supporting everyone who lives here.")
                .font(GhafTypography.body(15, languageCode: lang)).foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).ghafCard(theme: theme)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            ShareLink(item: GhafLinks.appStore, message: Text(ar ? "جرّب غاف لمتابعة أموالك" : "Try Ghaf to keep track of your money")) {
                row(ar ? "شارك غاف" : "Share Ghaf", "square.and.arrow.up")
            }
            // Until Ghaf has an App Store listing the link is a bare placeholder: shown, but inactive (owner rule).
            .disabled(GhafLinks.appStore.path.count <= 1).opacity(GhafLinks.appStore.path.count <= 1 ? 0.4 : 1)
            Divider().overlay(theme.outline).padding(.leading, 58)
            Link(destination: GhafLinks.appStore) { row(ar ? "قيّم غاف" : "Rate Ghaf", "star.fill") }
                .disabled(GhafLinks.appStore.path.count <= 1).opacity(GhafLinks.appStore.path.count <= 1 ? 0.4 : 1)
            Divider().overlay(theme.outline).padding(.leading, 58)
            Link(destination: GhafLinks.feedback) { row(ar ? "أرسل ملاحظاتك" : "Send feedback", "bubble.left.and.text.bubble.right.fill") }
            Divider().overlay(theme.outline).padding(.leading, 58)
            NavigationLink { GhafWhyPaidPage(settings: settings) } label: {
                row(ar ? "لماذا غاف مدفوع؟" : "Why is Ghaf paid?", "heart.text.square.fill")
            }
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
        .disabled(url.path.count <= 1 || url.host == "example.com")
        .opacity(url.path.count <= 1 || url.host == "example.com" ? 0.4 : 1)
        .accessibilityLabel(name)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(ar ? "بامتنان لدولة الإمارات" : "With gratitude to the UAE")
                .font(GhafTypography.body(12, languageCode: lang, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text("© 2026 Abdulkarim Bayassi")
                .font(GhafTypography.body(11, languageCode: lang))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
        .padding(.top, 4)
    }
}

private struct GhafWhyPaidPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showProSheet = false
    let settings: GhafSettings
    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 64, height: 64)
                    .background(theme.accent.opacity(0.12), in: Circle())
                Text(ar ? "صُمّم ليبقى هادئاً وصادقاً ولك." : "Built to stay calm, honest and yours.")
                    .font(GhafTypography.heading(20, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                paidReason("nosign", ar ? "بلا إعلانات، أبداً" : "No ads, ever",
                           ar ? "تبقى تجربتك هادئة وخالية من الإعلانات." : "Your experience stays calm and ad-free.")
                Divider().overlay(theme.outline).padding(.leading, 56)
                paidReason("lock.shield", ar ? "مستقل ويحترم خصوصيتك" : "Independent and private",
                           ar ? "يدعم Pro التطوير، لا بيع بياناتك." : "Pro supports development, not the sale of your data.")
                Divider().overlay(theme.outline).padding(.leading, 56)
                paidReason("checkmark.seal", ar ? "يبقى الإصدار المجاني مفيداً" : "Free stays useful",
                           ar ? "ستبقى الميزانيات والحسابات والتنبيهات البنكية مجانية." : "Budgets, accounts and bank alerts stay free.")
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .ghafCard(theme: theme)

            Button { showProSheet = true } label: {
                Text(ar ? "اكتشف غاف برو" : "See Ghaf Pro")
                    .font(GhafTypography.body(17, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.accentContrast)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background.ignoresSafeArea())
        .ghafPageTitle(ar ? "لماذا غاف مدفوع؟" : "Why is Ghaf paid?", languageCode: settings.languageCode, theme: theme)
        .ghafProSheet(isPresented: $showProSheet, settings: settings)
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    private func paidReason(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                Text(subtitle).font(GhafTypography.body(12, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

/// Owner pick "outline titles": white outline, see-through middle.
private struct GhafOutlinedText: View {
    let text: String
    let font: Font
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).font(font).foregroundStyle(.white)
                    .offset(x: cos(a) * 1.2, y: sin(a) * 1.2)
            }
            Text(text).font(font).foregroundStyle(.black.opacity(0.55)).blendMode(.destinationOut)
        }
        .compositingGroup()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(text)
    }
}

/// Owner pick "shaders": a slow-moving colour field in the theme's accent, drawn live.
private struct GhafAboutShader: View {
    let theme: GhafTheme
    let seed: Double
    let animate: Bool
    var body: some View {
        TimelineView(.animation(paused: !animate)) { context in
            let t = animate ? context.date.timeIntervalSinceReferenceDate * 0.25 + seed * 1.7 : seed
            // Graphite's accent is pure black/white, which would wash out the white text; use steel instead.
            let glow = theme.name == "Graphite" ? Color(red: 0.42, green: 0.46, blue: 0.52) : theme.accent
            ZStack {
                Color.black
                RadialGradient(colors: [glow, .clear], center: UnitPoint(x: 0.5 + 0.35 * cos(t), y: 0.4 + 0.3 * sin(t * 1.3)),
                               startRadius: 0, endRadius: 320)
                RadialGradient(colors: [glow.opacity(0.6), .clear], center: UnitPoint(x: 0.5 + 0.4 * sin(t * 0.8), y: 0.8 + 0.2 * cos(t)),
                               startRadius: 0, endRadius: 260)
                    .blendMode(.screen)
            }
        }
    }
}
