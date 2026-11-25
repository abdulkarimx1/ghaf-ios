import SwiftUI
import UIKit

extension UIApplication {
    func ghafHideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// A "hide keyboard" button above the keyboard. Attach inside a NavigationStack's content.
    func ghafKeyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { UIApplication.shared.ghafHideKeyboard() } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel(Text("Hide keyboard"))
            }
        }
    }
}

/// Taps anywhere outside a text field close the keyboard, app-wide (sheets share the window).
/// Buttons keep working because the recognizer never cancels touches.
final class GhafKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = GhafKeyboardDismisser()
    private var installed = Set<ObjectIdentifier>()

    func install() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !installed.contains(ObjectIdentifier(window)) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
                installed.insert(ObjectIdentifier(window))
            }
        }
    }

    @objc private func dismiss() { UIApplication.shared.ghafHideKeyboard() }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

// MARK: Tab bar compaction (owner 1.31, row 5)

private struct GhafCompactsTabBar: ViewModifier {
    @Environment(GhafTabRouter.self) private var router
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
                guard abs(new - old) > 2 else { return }
                let compact = new > old && new > 40
                if compact != router.tabBarCompact { router.tabBarCompact = compact }
            }
        } else { content }
    }
}

extension View {
    /// Attach to a tab's main scroll view: scrolling down compacts the tab bar, scrolling up restores it.
    func ghafCompactsTabBar() -> some View { modifier(GhafCompactsTabBar()) }
}
