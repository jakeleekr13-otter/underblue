import SwiftUI
import UniformTypeIdentifiers

/// UnderBlue in the share sheet. It copies the shared photos or video into the App Group inbox
/// (SharedInbox), then opens UnderBlue, which opens the share in the editor or the batch screen.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(model: model, open: { [weak self] in self?.openApp() },
                             done: { [weak self] in self?.done() }, cancel: { [weak self] in self?.cancel() })
        let host = UIHostingController(rootView: root.preferredColorScheme(.dark).tint(.mint))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        model.start(providers)
    }

    /// iOS has no public call for a share extension to open its app. The extension's UIApplication object is on
    /// the responder chain, so the extension asks it to open UnderBlue. If iOS refuses, the sheet stays open.
    private func openApp() {
        var responder: UIResponder? = self
        while let current = responder, !(current is UIApplication) { responder = current.next }
        guard let application = responder as? UIApplication else { model.openFailed = true; return }
        application.open(SharedInbox.openURL, options: [:]) { [weak self] opened in
            if opened { self?.done() } else { self?.model.openFailed = true }
        }
    }

    private func done() { extensionContext?.completeRequest(returningItems: nil) }
    private func cancel() {
        model.cancel()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
