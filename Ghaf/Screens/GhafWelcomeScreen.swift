import SwiftUI

/// Full-screen Ghaf introduction artwork. Supply the approved artwork as the
/// `GhafWelcomeArtwork` image in the asset catalog.
struct GhafWelcomeScreen: View {
    let languageCode: String
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: onContinue) {
                ZStack {
                    Color(red: 0.12, green: 0.16, blue: 0.15).ignoresSafeArea()
                    Image("GhafWelcomeArtwork")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                    Color.clear.contentShape(Rectangle())
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageCode == "ar" ? "متابعة إلى غاف" : "Continue to Ghaf")
            .accessibilityHint(languageCode == "ar" ? "اضغط للمتابعة" : "Tap anywhere to continue")
        }
        .ignoresSafeArea()
    }
}
