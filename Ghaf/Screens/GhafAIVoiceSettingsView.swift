import SwiftUI

struct GhafAIVoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ghaf.ai.voiceCharacter") private var character = ""
    @State private var playingSample: String?
    let settings: GhafSettings
    var firstChoiceRequired = false
    var onChoose: (() -> Void)?

    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme { GhafTheme.resolve(name: settings.themeName, appearanceMode: "Dark", systemIsDark: true) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(firstChoiceRequired
                     ? (ar ? "من يرد عليك؟" : "Who should answer you?")
                     : (ar ? "صوت غاف" : "Ghaf voice"))
                    .font(GhafTypography.heading(26, languageCode: settings.languageCode))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                ForEach([("Hamad", "male"), ("Mariam", "female")], id: \.0) { name, voiceType in
                    VStack(spacing: 10) {
                        Button {
                            character = name
                            if firstChoiceRequired { onChoose?(); dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: character == name ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(character == name ? theme.accent : theme.secondaryText)
                                Text(name).font(GhafTypography.heading(18, languageCode: "en"))
                                Text(ar ? (voiceType == "male" ? "رجل" : "امرأة") : voiceType.capitalized)
                                    .font(GhafTypography.body(15, languageCode: settings.languageCode))
                                    .foregroundStyle(theme.secondaryText)
                                Spacer()
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(name), \(ar ? (voiceType == "male" ? "رجل" : "امرأة") : voiceType.capitalized)")
                            .accessibilityValue(character == name ? (ar ? "محدد" : "Selected") : (ar ? "غير محدد" : "Not selected"))
                            .accessibilityIdentifier("ghaf.voice.card.\(name)")
                            .accessibilityAddTraits(.isButton)
                            .foregroundStyle(theme.primaryText)
                            .padding(16)
                            .frame(minHeight: 64)
                            .background(character == name ? theme.accent.opacity(0.12) : theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(character == name ? theme.accent.opacity(0.55) : theme.outline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            sampleButton(name, language: "en", title: ar ? "إنجليزي" : "English")
                            sampleButton(name, language: "ar", title: ar ? "عربي" : "Arabic")
                        }
                    }
                }

                Text(ar ? "يجيبك غاف بهذا الصوت بالعربية والإنجليزية." : "Ghaf AI answers in this voice in English and Arabic.")
                        .font(GhafTypography.body(13, languageCode: settings.languageCode))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("ghaf.voice.footnote")
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                if !firstChoiceRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ar ? "إغلاق" : "Close") { dismiss() }
                    }
                }
            }
        }
    }

    private func sampleButton(_ name: String, language: String, title: String) -> some View {
        let sampleID = "\(name)-\(language)"
        let isPlaying = playingSample == sampleID
        return Button {
            if isPlaying {
                GhafCloudVoice.shared.stop()
                playingSample = nil
                return
            }
            playingSample = sampleID
            let text = language == "ar" ? "هلا، أنا \(name). كيف أقدر أساعدك اليوم؟" : "Hi, I'm \(name). How can I help you today?"
            Task {
                let started = await GhafCloudVoice.shared.speak(text, arabic: language == "ar", character: name,
                    onStart: {}, onFinish: { playingSample = nil })
                if !started { playingSample = nil }
            }
        } label: {
            Label(isPlaying ? (ar ? "إيقاف" : "Stop") : title, systemImage: isPlaying ? "stop.fill" : "play.fill")
                .font(GhafTypography.body(14, languageCode: settings.languageCode, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!GhafCloudAI.isEnabled || (playingSample != nil && !isPlaying))
        .opacity(GhafCloudAI.isEnabled ? 1 : 0.4)
    }
}
