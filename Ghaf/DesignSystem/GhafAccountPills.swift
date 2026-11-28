import SwiftUI

struct GhafAccountPills: View {
    let accounts: [GhafAccount]
    let transactions: [GhafTransaction]
    @Binding var selection: UUID?
    let theme: GhafTheme
    let languageCode: String
    var excludingID: UUID? = nil
    var onSelection: ((UUID) -> Void)? = nil

    private var orderedAccounts: [GhafAccount] {
        let active = accounts.filter { !$0.isArchived }
        let counts = Dictionary(grouping: transactions.compactMap(\.accountID), by: { $0 }).mapValues(\.count)
        return active.enumerated().sorted {
            let left = counts[$0.element.id, default: 0], right = counts[$1.element.id, default: 0]
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedAccounts, id: \.id) { account in
                    let unavailable = account.id == excludingID
                    Button {
                        guard !unavailable else { return }
                        selection = account.id
                        onSelection?(account.id)
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(dotColor(account)).frame(width: 10, height: 10)
                            Text("\(account.name) · \(account.currency)")
                                .font(GhafTypography.body(14, languageCode: languageCode, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(selection == account.id ? theme.background : theme.primaryText)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(selection == account.id ? theme.primaryText : theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.outline.opacity(selection == account.id ? 0 : 0.55), lineWidth: 1))
                        .opacity(unavailable ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable)
                    .accessibilityAddTraits(selection == account.id ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel(languageCode == "ar" ? "الحساب" : "Account")
    }

    private func dotColor(_ account: GhafAccount) -> Color {
        guard let hex = GhafUAEBank.match([account.institution, account.name])?.colors.0 else { return theme.accent }
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
