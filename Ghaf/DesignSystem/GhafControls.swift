import SwiftUI

struct GhafToggleStyle: ToggleStyle {
    let theme: GhafTheme
    let languageCode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            let change = { configuration.isOn.toggle() }
            if reduceMotion { change() } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.78), change) }
        } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Text(configuration.isOn ? (languageCode == "ar" ? "مفعّل" : "On") : (languageCode == "ar" ? "متوقف" : "Off"))
                    if configuration.isOn { Image(systemName: "checkmark") }
                }
                .font(GhafTypography.body(13, languageCode: languageCode, weight: .bold))
                .foregroundStyle(configuration.isOn ? theme.accentContrast : theme.secondaryText)
                .frame(width: 66, height: 34)
                .background {
                    if configuration.isOn { Capsule().fill(theme.accent) }
                    else {
                        Capsule().fill(theme.elevatedSurface)
                        if theme.name != "Graphite" { Capsule().fill(theme.accent.opacity(theme.isDark ? 0.07 : 0.04)) }
                    }
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: configuration.isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? (languageCode == "ar" ? "مفعّل" : "On") : (languageCode == "ar" ? "متوقف" : "Off"))
    }
}

struct GhafSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    let theme: GhafTheme
    var languageCode = "en"
    @Namespace private var selectionAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    if reduceMotion { selection = option.0 }
                    else { withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { selection = option.0 } }
                } label: {
                    Text(option.1).font(GhafTypography.body(15, languageCode: languageCode, weight: .bold))
                        .foregroundStyle(selection == option.0 ? theme.accentContrast : theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            if selection == option.0 { Capsule().fill(theme.accent).matchedGeometryEffect(id: "selection", in: selectionAnimation) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule().fill(theme.elevatedSurface)
            if theme.name != "Graphite" { Capsule().fill(theme.accent.opacity(theme.isDark ? 0.07 : 0.04)) }
        }
    }
}

struct GhafMenuRow<Content: View>: View {
    let title: String
    let value: String
    let theme: GhafTheme
    let languageCode: String
    var compact = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu { content() } label: {
            Group {
                if compact {
                    HStack(spacing: 8) {
                        Text(value).foregroundStyle(theme.secondaryText)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(title).foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, alignment: .leading)
                        Text(value).foregroundStyle(theme.secondaryText)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .ghafCard(theme: theme, radius: 16)
                }
            }
            .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct GhafStatusChip: View {
    enum Kind { case working, waiting, notSetUp, failed }
    let kind: Kind
    let title: String
    let theme: GhafTheme
    let languageCode: String

    private var symbol: String {
        switch kind { case .working: "checkmark.circle"; case .waiting: "clock"; case .notSetUp: "circle.dashed"; case .failed: "xmark.circle" }
    }
    private var color: Color {
        switch kind { case .working: theme.comfortable; case .waiting: theme.close; case .notSetUp: theme.secondaryText; case .failed: theme.over }
    }
    var body: some View {
        Label(title, systemImage: symbol)
            .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

struct GhafDateRow: View {
    let title: String
    @Binding var selection: Date
    let components: DatePickerComponents
    let theme: GhafTheme
    let languageCode: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, alignment: .leading)
            DatePicker(title, selection: $selection, displayedComponents: components)
                .labelsHidden().tint(theme.accent)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .ghafCard(theme: theme, radius: 16)
    }
}
