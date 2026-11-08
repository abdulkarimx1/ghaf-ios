import SwiftUI

/// A complete, asset-independent welcome screen. The illustration is drawn in
/// SwiftUI so the launch experience can never degrade to a blank background
/// when an image asset is missing from the bundle.
struct GhafWelcomeScreen: View {
    let languageCode: String
    let onContinue: () -> Void

    private var isArabic: Bool { languageCode == "ar" }

    private let ink = Color(red: 0.055, green: 0.13, blue: 0.105)
    private let leaf = Color(red: 0.34, green: 0.57, blue: 0.39)
    private let sand = Color(red: 0.91, green: 0.84, blue: 0.68)
    private let mist = Color(red: 0.76, green: 0.82, blue: 0.72)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ink.ignoresSafeArea()

                // Architectural atmosphere: layered, low-contrast city contours.
                RadialGradient(
                    colors: [leaf.opacity(0.30), .clear],
                    center: .init(x: 0.78, y: 0.34),
                    startRadius: 8,
                    endRadius: proxy.size.width * 0.82
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, max(proxy.safeAreaInsets.top + 18, 34))

                    Spacer(minLength: 10)

                    cityIllustration
                        .frame(height: min(proxy.size.height * 0.43, 350))
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 15) {
                        Text(isArabic ? "أموالك، بصورة أوضح." : "Your money. In a clearer picture.")
                            .font(.system(size: isArabic ? 34 : 37, weight: .bold, design: .rounded))
                            .tracking(isArabic ? 0 : -1.4)
                            .lineSpacing(3)
                            .foregroundStyle(sand)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(isArabic
                             ? "كل حساباتك ومصروفاتك في مكان واحد. متابعة أبسط، وقرارات أوضح."
                             : "All your accounts and spending, brought together. Less manual tracking. Better visibility.")
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(6)
                            .foregroundStyle(mist.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                    Spacer(minLength: 26)

                    Button(action: onContinue) {
                        HStack(spacing: 12) {
                            Text(isArabic ? "ابدأ" : "Get started")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Image(systemName: isArabic ? "arrow.left" : "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(sand, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 26)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 18, 30))
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(leaf.opacity(0.22))
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(sand)
                }
                .frame(width: 38, height: 38)

                Text("GHAF")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(3.4)
                    .foregroundStyle(sand)
            }
            Spacer()
            Text(isArabic ? "الإمارات العربية المتحدة" : "UNITED ARAB EMIRATES")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(mist.opacity(0.78))
        }
    }

    private var cityIllustration: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                // Soft sun and horizon.
                Circle()
                    .fill(sand.opacity(0.10))
                    .frame(width: h * 0.68, height: h * 0.68)
                    .position(x: w * 0.72, y: h * 0.36)
                Circle()
                    .stroke(sand.opacity(0.22), lineWidth: 1)
                    .frame(width: h * 0.83, height: h * 0.83)
                    .position(x: w * 0.72, y: h * 0.36)

                UAECityLineArt()
                    .stroke(
                        LinearGradient(colors: [sand.opacity(0.9), leaf.opacity(0.82)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
                    )
                    .padding(.horizontal, 2)
                    .padding(.top, 12)

                VStack {
                    Spacer()
                    HStack {
                        Text(isArabic ? "الشارقة · دبي · أبوظبي" : "SHARJAH · DUBAI · ABU DHABI")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1.25)
                            .foregroundStyle(mist.opacity(0.65))
                        Spacer()
                        Text("01 / 07")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(mist.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .accessibilityLabel(isArabic ? "رسم خطي لأفق مدينة إماراتية" : "Line illustration of a UAE city skyline")
    }
}

private struct UAECityLineArt: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: w * x, y: h * y)
        }

        // Horizon and low-rise Emirati urban fabric.
        p.move(to: point(0.04, 0.83))
        p.addLine(to: point(0.96, 0.83))
        p.move(to: point(0.07, 0.83))
        p.addLine(to: point(0.07, 0.62))
        p.addLine(to: point(0.14, 0.62))
        p.addLine(to: point(0.14, 0.83))
        p.move(to: point(0.16, 0.83))
        p.addLine(to: point(0.16, 0.55))
        p.addLine(to: point(0.23, 0.55))
        p.addLine(to: point(0.23, 0.83))

        // Distinctive tapered tower silhouette.
        p.move(to: point(0.39, 0.83))
        p.addLine(to: point(0.43, 0.18))
        p.addQuadCurve(to: point(0.49, 0.18), control: point(0.46, 0.12))
        p.addLine(to: point(0.53, 0.83))
        p.move(to: point(0.43, 0.31))
        p.addLine(to: point(0.49, 0.31))
        p.move(to: point(0.42, 0.48))
        p.addLine(to: point(0.50, 0.48))
        p.move(to: point(0.41, 0.65))
        p.addLine(to: point(0.51, 0.65))

        // Curved sail-like tower.
        p.move(to: point(0.61, 0.83))
        p.addCurve(to: point(0.75, 0.83), control1: point(0.59, 0.53), control2: point(0.75, 0.38))
        p.addLine(to: point(0.75, 0.83))
        p.move(to: point(0.66, 0.83))
        p.addLine(to: point(0.66, 0.57))
        p.addLine(to: point(0.71, 0.57))
        p.addLine(to: point(0.71, 0.83))

        // Mosque dome and minaret as a subtle architectural cue.
        p.move(to: point(0.80, 0.83))
        p.addLine(to: point(0.80, 0.68))
        p.addQuadCurve(to: point(0.91, 0.68), control: point(0.855, 0.54))
        p.addLine(to: point(0.91, 0.83))
        p.move(to: point(0.94, 0.83))
        p.addLine(to: point(0.94, 0.49))
        p.addLine(to: point(0.96, 0.49))
        p.addLine(to: point(0.96, 0.83))
        p.move(to: point(0.935, 0.49))
        p.addLine(to: point(0.95, 0.44))
        p.addLine(to: point(0.965, 0.49))

        // Ground contours.
        p.move(to: point(0.03, 0.88))
        p.addQuadCurve(to: point(0.97, 0.88), control: point(0.50, 0.92))
        p.move(to: point(0.10, 0.94))
        p.addQuadCurve(to: point(0.90, 0.94), control: point(0.50, 0.97))
        return p
    }
}
