import SwiftUI

enum GhafTypography {
    static func display(_ size: CGFloat, languageCode: String) -> Font {
        if languageCode == "ar" {
            return .custom("ThmanyahSerifDisplay-Black", size: size, relativeTo: .largeTitle)
        }
        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .largeTitle)
            .weight(.heavy)
    }

    static func heading(_ size: CGFloat, languageCode: String) -> Font {
        if languageCode == "ar" {
            return .custom("ThmanyahSerifDisplay-Black", size: size, relativeTo: .title)
        }
        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .title)
            .weight(.bold)
    }

    static func body(
        _ size: CGFloat,
        languageCode: String,
        weight: Font.Weight = .regular
    ) -> Font {
        if languageCode == "ar" {
            let fontName: String
            if weight == .bold || weight == .heavy || weight == .black {
                fontName = "IBMPlexSansArabic-Bold"
            } else if weight == .semibold {
                fontName = "IBMPlexSansArabic-SemiBold"
            } else if weight == .medium {
                fontName = "IBMPlexSansArabic-Medium"
            } else {
                fontName = "IBMPlexSansArabic-Medium"
            }
            return .custom(fontName, size: size, relativeTo: .body)
        }

        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .body)
            .weight(weight == .regular ? .semibold : (weight == .medium ? .semibold : .bold))
    }

    /// Amounts use SF Pro Rounded: wide, friendly numerals that scan fast and animate cleanly.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight == .regular ? .medium : weight, design: .rounded)
    }
}

struct GhafScreenTitle: View {
    let title: String
    let subtitle: String?
    let languageCode: String
    let theme: GhafTheme
    /// For screens shown as a sheet: a 44pt close button level with the title.
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(GhafTypography.display(34, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, onClose == nil ? 0 : 48)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(theme.surface, in: Circle())
                        .shadow(color: theme.shadow, radius: 8, y: 3)
                }
                .buttonStyle(.ghafPress)
                .accessibilityLabel(languageCode == "ar" ? "إغلاق" : "Close")
            }
        }
        // Sheets put their grabber over the top 20pt; keep the title clear of it.
        .padding(.top, onClose == nil ? 0 : 16)
    }
}

struct GhafLaunchSplash: View {
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.12, blue: 0.095),
                        Color(red: 0.075, green: 0.22, blue: 0.16),
                        Color(red: 0.035, green: 0.095, blue: 0.075)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.78, green: 0.91, blue: 0.43).opacity(0.13))
                    .frame(width: proxy.size.width * 1.12)
                    .blur(radius: 58)
                    .offset(x: proxy.size.width * 0.40, y: -proxy.size.height * 0.22)

                VStack(spacing: 13) {
                    Text("غاف")
                        .font(.custom("ThmanyahSerifDisplay-Black", size: 94))
                        .foregroundStyle(Color(red: 0.97, green: 0.94, blue: 0.84))
                        .shadow(color: .black.opacity(0.16), radius: 16, y: 5)

                    Text("MONEY, WITH CLARITY")
                        .font(.custom("IBMPlexSans-Regular", size: 10).weight(.semibold))
                        .tracking(3.2)
                        .foregroundStyle(Color(red: 0.78, green: 0.86, blue: 0.72))
                }
                .scaleEffect(scale)
                .blur(radius: max(0, (1 - scale) * 11))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("غاف")
    }
}

extension View {
    /// More's pages (and Wallet): one big centred title in the bar's own row, next to the back button,
    /// so pages start with content instead of a second title row. Same look as Home and About Ghaf.
    func ghafPageTitle(_ title: String, languageCode: String, theme: GhafTheme) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(GhafTypography.display(24, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    /// Sheets don't inherit the app's Arabic right-to-left direction; set it again at each sheet's root.
    func ghafDirection(_ languageCode: String) -> some View {
        environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: languageCode))
    }
}

extension View {
    /// Screens that hide the navigation bar: fade content out under the status bar so text never
    /// scrolls behind the clock and battery.
    func ghafStatusBarFade(theme: GhafTheme) -> some View {
        overlay(alignment: .top) {
            GeometryReader { geometry in
                let top = geometry.safeAreaInsets.top, fade: CGFloat = 18
                LinearGradient(stops: [.init(color: theme.background, location: 0),
                                       .init(color: theme.background, location: top / (top + fade)),
                                       .init(color: theme.background.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: top + fade)
                    .offset(y: -top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
