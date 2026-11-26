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

/// Full-screen story pages: each page is a looping scene with its text and one action over it.
/// Swipe follows the finger, a flick moves exactly one page, dots jump, auto-advance stops on touch.
struct GhafAboutView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(GhafTabRouter.self) private var router
    let settings: GhafSettings

    private enum Destination: Hashable { case privacy, automation, learned, stats, whyPaid, terms }

    @State private var pos = 0.0
    @State private var active = 0
    @State private var dragStart: Double?
    @State private var touching = false
    @State private var autoAdvance = true
    @State private var destination: Destination?

    private let count = 5
    private var ar: Bool { settings.languageCode == "ar" }
    private var lang: String { settings.languageCode }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: systemColorScheme == .dark)
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
    private func t(_ en: String, _ arabic: String) -> String { ar ? arabic : en }

    private struct Page { let title: String; let body: String; let cta: String; let destination: Destination }
    private var pages: [Page] {
        [
            Page(title: t("Private from the start", "خصوصيتك من أول يوم"),
                 body: t("Your money stays on your iPhone, behind Face ID. No account, no bank login.",
                         "فلوسك تبقى على جهازك، محمية بـ Face ID. بدون حساب، وبدون تسجيل دخول للبنك."),
                 cta: t("Read the privacy policy", "اقرأ سياسة الخصوصية"), destination: .privacy),
            Page(title: t("Logs itself", "يسجّل لحاله"),
                 body: t("A bank alert arrives and it's recorded for you. You don't type a thing.",
                         "يوصلك تنبيه البنك، ويتسجّل لك. ما تكتب شي."),
                 cta: t("Set up automation", "فعّل التسجيل التلقائي"), destination: .automation),
            Page(title: t("Learns from you", "يتعلّم منك"),
                 body: t("Pick a category once; every visit after is sorted for you.",
                         "اختر التصنيف مرة وحدة، والزيارات الجاية تتصنّف لحالها."),
                 cta: t("See what it learned", "شوف وش تعلّم"), destination: .learned),
            Page(title: t("Sees what's coming", "يعرف وين بيوصل شهرك"),
                 body: t("Where the month will land, before it does.", "وين بيوصل صرفك هالشهر، قبل لا يوصل."),
                 cta: t("Open Statistics", "افتح الإحصائيات"), destination: .stats),
            Page(title: t("Why we built it", "ليش سوّيناه"),
                 body: t("Calm, private money tracking for the Gulf. With gratitude to the UAE.",
                         "متابعة هادية وخاصة لفلوسك في الخليج. مع الامتنان لدولة الإمارات."),
                 cta: t("Why is Pro paid?", "ليش برو مدفوع؟"), destination: .whyPaid)
        ]
    }

    var body: some View {
        GeometryReader { geo in
            // Read the insets here, then draw edge to edge: scenes sit behind the status bar and home indicator.
            let top = geo.safeAreaInsets.top, bottom = geo.safeAreaInsets.bottom
            let size = CGSize(width: geo.size.width, height: geo.size.height + top + bottom)
            let env = GhafAboutSceneEnv(theme: theme, lang: lang, reduce: reduceMotion, size: size, top: top)
            ZStack {
                theme.ink
                scenes(env)
                overlay(bottomInset: bottom)
                Button { router.fullScreenPage = false; dismiss() } label: {
                    Image(systemName: "chevron.backward").resizable().scaledToFit().frame(width: 12, height: 20)
                        .foregroundStyle(theme.inkText).frame(width: 44, height: 44).background(Color.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel(t("Back", "رجوع"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, top + 6).padding(.horizontal, 18)
            }
            .frame(width: size.width, height: size.height)
            .offset(y: -top)
            .contentShape(Rectangle())
            .simultaneousGesture(pager(width: size.width))
        }
        .background(theme.ink.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .modifier(GhafHideTabBar())
        .onAppear { router.fullScreenPage = true }
        .onDisappear { router.fullScreenPage = false }
        // Leave dark mode before a linked page slides in, so it doesn't flash dark first.
        .onChange(of: destination) { _, value in if value != nil { router.fullScreenPage = false } }
        .environment(\.locale, Locale(identifier: lang))
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        .sensoryFeedback(.selection, trigger: active)
        .task(id: "\(active)-\(touching)-\(autoAdvance)") {
            guard autoAdvance, !touching, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(7.6))
            if !Task.isCancelled { go((active + 1) % count, manual: false) }
        }
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .privacy: GhafPrivacyPolicyView(settings: settings)
            case .automation: GhafAutomationGuideView(settings: settings)
            case .learned: GhafLearnedRulesView(settings: settings)
            case .stats: GhafStatsView(settings: settings).ghafPushedBack(theme: theme, languageCode: lang)
            case .whyPaid: GhafWhyPaidPage(settings: settings)
            case .terms: GhafTermsView(settings: settings)
            }
        }
#if DEBUG
        .onAppear {
            if GhafScreenshotFixture.enabled, let page = GhafScreenshotFixture.aboutPage, (0..<count).contains(page) { pos = Double(page); active = page }
        }
#endif
    }

    // MARK: Pages

    private func scenes(_ env: GhafAboutSceneEnv) -> some View {
        let dir: Double = ar ? -1 : 1
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let d = Double(i) - pos
                scene(i, env)
                    .offset(x: reduceMotion ? 0 : dir * d * env.size.width)
                    .opacity(reduceMotion ? max(0, 1 - abs(d)) : (abs(d) > 1.01 ? 0 : 1))
            }
        }
    }

    @ViewBuilder private func scene(_ i: Int, _ env: GhafAboutSceneEnv) -> some View {
        let on = i == active
        switch i {
        case 0: GhafAboutPrivateScene(env: env, active: on)
        case 1: GhafAboutLogScene(env: env, active: on)
        case 2: GhafAboutLearnScene(env: env, active: on)
        case 3: GhafAboutForecastScene(env: env, active: on)
        default: GhafAboutWhyScene(env: env, active: on)
        }
    }

    // MARK: Paging

    private func go(_ index: Int, manual: Bool = true) {
        if manual { autoAdvance = false }
        let target = max(0, min(count - 1, index))
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) { pos = Double(target) }
        active = target
    }

    private func pager(width: CGFloat) -> some Gesture {
        let dir: CGFloat = ar ? -1 : 1
        return DragGesture(minimumDistance: 12)
            .onChanged { v in
                touching = true
                if dragStart == nil {
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    dragStart = Double(active)
                }
                guard let start = dragStart, !reduceMotion else { return }
                var raw = start - Double(v.translation.width * dir / width)
                raw = min(start + 1, max(start - 1, raw))
                if raw < 0 { raw *= 0.3 }
                if raw > Double(count - 1) { raw = Double(count - 1) + (raw - Double(count - 1)) * 0.3 }
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { pos = raw }
            }
            .onEnded { v in
                touching = false
                guard let start = dragStart else { return }
                dragStart = nil
                let travel = Double(-v.translation.width * dir / width)
                let flick = Double(-v.velocity.width * dir)
                var step = 0
                if travel > 0.2 || flick > 500 { step = 1 } else if travel < -0.2 || flick < -500 { step = -1 }
                let target = max(0, min(count - 1, Int(start) + step))
                autoAdvance = false
                // The spring starts at the finger's speed so a flick carries on instead of restarting.
                let remaining = max(1, abs(Double(target) - pos)) * Double(width)
                let toward = (Double(target) - pos) >= 0 ? flick : -flick
                withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                              : .interpolatingSpring(mass: 1, stiffness: 190, damping: 24, initialVelocity: max(0, toward) / remaining)) {
                    pos = Double(target)
                }
                active = target
            }
    }

    // MARK: Overlay

    private func overlay(bottomInset: CGFloat) -> some View {
        let page = pages[active]
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(page.title).font(GhafTypography.heading(28, languageCode: lang)).foregroundStyle(theme.inkText)
                Text(page.body).font(GhafTypography.body(15, languageCode: lang)).foregroundStyle(theme.inkText.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(active)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { direction in
                go(direction == .increment ? active + 1 : active - 1)
            }
            HStack(spacing: 0) {
                dots
                Spacer(minLength: 8)
                Button { destination = .terms } label: {
                    Text(t("Terms", "الشروط")).font(GhafTypography.body(13, languageCode: lang, weight: .semibold))
                        .foregroundStyle(theme.inkText.opacity(0.72)).frame(minHeight: 44)
                }
                Text(verbatim: "\u{00B7}").foregroundStyle(theme.inkText.opacity(0.5)).padding(.horizontal, 6)
                Text(verbatim: version).font(GhafTypography.number(12, weight: .medium))
                    .foregroundStyle(theme.inkText.opacity(0.5)).environment(\.layoutDirection, .leftToRight)
            }
            .padding(.bottom, 14) // owner: dots sat too close to the button
            Button { destination = page.destination } label: {
                Text(page.cta).font(GhafTypography.body(17, languageCode: lang, weight: .semibold)).foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 54).background(theme.inkText, in: Capsule())
            }
            .id("cta-\(active)")
            .transition(.opacity)
            HStack(spacing: 10) {
                pill(t("Rate", "قيّم"), "star.fill", GhafLinks.appStore)
                pill(t("Feedback", "ملاحظات"), "bubble.left.fill", GhafLinks.feedback)
            }
            HStack {
                ShareLink(item: GhafLinks.appStore, message: Text(t("Try Ghaf to keep track of your money", "جرّب غاف لمتابعة أموالك"))) { circle("square.and.arrow.up") }
                    .disabled(isPlaceholder(GhafLinks.appStore)).opacity(isPlaceholder(GhafLinks.appStore) ? 0.4 : 1)
                    .accessibilityLabel(t("Share", "مشاركة"))
                Spacer(minLength: 0)
                social("Instagram", "camera.fill", GhafLinks.instagram); Spacer(minLength: 0)
                social("X", "xmark", GhafLinks.x); Spacer(minLength: 0)
                social("TikTok", "music.note", GhafLinks.tiktok); Spacer(minLength: 0)
                social(t("Website", "الموقع"), "globe", GhafLinks.website)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25), value: active)
        .buttonStyle(.ghafPress)
        .padding(.horizontal, 24).padding(.bottom, max(bottomInset, 16) + 12)
    }

    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Button { go(i) } label: {
                    Capsule().fill(theme.inkText.opacity(i == active ? 1 : 0.28)).frame(width: i == active ? 22 : 7, height: 7)
                        .padding(.horizontal, 3).frame(minWidth: 26, minHeight: 44)
                }
                .accessibilityLabel(t("Page ", "الصفحة ") + "\(i + 1)")
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.85), value: active)
    }

    private func isPlaceholder(_ url: URL) -> Bool { url.path.count <= 1 || url.host == "example.com" }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol).resizable().scaledToFit().frame(width: 19, height: 19).foregroundStyle(theme.inkText)
            .frame(width: 48, height: 48).background(Color.white.opacity(0.12), in: Circle())
    }

    private func social(_ name: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) { circle(symbol) }
            .disabled(isPlaceholder(url)).opacity(isPlaceholder(url) ? 0.4 : 1)
            .accessibilityLabel(name)
    }

    private func pill(_ title: String, _ symbol: String, _ url: URL) -> some View {
        // Until there is an App Store listing the link is a bare placeholder: shown, but inactive (owner rule).
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: symbol).resizable().scaledToFit().frame(width: 17, height: 17)
                Text(title).font(GhafTypography.body(15, languageCode: lang, weight: .semibold))
            }
            .foregroundStyle(theme.inkText).frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(0.12), in: Capsule())
        }
        .disabled(url == GhafLinks.appStore && isPlaceholder(url)).opacity(url == GhafLinks.appStore && isPlaceholder(url) ? 0.4 : 1)
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

/// Full-screen pages hide the tab bar and show a light status bar. The SwiftUI modifiers do not reach the
/// app's root TabView and colour scheme here, so this reaches the UIKit objects directly and restores them on exit.
private struct GhafHideTabBar: ViewModifier {
    func body(content: Content) -> some View { content.background(Hider().frame(width: 0, height: 0)) }

    private struct Hider: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Controller { Controller() }
        func updateUIViewController(_ controller: Controller, context: Context) {}
    }

    private final class Controller: UIViewController {
        private var savedStyle: UIUserInterfaceStyle = .unspecified
        private var tabBar: UITabBar? {
            func find(_ vc: UIViewController?) -> UITabBarController? {
                guard let vc else { return nil }
                if let tab = vc as? UITabBarController { return tab }
                for child in vc.children { if let tab = find(child) { return tab } }
                return find(vc.presentedViewController)
            }
            return find(view.window?.rootViewController)?.tabBar
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            savedStyle = view.window?.overrideUserInterfaceStyle ?? .unspecified
            view.window?.overrideUserInterfaceStyle = .dark
            UIView.animate(withDuration: 0.2) { self.tabBar?.alpha = 0 }
            tabBar?.isHidden = true
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            view.window?.overrideUserInterfaceStyle = savedStyle
            tabBar?.isHidden = false
            UIView.animate(withDuration: 0.2) { self.tabBar?.alpha = 1 }
        }
    }
}
