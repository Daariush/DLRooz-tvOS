import SwiftUI
import UIKit

/// tvOS selects a tab as soon as it gets focus, and clicking the tab you're already on tells SwiftUI
/// nothing. This watches clicks (Select on the Siri Remote) on the system tab bar itself and reports
/// which tab was clicked, so that tab can go back to its first page.
struct TabBarClickObserver: UIViewControllerRepresentable {
    let onClick: (Int) -> Void

    func makeUIViewController(context: Context) -> Probe { Probe(onClick: onClick) }
    func updateUIViewController(_ vc: Probe, context: Context) { vc.onClick = onClick }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var onClick: (Int) -> Void
        private static let name = "dlrooz.tabBarClick"

        init(onClick: @escaping (Int) -> Void) {
            self.onClick = onClick
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        private func attach() {
            guard let tabBar = findTabBarController()?.tabBar else { return }
            // One recognizer for the whole app; later probes just take over the callback.
            if let existing = tabBar.gestureRecognizers?.first(where: { $0.name == Self.name }) {
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
            tap.delegate = self
            tabBar.addGestureRecognizer(tap)
        }

        private func findTabBarController() -> UITabBarController? {
            if let t = tabBarController { return t }
            var vc = view.window?.rootViewController
            var queue: [UIViewController] = vc.map { [$0] } ?? []
            while !queue.isEmpty {
                vc = queue.removeFirst()
                if let t = vc as? UITabBarController { return t }
                queue += vc?.children ?? []
                if let p = vc?.presentedViewController { queue.append(p) }
            }
            return nil
        }

        @objc private func clicked() {
            guard let t = findTabBarController() else { return }
            onClick(t.selectedIndex)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
