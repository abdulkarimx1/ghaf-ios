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
