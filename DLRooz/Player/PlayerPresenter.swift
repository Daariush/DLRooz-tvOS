import AVKit
import Combine
import UIKit

/// Presents the system player (AVPlayerViewController), as Apple's TV guidelines recommend: the standard
/// transport bar, Siri Remote gestures, audio menu and info panel. App-specific options are added as
/// transport-bar menus, and subtitles are drawn by the app in the content overlay.
@MainActor
final class PlayerPresenter: NSObject, AVPlayerViewControllerDelegate {
    static let shared = PlayerPresenter()

    private var controller: PlayerController?
    private var playerVC: AVPlayerViewController?
    private var subtitleView: SubtitleOverlayView?
    private var bag = Set<AnyCancellable>()

    func present(_ controller: PlayerController) {
        guard let root = Self.topViewController() else { return }
        self.controller = controller
        let vc = AVPlayerViewController()
        vc.player = controller.player
        vc.delegate = self
        vc.allowsPictureInPicturePlayback = false
        // One subtitle button only: the app's own menu (site + SubDL/SubSource/OpenSubtitles). Allowing
        // no language hides the system subtitle button that the stream's text tracks would add.
        vc.allowedSubtitleOptionLanguages = ["zxx"]
        let overlay = SubtitleOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        if let content = vc.contentOverlayView {
            content.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: content.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        subtitleView = overlay
        playerVC = vc

        controller.$currentCues.receive(on: RunLoop.main).sink { [weak overlay] cues in
            overlay?.show(cues.map(\.text).joined(separator: "\n"))
        }.store(in: &bag)
        AppSettings.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak overlay] _ in
            DispatchQueue.main.async { overlay?.restyle() }
        }.store(in: &bag)
        controller.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] msg in
            self?.showError(msg)
        }.store(in: &bag)
        controller.onStateChange = { [weak self] in self?.rebuildMenus() }
        controller.onFinished = { [weak self] in self?.playerVC?.dismiss(animated: true) { self?.cleanUp() } }
        rebuildMenus()
        root.present(vc, animated: true)
    }

    // MARK: AVPlayerViewControllerDelegate

    nonisolated func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in self.cleanUp() }
    }

    private func cleanUp() {
        controller?.tearDown()
        controller = nil
        playerVC = nil
        subtitleView = nil
        bag.removeAll()
    }

    private func showError(_ message: String) {
        guard let vc = playerVC, vc.presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("باشه", "OK"), style: .default) { [weak self] _ in
            self?.controller?.errorMessage = nil
        })
        vc.present(alert, animated: true)
    }

    // MARK: Transport bar menus

    private func rebuildMenus() {
        guard let c = controller, let vc = playerVC else { return }
        var items: [UIMenuElement] = [subtitleMenu(c), syncMenu(c), qualityMenu(c), speedMenu(c), bufferMenu(c)]
        if c.nextEpisode != nil {
            items.append(UIAction(title: L("قسمت بعد", "Next Episode"), image: UIImage(systemName: "forward.end.fill")) { _ in
                Task { await c.playNext() }
            })
        }
        vc.transportBarCustomMenuItems = items
    }

    private func subtitleMenu(_ c: PlayerController) -> UIMenu {
        var site: [UIMenuElement] = [
            UIAction(title: L("خاموش", "Off"), state: c.subtitle == .off ? .on : .off) { _ in c.select(.off) },
        ]
        for t in c.siteTracks {
            site.append(UIAction(title: Self.siteLabel(t.label), state: c.subtitle == .site(t) ? .on : .off) { _ in c.select(.site(t)) })
        }
        var children: [UIMenuElement] = [UIMenu(title: L("زیرنویس‌های سایت", "From DLRooz"), options: .displayInline, children: site)]

        var online: [UIMenuElement] = []
        switch c.onlineState {
        case .idle:
            online.append(UIAction(title: L("کلید API را در تنظیمات وارد کنید", "Add API keys in Settings"), attributes: .disabled) { _ in })
        case .searching:
            online.append(UIAction(title: L("در حال جستجو…", "Searching…"), attributes: .disabled) { _ in })
        case .failed(let msg):
            online.append(UIAction(title: msg, attributes: .disabled) { _ in })
        case .done:
            if c.onlineResults.isEmpty {
                online.append(UIAction(title: L("چیزی پیدا نشد", "Nothing found"), attributes: .disabled) { _ in })
            }
            let grouped = Dictionary(grouping: c.onlineResults.prefix(60), by: \.language)
            for lang in grouped.keys.sorted(by: { Self.langRank($0) < Self.langRank($1) }) {
                let subs = grouped[lang] ?? []
                let actions: [UIMenuElement] = subs.map { s in
                    UIAction(title: s.release.nilIfBlank ?? s.source.rawValue, subtitle: s.source.rawValue,
                             state: c.subtitle == .online(s) ? .on : .off) { _ in c.select(.online(s)) }
                }
                online.append(UIMenu(title: "\(Self.langName(lang)) (\(subs.count))", children: actions))
            }
        }
        children.append(UIMenu(title: "SubDL · SubSource · OpenSubtitles", options: .displayInline, children: online))
        return UIMenu(title: L("زیرنویس", "Subtitles"), image: UIImage(systemName: "captions.bubble"), children: children)
    }

    private func syncMenu(_ c: PlayerController) -> UIMenu {
        let offset = String(format: "%+.1f", c.subtitleOffset)
        return UIMenu(title: L("هماهنگی زیرنویس (\(offset) ث)", "Subtitle Sync (\(offset)s)"), image: UIImage(systemName: "timer"), children: [
            UIAction(title: L("زودتر ۰٫۵ ثانیه", "0.5 s earlier"), image: UIImage(systemName: "minus")) { _ in c.shiftSubtitles(by: -0.5) },
            UIAction(title: L("دیرتر ۰٫۵ ثانیه", "0.5 s later"), image: UIImage(systemName: "plus")) { _ in c.shiftSubtitles(by: 0.5) },
            UIAction(title: L("زودتر ۲ ثانیه", "2 s earlier")) { _ in c.shiftSubtitles(by: -2) },
            UIAction(title: L("دیرتر ۲ ثانیه", "2 s later")) { _ in c.shiftSubtitles(by: 2) },
            UIAction(title: L("بازنشانی", "Reset"), image: UIImage(systemName: "arrow.counterclockwise")) { _ in c.shiftSubtitles(by: 0) },
        ])
    }

    private func qualityMenu(_ c: PlayerController) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(title: L("خودکار", "Automatic"), state: c.qualityKbps == nil ? .on : .off) { _ in c.setQuality(kbps: nil) },
        ]
        for (kbps, label) in c.qualityOptions {
            children.append(UIAction(title: label, state: c.qualityKbps == kbps ? .on : .off) { _ in c.setQuality(kbps: kbps) })
        }
        return UIMenu(title: L("کیفیت", "Quality"), image: UIImage(systemName: "sparkles.tv"), children: children)
    }

    private func speedMenu(_ c: PlayerController) -> UIMenu {
        let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
        return UIMenu(title: L("سرعت", "Speed"), image: UIImage(systemName: "speedometer"), children: speeds.map { s in
            UIAction(title: String(format: "%g×", s), state: c.speed == s ? .on : .off) { _ in c.setSpeed(s) }
        })
    }

    private func bufferMenu(_ c: PlayerController) -> UIMenu {
        let ahead = Int(c.bufferedAhead / 60)
        var children: [UIMenuElement] = [
            UIAction(title: L("الان \(N(ahead)) دقیقه بارگذاری شده", "\(ahead) min loaded ahead now"), attributes: .disabled) { _ in },
        ]
        for m in AppSettings.bufferOptions {
            children.append(UIAction(title: L("\(N(m)) دقیقه جلوتر", "\(m) minutes ahead"),
                                     state: AppSettings.shared.bufferMinutes == m ? .on : .off) { _ in c.setBuffer(minutes: m) })
        }
        return UIMenu(title: L("بافر", "Buffer"), image: UIImage(systemName: "arrow.down.circle"), children: children)
    }

    private static func siteLabel(_ label: String) -> String {
        switch label.trimmed {
        case "Farsi": return L("فارسی", "Persian")
        case "English": return L("انگلیسی", "English")
        case "English + Farsi": return L("انگلیسی + فارسی", "English + Persian")
        case "Farsi for Dub": return L("فارسی (دوبله)", "Persian (for dub)")
        default: return label
        }
    }

    private static func langName(_ code: String) -> String {
        switch code {
        case "fa": return L("فارسی", "Persian")
        case "en": return L("انگلیسی", "English")
        default: return Locale.current.localizedString(forLanguageCode: code) ?? code
        }
    }

    private static func langRank(_ code: String) -> Int {
        AppSettings.shared.onlineSubtitleLanguages.firstIndex(of: code) ?? 99
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Subtitle text drawn over the video, styled from Settings (size, colour, background box).
final class SubtitleOverlayView: UIView {
    private let label = UILabel()
    private var text = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.85),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -70),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String) {
        self.text = text
        restyle()
    }

    @MainActor
    func restyle() {
        let s = AppSettings.shared
        let size = 46 * CGFloat(s.subtitleSize) / 100
        let font = UIFont(name: "Vazirmatn-Bold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        paragraph.baseWritingDirection = .natural
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: s.subtitleColor.uiColor, .shadow: shadow, .paragraphStyle: paragraph,
            .strokeColor: UIColor.black, .strokeWidth: -2.0,
        ]
        if s.subtitleBackground > 0 {
            attrs[.backgroundColor] = UIColor.black.withAlphaComponent(CGFloat(s.subtitleBackground) / 100)
        }
        // Pad lines with thin spaces so the background box doesn't hug the glyphs.
        let padded = text.isEmpty ? "" : text.components(separatedBy: "\n").map { "\u{2009}\($0)\u{2009}" }.joined(separator: "\n")
        label.attributedText = NSAttributedString(string: padded, attributes: attrs)
    }
}
