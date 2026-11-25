import SwiftUI

/// Slow-moving theme glow behind the welcome pages (inspo: full-bleed blurred light, dark canvas).
struct GhafWelcomeGlow: View {
    let theme: GhafTheme
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let shift = Double(step) * 0.9
            ZStack {
                Circle().fill(theme.accent)
                    .frame(width: 300, height: 300)
                    .offset(x: cos(t * 0.35 + shift) * 70, y: sin(t * 0.28 + shift) * 40 - 40)
                Circle().fill(theme.glow)
                    .frame(width: 240, height: 240)
                    .offset(x: sin(t * 0.22 + shift) * 90, y: cos(t * 0.31) * 50 + 30)
            }
            .blur(radius: 70)
            .opacity(0.55)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The animated hero for welcome pages 0–3. Content is illustrative only.
struct GhafWelcomeHero: View {
    let step: Int
    let theme: GhafTheme
    let languageCode: String
    let cards: [GhafCardDesign]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private func text(_ en: String, _ ar: String) -> String { languageCode == "ar" ? ar : en }

    var body: some View {
        Group {
            switch step {
            // Owner 1.31: four feature cards: auto-capture, accounts, Ghaf AI voice, subscriptions + budget petals.
            case 0: capture
            case 1: accounts
            case 2: askGhaf
            default: subscriptionsAndPetals
            }
        }
        .onAppear {
            shown = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.7, bounce: 0.22).delay(0.05)) { shown = true }
        }
    }

    // MARK: Page 1 — accounts rise in one by one, balances roll up

    private var accounts: some View {
        let rows: [(String, Decimal)] = [("Mashreq", 8_540), ("ADCB", 3_280), (text("Cash wallet", "محفظة نقدية"), 640)]
        return VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 14) {
                    Group {
                        if let card = cards.dropFirst(index).first, index < 2 {
                            card.image.resizable().scaledToFill()
                        } else {
                            theme.accent.overlay(Image(systemName: "banknote").foregroundStyle(theme.accentContrast))
                        }
                    }
                    .frame(width: 52, height: 33).clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(row.0).font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                    Spacer()
                    GhafMoneyLabel(amount: shown ? row.1 : 0, currency: "AED", languageCode: languageCode, size: 17)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 16).frame(height: 64)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.outline, lineWidth: 1))
                .rotation3DEffect(.degrees(shown ? 0 : 55), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                .offset(y: shown ? 0 : 50)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .none : .spring(duration: 0.7, bounce: 0.2).delay(0.12 * Double(index)), value: shown)
            }
            Text(text("Illustrative balances", "أرصدة توضيحية"))
                .font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: Page 2 — a bank message drops in and becomes a logged transaction (loops)

    private var capture: some View {
        PhaseAnimator(reduceMotion ? [3] : [0, 1, 2, 3, 3]) { phase in
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "message.fill").foregroundStyle(theme.accent)
                    Text("Mashreq · " + text("Purchase of AED 35.00 at Bakery", "شراء بقيمة ٣٥٫٠٠ درهم من مخبز"))
                        .font(GhafTypography.body(15, languageCode: "en", weight: .medium)).multilineTextAlignment(.leading)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.outline, lineWidth: 1))
                .offset(y: phase >= 1 ? 0 : -60).opacity(phase >= 1 ? 1 : 0)
                .scaleEffect(phase == 2 ? 0.96 : 1)

                Image(systemName: "arrow.down").font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.accent)
                    .opacity(phase >= 2 ? 1 : 0).offset(y: phase >= 2 ? 0 : -10)

                HStack(spacing: 12) {
                    GhafCategoryIcon(category: "Dining", tint: theme.accent, theme: theme)
                    Text(text("Bakery", "مخبز")).font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                    Spacer()
                    GhafMoneyLabel(amount: 35, currency: "AED", languageCode: languageCode, size: 17)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(theme.credit)
                        .scaleEffect(phase >= 3 ? 1 : 0.2).opacity(phase >= 3 ? 1 : 0)
                }
                .padding(16)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(phase >= 3 ? 0.8 : 0.0), lineWidth: 1.5))
                .offset(y: phase >= 3 ? 0 : 30).opacity(phase >= 3 ? 1 : 0)
            }
        } animation: { phase in
            phase == 0 ? .easeOut(duration: 0.4).delay(0.6) : .spring(duration: 0.6, bounce: 0.25)
        }
    }

    // MARK: Page 3 — the orb listens, a question appears, then the answer (loops)

    private var askGhaf: some View {
        PhaseAnimator(reduceMotion ? [2] : [0, 1, 2, 2, 2]) { phase in
            VStack(spacing: 14) {
                GhafAIOrb(theme: theme, mood: phase == 1 ? .listening : .idle, level: 0)
                    .frame(width: 110, height: 110)
                    .scaleEffect(phase == 1 ? 1.08 : 1)
                HStack {
                    Spacer(minLength: 30)
                    Label(text("Lunch, 35 dirhams", "غدا بخمسة وثلاثين درهم"), systemImage: "waveform")
                        .font(GhafTypography.body(15, languageCode: languageCode, weight: .medium))
                        .foregroundStyle(theme.accentContrast)
                        .padding(14).background(theme.accent, in: RoundedRectangle(cornerRadius: 18))
                }
                .opacity(phase >= 1 ? 1 : 0).offset(y: phase >= 1 ? 0 : 16)
                HStack {
                    Text(text("Added: Lunch · AED 35.00", "تمت الإضافة: غداء · ٣٥٫٠٠ درهم"))
                        .font(GhafTypography.body(15, languageCode: languageCode))
                        .padding(14).background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.outline, lineWidth: 1))
                    Spacer(minLength: 30)
                }
                .opacity(phase >= 2 ? 1 : 0).offset(y: phase >= 2 ? 0 : 16)
            }
        } animation: { phase in
            phase == 0 ? .easeOut(duration: 0.3).delay(0.5) : .spring(duration: 0.55, bounce: 0.2).delay(0.35)
        }
    }

    // MARK: Page 3 — budget petals fill, upcoming subscriptions slide in

    private var subscriptionsAndPetals: some View {
        let fills: [CGFloat] = [0.9, 0.55, 0.75, 0.35, 0.6, 0.45]
        return VStack(spacing: 16) {
            ZStack {
                ForEach(fills.indices, id: \.self) { index in
                    let start = Double(index) * 60 - 90 + 2, end = Double(index + 1) * 60 - 90 - 2
                    GhafPetalSegment(start: start, end: end, inner: 0.22, outer: 1)
                        .fill(theme.primaryText.opacity(0.07))
                    GhafPetalSegment(start: start, end: end, inner: 0.22, outer: shown ? 0.22 + 0.78 * fills[index] : 0.24)
                        .fill(index == 0 ? theme.over : theme.accent.opacity(0.55 + 0.07 * Double(index)))
                        .animation(reduceMotion ? .none : .spring(duration: 0.9, bounce: 0.15).delay(0.08 * Double(index)), value: shown)
                }
            }
            .frame(width: 150, height: 150)
            VStack(spacing: 8) {
                subscriptionRow("play.tv.fill", text("Streaming", "البث"), text("Due in 3 days", "بعد ٣ أيام"), 39, index: 0)
                subscriptionRow("figure.run", text("Gym", "النادي"), text("Due next week", "الأسبوع القادم"), 250, index: 1)
            }
        }
    }

    private func subscriptionRow(_ icon: String, _ name: String, _ due: String, _ amount: Decimal, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.accent)
                .frame(width: 32, height: 32).background(theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                Text(due).font(GhafTypography.body(12, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            GhafMoneyLabel(amount: amount, currency: "AED", languageCode: languageCode, size: 15)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.outline, lineWidth: 1))
        .offset(y: shown ? 0 : 24).opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .none : .spring(duration: 0.6, bounce: 0.2).delay(0.5 + 0.12 * Double(index)), value: shown)
    }
}

/// Gentle continuous float for hero items.
private struct GhafFloat: ViewModifier {
    let amplitude: CGFloat
    let period: Double
    func body(content: Content) -> some View {
        if amplitude == 0 { content } else {
            content.phaseAnimator([false, true]) { view, up in
                view.offset(y: up ? -amplitude : amplitude)
            } animation: { _ in .easeInOut(duration: period / 2) }
        }
    }
}
