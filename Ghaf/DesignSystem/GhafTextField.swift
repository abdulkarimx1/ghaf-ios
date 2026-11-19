import SwiftUI
import UIKit

struct GhafTextField: View {
    @Binding var text: String
    let placeholder: String
    let theme: GhafTheme
    let languageCode: String
    var icon: String? = nil
    var label: String? = nil
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
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label).font(GhafTypography.body(13, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
            }
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).foregroundStyle(theme.secondaryText).accessibilityHidden(true) }
                Group {
                    if multiline { TextField(placeholder, text: $text, axis: .vertical) }
                    else { TextField(placeholder, text: $text) }
                }
                .focused(focusBinding ?? $focused)
                .font(GhafTypography.body(17, languageCode: languageCode))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrection)
                .lineLimit(multiline ? 5 : 1)
                .submitLabel(submitLabel ?? .return)
                .onSubmit { onSubmit?() }
                if clearable && !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(languageCode == "ar" ? "مسح النص" : "Clear text")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: label == nil ? 56 : 64)
        .ghafGlassShape(theme: theme, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: theme.surface)
        .overlay {
            if focusBinding?.wrappedValue ?? focused {
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.accent, lineWidth: 1.5).allowsHitTesting(false)
            }
        }
    }
}

