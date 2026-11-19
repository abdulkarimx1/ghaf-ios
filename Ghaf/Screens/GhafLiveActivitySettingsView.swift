import SwiftUI

/// More › Live Activity: choose whether the latest recorded purchase appears on the Lock Screen.
struct GhafLiveActivitySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let settings: GhafSettings
    @State private var isEnabled: Bool
    @State private var balance: GhafLiveActivityBalance

    init(settings: GhafSettings) {
        self.settings = settings
        _isEnabled = State(initialValue: GhafWidgetSync.liveActivityEnabled)
        _balance = State(initialValue: GhafWidgetSync.liveActivityBalance)
    }

    private var arabic: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(arabic ? "النشاط المباشر للمشتريات" : "Purchase Live Activity")
                .font(GhafTypography.heading(23, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(arabic ? "يعرض أحدث عملية تسجّلها لمدة خمس دقائق." : "Shows your latest logged transaction for five minutes.")
                .font(GhafTypography.body(14, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                selectionRow(arabic ? (isEnabled ? "النشاط المباشر · مفعّل" : "النشاط المباشر · متوقف")
                                    : (isEnabled ? "Live Activity · On" : "Live Activity · Off"), selected: isEnabled) {
                    isEnabled.toggle()
                }
                Divider().overlay(theme.outline)
                selectionRow(arabic ? "إجمالي الرصيد بالعملة نفسها" : "Total balance (same currency)", selected: balance == .total) {
                    balance = .total
                }
                Divider().overlay(theme.outline)
                selectionRow(arabic ? "رصيد البطاقة" : "Card balance", selected: balance == .card) {
                    balance = .card
                }
                Divider().overlay(theme.outline)
                selectionRow(arabic ? "إخفاء الرصيد" : "Hidden", selected: balance == .hidden) {
                    balance = .hidden
                }
            }
            .padding(.horizontal, 16)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(arabic ? "لن تُجمع أرصدة بعملات مختلفة. عند اختلاف العملات، سيظهر رصيد البطاقة فقط." : "Balances in different currencies are never added. If currencies differ, only the card balance is shown.")
                .font(GhafTypography.body(12, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .ghafScreenPadding()
        .padding(.top, 18)
        .frame(maxWidth: 620, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .ghafBackground(theme: theme)
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
        .onChange(of: isEnabled) { _, _ in savePreferences() }
        .onChange(of: balance) { _, _ in savePreferences() }
    }

    private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(GhafTypography.body(15, languageCode: settings.languageCode, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? theme.accent : theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func savePreferences() {
        GhafWidgetSync.setLiveActivityPreferences(enabled: isEnabled, balance: balance)
    }
}
