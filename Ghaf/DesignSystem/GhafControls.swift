import SwiftUI

struct GhafPrimaryButton: View {
    let title: String
    let theme: GhafTheme
    let languageCode: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                .foregroundStyle(theme.accentContrast)
                .frame(maxWidth: .infinity, minHeight: GhafMetrics.buttonHeight)
                .background(theme.accent, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.ghafPress)
    }
}

struct GhafSecondaryButton: View {
    let title: String
    let theme: GhafTheme
    let languageCode: String
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .medium)) }
                Text(title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: symbol == nil ? 184 : 155)
            }
            .font(GhafTypography.body(17, languageCode: languageCode, weight: .medium))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 18)
            .frame(minHeight: GhafMetrics.compactButtonHeight)
            .background(theme.primaryText.opacity(theme.isDark ? 0.10 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.ghafPress)
    }
}

struct GhafFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += (x == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(Int, CGSize)]] = [[]]
        var rowWidths: [CGFloat] = [0], rowHeights: [CGFloat] = [0]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows.count - 1
            if !rows[current].isEmpty && rowWidths[current] + spacing + size.width > bounds.width {
                rows.append([]); rowWidths.append(0); rowHeights.append(0)
            }
            let row = rows.count - 1
            rowWidths[row] += (rows[row].isEmpty ? 0 : spacing) + size.width
            rowHeights[row] = max(rowHeights[row], size.height)
            rows[row].append((index, size))
        }
        var y = bounds.minY
        for row in rows.indices {
            var x = bounds.minX + (bounds.width - rowWidths[row]) / 2
            for (index, size) in rows[row] {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeights[row] - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeights[row] + spacing
        }
    }
}

struct GhafChecklistCard: View {
    let items: [String]
    let theme: GhafTheme
    let languageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(GhafTypography.body(17, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(theme.comfortable)
                    Text(item)
                        .font(GhafTypography.body(18, languageCode: languageCode))
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .ghafCard(theme: theme, radius: 24)
    }
}

struct GhafFormCard<Content: View>: View {
    let theme: GhafTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .ghafCard(theme: theme, radius: 24)
    }
}

struct GhafFormRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let theme: GhafTheme
    let languageCode: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            GhafIconBadge(symbol: icon, tint: tint, size: 40, theme: theme)
            Text(title).font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 12)
            trailing().font(GhafTypography.body(15, languageCode: languageCode)).foregroundStyle(theme.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 155, alignment: .trailing)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

struct GhafFormDivider: View {
    let theme: GhafTheme
    var inset: CGFloat = 58
    var body: some View { Divider().overlay(theme.outline).padding(.leading, inset) }
}

struct GhafFormMenuRow<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let theme: GhafTheme
    let languageCode: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu { content() } label: {
            GhafFormRow(icon: icon, tint: tint, title: title, theme: theme, languageCode: languageCode) {
                HStack(spacing: 7) {
                    Text(value)
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .bold)).opacity(0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct GhafFormToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool
    let theme: GhafTheme
    let languageCode: String

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                GhafIconBadge(symbol: icon, tint: tint, size: 40, theme: theme)
                Text(title).font(GhafTypography.body(16, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.primaryText)
            }
        }
        .toggleStyle(GhafToggleStyle(theme: theme, languageCode: languageCode))
        .frame(minHeight: 64)
    }
}

struct GhafFormDateRow: View {
    let icon: String
    let tint: Color
    let title: String
    @Binding var selection: Date
    @Binding var isExpanded: Bool
    let theme: GhafTheme
    let languageCode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Button {
                let change = { isExpanded.toggle() }
                if reduceMotion { change() } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.85), change) }
            } label: {
                GhafFormRow(icon: icon, tint: tint, title: title, theme: theme, languageCode: languageCode) {
                    HStack(spacing: 7) {
                        Text(selection.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: languageCode))))
                        Image(systemName: "chevron.forward").font(.system(size: 13, weight: .bold)).opacity(0.7)
                    }
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                DatePicker(title, selection: $selection, displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(theme.accent).labelsHidden()
                    .environment(\.colorScheme, theme.isDark ? .dark : .light)
                    .environment(\.locale, Locale(identifier: languageCode == "ar" ? "ar_AE" : "en_AE"))
                    .padding(.horizontal, 4).padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct GhafFormActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let theme: GhafTheme
    let languageCode: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GhafFormRow(icon: icon, tint: tint, title: title, theme: theme, languageCode: languageCode) {
                HStack(spacing: 7) {
                    Text(value)
                    Image(systemName: "chevron.forward").font(.system(size: 13, weight: .bold)).opacity(0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

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
                configuration.label.foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, alignment: .leading)
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
                        Capsule().fill(theme.primaryText.opacity(0.08))
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
                    Text(option.1).font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                        .foregroundStyle(selection == option.0 ? theme.accentContrast : theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: GhafMetrics.segmentedSegmentHeight)
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
        .frame(height: GhafMetrics.segmentedTrackHeight)
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
                        Text(value).foregroundStyle(theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 8)
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
            .font(GhafTypography.body(15, languageCode: languageCode, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(Capsule().fill(color.opacity(theme.isDark ? 0.22 : 0.14)))
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
                .labelsHidden().tint(theme.accent).environment(\.colorScheme, theme.isDark ? .dark : .light)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .ghafCard(theme: theme, radius: 16)
    }
}
