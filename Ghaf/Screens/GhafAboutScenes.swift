import SwiftUI

/// Shared bits for the About scenes: full-screen, borderless, each one a small looping story.
struct GhafAboutSceneEnv {
    let theme: GhafTheme
    let lang: String
    let reduce: Bool
    let size: CGSize
    let top: CGFloat
    var ar: Bool { lang == "ar" }
    func t(_ en: String, _ arabic: String) -> String { ar ? arabic : en }
}

/// Plays a scene's story when it becomes the active page and repeats it while it stays active.
/// Reduce Motion shows the finished state instead and never loops.
private struct AboutLoop: ViewModifier {
    let active: Bool
    let reduce: Bool
    let reset: () -> Void
    let final: () -> Void
    let play: () async -> Void

    func body(content: Content) -> some View {
        content.task(id: active) {
            // A page that was just left keeps its last frame while it slides out, then goes back to its first.
            guard active else { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled { reset() }; return }
            if reduce { final(); return }
            while !Task.isCancelled {
                reset()
                await play()
                try? await Task.sleep(for: .milliseconds(1800))
            }
        }
    }
}

extension View {
    fileprivate func aboutLoop(active: Bool, reduce: Bool, reset: @escaping () -> Void, final: @escaping () -> Void,
                               play: @escaping () async -> Void) -> some View {
        modifier(AboutLoop(active: active, reduce: reduce, reset: reset, final: final, play: play))
    }
}

private func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

/// Amount with its currency, in the app's number font. Digits stay Western in Arabic.
private struct AboutMoney: View {
    let currency: String
    let amount: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var negative = false
    let color: Color
    let ar: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.28) {
            // Locked rule: AED, SAR and OMR use their official sign; other currencies show the ISO code.
            if ar {
                Text(verbatim: (negative ? "\u{2212}" : "") + amount).font(GhafTypography.number(size, weight: weight))
                mark
            } else {
                if negative { Text(verbatim: "\u{2212}").font(GhafTypography.number(size, weight: weight)) }
                mark
                Text(verbatim: amount).font(GhafTypography.number(size, weight: weight))
            }
        }
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1).minimumScaleFactor(0.6)
    }

    @ViewBuilder private var mark: some View {
        if GhafCurrencyIcon.assetName(currency) != nil {
            GhafCurrencyIcon(currency: currency, size: size * 0.72)
        } else {
            Text(verbatim: currency).font(GhafTypography.number(size * 0.62, weight: .semibold))
        }
    }
}

private struct AboutTxRow: View {
    let env: GhafAboutSceneEnv
    let symbol: String
    let tint: Color
    let name: String
    let sub: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(GhafTypography.body(16, languageCode: env.lang, weight: .semibold)).foregroundStyle(env.theme.primaryText)
                Text(sub).font(GhafTypography.body(13, languageCode: env.lang, weight: .medium)).foregroundStyle(env.theme.secondaryText)
            }
            Spacer(minLength: 8)
            AboutMoney(currency: "AED", amount: amount, size: 16, weight: .bold, negative: true,
                       color: env.theme.primaryText, ar: env.ar)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

private struct AboutCard<Content: View>: View {
    let env: GhafAboutSceneEnv
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(env.theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(env.theme.outline, lineWidth: 1))
    }
}

/// The dark scene wall: soft light patches on the theme's ink colour, no hard edges.
struct GhafAboutWall: View {
    let theme: GhafTheme
    var body: some View {
        ZStack {
            theme.ink
            LinearGradient(colors: [Color.white.opacity(0.14), .clear, Color.black.opacity(0.45)], startPoint: .topLeading, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: UnitPoint(x: 0.25, y: 0.12), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.85, y: 0.7), startRadius: 0, endRadius: 300)
        }
    }
}

// MARK: 1 Private

struct GhafAboutPrivateScene: View {
    let env: GhafAboutSceneEnv
    let active: Bool
    @State private var scan = false
    @State private var open = false
    @State private var cur = 0
    @State private var foldAngle = 0.0

    private let gcc: [(en: String, ar: String, amount: String)] = [
        ("AED", "د.إ", "9,150.00"), ("SAR", "ر.س", "9,342.75"), ("OMR", "ر.ع", "962.400"),
        ("KWD", "د.ك", "764.120"), ("BHD", "د.ب", "935.550"), ("QAR", "ر.ق", "9,068.20")
    ]

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: env.ar ? "ar_AE@numbers=latn" : "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: .now)
    }

    var body: some View {
        ZStack {
            GhafAboutWall(theme: env.theme)
            appLayer
            lockLayer
        }
        .aboutLoop(active: active, reduce: env.reduce, reset: reset, final: final, play: play)
    }

    private var lockLayer: some View {
        VStack(spacing: 0) {
            Text(dateText).font(GhafTypography.body(17, languageCode: env.lang, weight: .semibold)).foregroundStyle(env.theme.inkText.opacity(0.8))
            Text(verbatim: "9:41").font(GhafTypography.number(92, weight: .semibold)).foregroundStyle(env.theme.inkText)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(env.t("Total balance", "إجمالي الرصيد")).font(GhafTypography.body(13, languageCode: env.lang, weight: .semibold))
                    .foregroundStyle(env.theme.inkText.opacity(0.7))
                AboutMoney(currency: "AED", amount: "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}", size: 28,
                           color: env.theme.inkText, ar: env.ar)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 16)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 24).padding(.top, 20)
            Image(systemName: scan ? "checkmark" : "faceid").resizable().scaledToFit().frame(width: 46, height: 46)
                .foregroundStyle(env.theme.inkText).padding(.top, 34)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(scan ? 1.06 : 0.92)
            Spacer(minLength: 0)
        }
        .padding(.top, env.top + 34)
        .frame(width: env.size.width, height: env.size.height)
        .offset(y: open ? -env.size.height : 0).opacity(open ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var appLayer: some View {
        VStack(spacing: 0) {
            Text(env.t("Good morning", "صباح الخير")).font(GhafTypography.body(14, languageCode: env.lang, weight: .semibold))
                .foregroundStyle(env.theme.inkText.opacity(0.7))
            Text(env.t("Amina", "أمينة")).font(GhafTypography.heading(30, languageCode: env.lang)).foregroundStyle(env.theme.inkText)
                .padding(.bottom, 14)
            AboutCard(env: env) {
                VStack(spacing: 8) {
                    Text(env.t("Total balance", "إجمالي الرصيد")).font(GhafTypography.body(13, languageCode: env.lang, weight: .semibold))
                        .foregroundStyle(env.theme.secondaryText)
                    AboutMoney(currency: gcc[cur].en, amount: gcc[cur].amount, size: 42, weight: .bold,
                               color: env.theme.primaryText, ar: env.ar)
                        .rotation3DEffect(.degrees(foldAngle), axis: (1, 0, 0), perspective: 0.4)
                        .opacity(1 - abs(foldAngle) / 90)
                    HStack(spacing: 8) {
                        chip(env.t("Mashreq Current", "المشرق الجاري"))
                        chip(env.t("Cash wallet", "المحفظة النقدية"))
                    }.padding(.top, 6)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 18)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .padding(.top, env.top + 58)
        .frame(width: env.size.width, height: env.size.height)
        .scaleEffect(open ? 1 : 0.94).opacity(open ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(GhafTypography.body(12, languageCode: env.lang, weight: .semibold)).foregroundStyle(env.theme.secondaryText)
            .padding(.horizontal, 10).padding(.vertical, 6).background(env.theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reset() { scan = false; open = false; cur = 0; foldAngle = 0 }
    private func final() { scan = true; open = true; cur = 0 }

    private func fold(to k: Int) async {
        withAnimation(.easeIn(duration: 0.22)) { foldAngle = 90 }
        await pause(230)
        cur = k; foldAngle = -90
        withAnimation(.easeOut(duration: 0.26)) { foldAngle = 0 }
    }

    private func play() async {
        await pause(700)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { scan = true }
        await pause(800)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { open = true }
        await pause(1100)
        for k in 1..<gcc.count { await fold(to: k); await pause(900) }
    }
}

// MARK: 2 Logs itself

struct GhafAboutLogScene: View {
    let env: GhafAboutSceneEnv
    let active: Bool
    @State private var islandOpen = false
    @State private var done = false
    @State private var rowIn = false

    var body: some View {
        ZStack(alignment: .top) {
            GhafAboutWall(theme: env.theme)
            VStack(alignment: .leading, spacing: 12) {
                Text(env.t("Activity", "النشاط")).font(GhafTypography.heading(24, languageCode: env.lang)).foregroundStyle(env.theme.inkText)
                    .padding(.horizontal, 6)
                AboutCard(env: env) {
                    VStack(spacing: 0) {
                        if rowIn {
                            AboutTxRow(env: env, symbol: "cart.fill", tint: env.theme.comfortable, name: env.t("Carrefour", "كارفور"),
                                       sub: env.t("Groceries · now", "البقالة · الآن"), amount: "42.50")
                                .transition(.move(edge: .top).combined(with: .opacity))
                            Divider().overlay(env.theme.outline)
                        }
                        AboutTxRow(env: env, symbol: "cup.and.saucer.fill", tint: env.theme.close, name: env.t("Local Cafe", "مقهى محلي"),
                                   sub: env.t("Food · 9:12 AM", "الطعام · 9:12 ص"), amount: "21.00")
                        Divider().overlay(env.theme.outline)
                        AboutTxRow(env: env, symbol: "fuelpump.fill", tint: env.theme.accent, name: env.t("ENOC", "إينوك"),
                                   sub: env.t("Car · Yesterday", "السيارة · أمس"), amount: "120.00")
                    }
                    .clipped()
                }
            }
            .padding(.horizontal, 16).padding(.top, env.top + 58)
            island.padding(.top, 12)
        }
        .frame(width: env.size.width, height: env.size.height, alignment: .top)
        .aboutLoop(active: active, reduce: env.reduce, reset: reset, final: { rowIn = true }, play: play)
        .accessibilityHidden(true)
    }

    private var island: some View {
        // Owner #41: content sits below the hardware island's band (like a real expanded Live Activity), so the cutout never crops it.
        ZStack(alignment: .bottom) {
            Color.black
            HStack(spacing: 12) {
                Image(systemName: "cart.fill").resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(Color.black)
                    .frame(width: 42, height: 42).background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(env.t("Carrefour", "كارفور")).font(GhafTypography.body(16, languageCode: env.lang, weight: .semibold))
                    Text(env.t("Mashreq ·· 4821", "المشرق ·· 4821")).font(GhafTypography.body(13, languageCode: env.lang, weight: .medium)).opacity(0.6)
                }
                Spacer(minLength: 8)
                AboutMoney(currency: "AED", amount: "42.50", size: 21, negative: true, color: .white, ar: env.ar)
                Image(systemName: "checkmark").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(Color.white)
                    .frame(width: 24, height: 24).background(env.theme.inkCredit, in: Circle())
                    .scaleEffect(done ? 1 : 0.6).opacity(done ? 1 : 0)
            }
            .foregroundStyle(Color.white).padding(.horizontal, 20).padding(.bottom, 16).opacity(islandOpen ? 1 : 0)
        }
        .frame(width: islandOpen ? min(360, env.size.width * 0.92) : 124, height: islandOpen ? 112 : 36)
        .clipShape(RoundedRectangle(cornerRadius: islandOpen ? 40 : 20, style: .continuous))
    }

    private func reset() { islandOpen = false; done = false; rowIn = false }

    private func play() async {
        await pause(500)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { islandOpen = true }
        await pause(1000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { done = true }
        await pause(1200)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { islandOpen = false; done = false }
        await pause(300)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { rowIn = true }
        await pause(2400)
    }
}

// MARK: 3 Learns

struct GhafAboutLearnScene: View {
    let env: GhafAboutSceneEnv
    let active: Bool
    @State private var picked = false
    @State private var tapping = false
    @State private var shown = 0

    var body: some View {
        ZStack(alignment: .top) {
            GhafAboutWall(theme: env.theme)
            VStack(spacing: 12) {
                AboutCard(env: env) {
                    VStack(alignment: .leading, spacing: 0) {
                        AboutTxRow(env: env, symbol: "bag.fill", tint: env.theme.debit, name: env.t("Kibsons", "كيبسونز"),
                                   sub: env.t("Which category? · now", "أي فئة؟ · الآن"), amount: "86.00")
                        HStack(spacing: 6) {
                            cat(env.t("Groceries", "البقالة"), on: picked, pressed: tapping)
                            cat(env.t("Food", "الطعام"), on: false, pressed: false)
                            cat(env.t("Shopping", "التسوق"), on: false, pressed: false)
                            cat(env.t("Other", "أخرى"), on: !picked, pressed: false)
                        }.padding(.horizontal, 14).padding(.bottom, 14)
                    }
                }
                ForEach(0..<2, id: \.self) { i in
                    AboutCard(env: env) {
                        AboutTxRow(env: env, symbol: "cart.fill", tint: env.theme.comfortable, name: env.t("Kibsons", "كيبسونز"),
                                   sub: i == 0 ? env.t("Groceries · next week", "البقالة · الأسبوع القادم") : env.t("Groceries · in 2 weeks", "البقالة · بعد أسبوعين"),
                                   amount: i == 0 ? "64.50" : "91.25")
                    }
                    .opacity(shown > i ? 1 : 0).offset(y: shown > i ? 0 : -14)
                }
            }
            .padding(.horizontal, 16).padding(.top, env.top + 58)
        }
        .frame(width: env.size.width, height: env.size.height, alignment: .top)
        .aboutLoop(active: active, reduce: env.reduce, reset: { picked = false; tapping = false; shown = 0 },
                   final: { picked = true; shown = 2 }, play: play)
        .accessibilityHidden(true)
    }

    private func cat(_ text: String, on: Bool, pressed: Bool) -> some View {
        Text(text).font(GhafTypography.body(13, languageCode: env.lang, weight: .semibold))
            .foregroundStyle(on ? env.theme.inkText : env.theme.secondaryText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? env.theme.ink : env.theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(pressed ? 0.94 : 1)
    }

    private func play() async {
        await pause(800)
        withAnimation(.easeOut(duration: 0.16)) { tapping = true }
        await pause(160)
        withAnimation(.easeOut(duration: 0.3)) { tapping = false; picked = true }
        await pause(740)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = 1 }
        await pause(600)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = 2 }
        await pause(2500)
    }
}

// MARK: 4 Forecast

private struct AboutSpend: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i], c = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: c, y: a.y), control2: CGPoint(x: c, y: b.y))
        }
        return p
    }
}

struct GhafAboutForecastScene: View {
    let env: GhafAboutSceneEnv
    let active: Bool
    @State private var draw = 0.0
    @State private var extras = 0.0

    private let vals: [Double] = [12, 18, 16, 24, 27, 31, 30, 38, 42, 44, 49, 55, 58, 62]
    private let fv: [Double] = [62, 68, 73, 78]

    var body: some View {
        ZStack(alignment: .top) {
            GhafAboutWall(theme: env.theme)
            AboutCard(env: env) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(env.t("Spent · Month", "المصروف · الشهر")).font(GhafTypography.body(13, languageCode: env.lang, weight: .semibold))
                        .foregroundStyle(env.theme.secondaryText)
                    AboutMoney(currency: "AED", amount: "3,210.40", size: 34, weight: .bold, color: env.theme.primaryText, ar: env.ar)
                        .padding(.top, 6)
                    HStack(spacing: 4) {
                        Text(env.t("Estimate by the 30th:", "التقدير بحلول يوم 30:"))
                        AboutMoney(currency: "AED", amount: "4,820", size: 14, weight: .bold, color: env.theme.secondaryText, ar: env.ar)
                    }
                    .font(GhafTypography.body(14, languageCode: env.lang, weight: .medium)).foregroundStyle(env.theme.secondaryText).padding(.top, 4)
                    plot.frame(height: 56).padding(.top, 10)
                    HStack {
                        ForEach(["1–8", "9–16", "17–23", "24–30"], id: \.self) { Text(verbatim: $0).frame(maxWidth: .infinity) }
                    }
                    .font(GhafTypography.number(12, weight: .semibold)).foregroundStyle(env.theme.secondaryText).padding(.top, 8)
                    HStack(spacing: 0) {
                        ForEach(Array([("W", "أ"), ("M", "ش"), ("3M", "3ش"), ("Y", "س")].enumerated()), id: \.offset) { i, p in
                            Text(verbatim: env.ar ? p.1 : p.0).font(GhafTypography.body(14, languageCode: env.lang, weight: .semibold))
                                .foregroundStyle(i == 1 ? env.theme.inkText : env.theme.secondaryText)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(i == 1 ? env.theme.ink : Color.clear, in: Capsule())
                        }
                    }
                    .padding(4).background(env.theme.elevatedSurface, in: Capsule()).padding(.top, 10)
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
            }
            .padding(.horizontal, 16).padding(.top, env.top + 58)
        }
        .frame(width: env.size.width, height: env.size.height, alignment: .top)
        .aboutLoop(active: active, reduce: env.reduce, reset: { draw = 0; extras = 0 }, final: { draw = 1; extras = 1 }, play: play)
        .accessibilityHidden(true)
    }

    private var plot: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, pad = 8.0, maxV = 84.0
            let xAt = { (i: Double) in pad + i * (w - 2 * pad) / 17 }
            let yAt = { (v: Double) in h - pad - v / maxV * (h - 2 * pad) }
            let pts = vals.enumerated().map { CGPoint(x: xAt(Double($0.offset)), y: yAt($0.element)) }
            let fpts = fv.enumerated().map { CGPoint(x: xAt(13 + Double($0.offset) * 4 / 3), y: yAt($0.element)) }
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addPath(AboutSpend(points: pts).path(in: .zero))
                    p.addLine(to: CGPoint(x: pts[13].x, y: h)); p.addLine(to: CGPoint(x: pts[0].x, y: h)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [env.theme.primaryText.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                .opacity(extras)
                AboutSpend(points: fpts).stroke(env.theme.secondaryText, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5])).opacity(extras)
                AboutSpend(points: pts).trim(from: 0, to: draw)
                    .stroke(env.theme.primaryText, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Circle().fill(env.theme.primaryText).overlay(Circle().stroke(env.theme.surface, lineWidth: 2.5))
                    .frame(width: 11, height: 11).position(pts[13]).opacity(extras)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func play() async {
        withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 1.4)) { draw = 1 }
        await pause(1100)
        withAnimation(.easeOut(duration: 0.5)) { extras = 1 }
        await pause(2800)
    }
}

// MARK: 5 Why

struct GhafAboutWhyScene: View {
    let env: GhafAboutSceneEnv
    let active: Bool

    private func blob(_ color: Color, _ opacity: Double, _ t: Double, period: Double, radius: Double, scale: Double, at: CGPoint, reverse: Bool = false) -> some View {
        let a = (reverse ? -1 : 1) * t / period * 2 * .pi
        let d = env.size.width * scale
        return Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: d / 2))
            .frame(width: d, height: d)
            .position(x: env.size.width * at.x + cos(a) * env.size.width * radius, y: env.size.height * at.y + sin(a) * env.size.width * radius)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || env.reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                env.theme.ink
                blob(env.theme.inkText, 0.5, t, period: 19, radius: 0.16, scale: 1.5, at: CGPoint(x: 0.2, y: 0.22))
                blob(env.theme.accent, 0.8, t, period: 24, radius: 0.14, scale: 1.3, at: CGPoint(x: 0.85, y: 0.45), reverse: true)
                blob(env.theme.inkText, 0.22, t, period: 29, radius: 0.12, scale: 1.6, at: CGPoint(x: 0.4, y: 0.95))
                blob(env.theme.inkText, 0.28, t, period: 16, radius: 0.1, scale: 0.9, at: CGPoint(x: 0.5, y: 0.4), reverse: true)
            }
            .compositingGroup()
        }
        .frame(width: env.size.width, height: env.size.height)
        .clipped().accessibilityHidden(true)
    }
}
