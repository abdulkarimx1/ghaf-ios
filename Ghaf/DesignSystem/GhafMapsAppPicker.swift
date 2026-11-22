import SwiftUI
import SwiftData
import MapKit
import UIKit

/// Self-contained setting row; its caller decides where it appears in Customization.
struct GhafMapsAppPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var settings: GhafSettings

    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode,
                          systemIsDark: colorScheme == .dark)
    }

    private var options: [(id: String, title: String)] {
        var values: [(String, String)] = [("apple", ar ? "خرائط Apple" : "Apple Maps")]
        if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            values.append(("google", "Google Maps"))
        }
        if UIApplication.shared.canOpenURL(URL(string: "waze://")!) {
            values.append(("waze", "Waze"))
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(options, id: \.id) { option in
                Button {
                    settings.mapsAppPreference = option.id
                } label: {
                    HStack(spacing: 10) {
                        Text(option.title)
                        Spacer()
                        if settings.mapsAppPreference == option.id {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .font(GhafTypography.body(14, languageCode: settings.languageCode))
                    .foregroundStyle(settings.mapsAppPreference == option.id ? theme.accent : theme.primaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
    }

    @MainActor
    static func openDirections(to item: MKMapItem, preference: String) {
        let coordinate = item.placemark.coordinate
        switch preference {
        case "google":
            if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!),
               let url = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving") {
                UIApplication.shared.open(url)
                return
            }
        case "waze":
            if UIApplication.shared.canOpenURL(URL(string: "waze://")!),
               let url = URL(string: "waze://?ll=\(coordinate.latitude),\(coordinate.longitude)&navigate=yes") {
                UIApplication.shared.open(url)
                return
            }
        default: break
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
