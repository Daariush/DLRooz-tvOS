import SwiftUI
import UIKit

/// tvOS selects a tab as soon as it gets focus, and clicking the tab you're already on tells SwiftUI
/// nothing. This listens for Select presses on the whole window and reports one whenever focus is on
/// the top tab bar, so the current tab can go back to its first page.
///
/// It doesn't depend on finding a UITabBarController (SwiftUI may not use one): it only checks whether
/// the focused view sits inside a tab bar. On tvOS focusing a tab selects it, so the clicked tab is
/// always the selected one.
struct TabBarClickObserver: UIViewRepresentable {
    let onClick: () -> Void

    func makeUIView(context: Context) -> Probe { Probe(onClick: onClick) }
    func updateUIView(_ view: Probe, context: Context) { view.onClick = onClick }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var onClick: () -> Void
        private static let name = "dlrooz.tabBarClick"

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            // One recognizer per window; a later probe takes over the callback.
            if let existing = window.gestureRecognizers?.first(where: { $0.name == Self.name }) {
                existing.removeTarget(nil, action: nil)
                existing.addTarget(self, action: #selector(clicked))
                existing.delegate = self
                return
            }
            let tap = UITapGestureRecognizer(target: self, action: #selector(clicked))
            tap.name = Self.name
            tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            tap.allowedTouchTypes = []
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        /// Is the focused view part of the top tab bar?
        private var focusIsOnTabBar: Bool {
            guard let focused = window?.windowScene?.focusSystem?.focusedItem as? UIView else { return false }
            var v: UIView? = focused
            while let current = v {
                if current is UITabBar || String(describing: type(of: current)).contains("TabBar") { return true }
                v = current.superview
            }
            return false
        }

        @objc private func clicked() { onClick() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            focusIsOnTabBar
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
