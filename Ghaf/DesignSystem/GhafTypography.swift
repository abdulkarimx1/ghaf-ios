import SwiftUI

enum GhafTypography {
    static func display(_ size: CGFloat, languageCode: String) -> Font {
        if languageCode == "ar" {
            return .custom("thmanyahserifdisplay-Black", size: size, relativeTo: .largeTitle)
        }
        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .largeTitle)
            .weight(.bold)
    }

    static func heading(_ size: CGFloat, languageCode: String) -> Font {
        if languageCode == "ar" {
            return .custom("thmanyahserifdisplay-Black", size: size, relativeTo: .title)
        }
        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .title)
            .weight(.semibold)
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
                fontName = "IBMPlexSansArabic-Regular"
            }
            return .custom(fontName, size: size, relativeTo: .body)
        }

        return .custom("IBMPlexSans-Regular", size: size, relativeTo: .body)
            .weight(weight)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("IBMPlexSans-Regular", size: size, relativeTo: .title)
            .weight(weight)
    }
}

struct GhafScreenTitle: View {
    let title: String
    let subtitle: String?
    let languageCode: String
    let theme: GhafTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(GhafTypography.display(31, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(GhafTypography.body(14, languageCode: languageCode))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.custom("thmanyahserifdisplay-Black", size: 94))
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
