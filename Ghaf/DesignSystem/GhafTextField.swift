import SwiftUI
import UIKit

struct GhafTextField: View {
    @Binding var text: String
    let placeholder: String
    let theme: GhafTheme
    let languageCode: String
    var icon: String? = nil
    var multiline = false
    var clearable = true
    var keyboard: UIKeyboardType = .default
    var autocorrection = true
    var capitalization: TextInputAutocapitalization = .sentences
    var focusBinding: FocusState<Bool>.Binding? = nil
    var submitLabel: SubmitLabel? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).foregroundStyle(theme.secondaryText).accessibilityHidden(true)
            }
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .focused(focusBinding ?? $focused)
            .font(GhafTypography.body(16, languageCode: languageCode))
            .foregroundStyle(theme.primaryText)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(!autocorrection)
            .lineLimit(multiline ? 5 : 1)
            .submitLabel(submitLabel ?? .return)
            .onSubmit { onSubmit?() }
            if clearable && !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageCode == "ar" ? "مسح النص" : "Clear text")
            }
        }
        .ghafField(theme: theme, focused: focusBinding?.wrappedValue ?? focused)
    }
}

private extension View {
    func ghafField(theme: GhafTheme, focused: Bool) -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 56)
            .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focused ? theme.accent : theme.outline.opacity(0.8), lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
