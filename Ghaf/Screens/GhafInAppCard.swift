import SwiftUI
import UIKit

enum GhafInAppCardContent: Identifiable {
    case streak(days: Int)
    case announcement(GhafAnnouncement)

    var id: String {
        switch self {
        case .streak(let days): "streak-\(days)"
        case .announcement(let item): "announcement-\(item.id)"
        }
    }
}

struct GhafInAppCard: View {
    let content: GhafInAppCardContent
    let theme: GhafTheme
    let languageCode: String
    let onAction: () -> Void
    let onDismiss: () -> Void
    let onAppear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touched = false
    @State private var dragDistance: CGFloat = 0

    private var arabic: Bool { languageCode == "ar" }
    private var title: String {
        switch content {
        case .streak(let days): arabic ? "إنجاز \(GhafLocalization.arabicDays(days))!" : "\(days)-day streak!"
        case .announcement(let item): item.title
        }
    }
    private var message: String {
        switch content {
        case .streak(let days):
            arabic ? "سجّلت مصروفاتك لمدة \(GhafLocalization.arabicDays(days)) متتالية." : "You logged spending \(days) days in a row."
        case .announcement(let item): item.body
        }
    }
    private var actionTitle: String {
        switch content {
        case .streak: return arabic ? "عرض الإنجاز" : "View streak"
        case .announcement(let item):
            if item.code != nil { return arabic ? "نسخ الرمز" : "Copy code" }
            return arabic ? "تحديث التطبيق" : "Update"
        }
    }
    private var icon: String {
        switch content {
        case .streak: "checkmark.seal.fill"
        case .announcement(let item): item.code == nil ? "arrow.down.circle.fill" : "gift.fill"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 32)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    touched = true
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(arabic ? "إغلاق" : "Dismiss")
            }
            Text(title)
                .font(GhafTypography.heading(19, languageCode: languageCode).weight(.bold))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(message)
                .font(GhafTypography.body(14, languageCode: languageCode))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if case .announcement(let item) = content, let code = item.code {
                Text(code)
                    .font(GhafTypography.number(18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(theme.background, in: Capsule())
                    .accessibilityIdentifier("ghaf.in-app-card.voucher-code")
                    .accessibilityLabel(arabic ? "رمز القسيمة (code)" : "Voucher code (code)")
            }
            Button {
                touched = true
                onAction()
            } label: {
                Text(actionTitle)
                    .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                    .foregroundStyle(theme.accentContrast)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ghaf.in-app-card.action")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(theme.outline, lineWidth: 1))
        .shadow(color: theme.shadow.opacity(0.16), radius: 16, x: 0, y: 8)
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ghaf.in-app-card")
        .offset(y: dragDistance)
        .gesture(DragGesture(minimumDistance: 16).onChanged { value in
            touched = true
            if value.translation.height > 0 { dragDistance = value.translation.height }
        }.onEnded { value in
            if value.translation.height > 48 { onDismiss() }
            else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragDistance = 0 } }
        })
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: "\(title). \(message)")
            onAppear()
        }
        .task(id: content.id) {
            try? await Task.sleep(for: .seconds(8))
            if !touched { onDismiss() }
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}
