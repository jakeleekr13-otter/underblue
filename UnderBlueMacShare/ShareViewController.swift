import AppKit
import SwiftUI

/// UnderBlue in the Mac share menu (Finder, Photos). It copies the shared photos or videos into the App Group inbox
/// (SharedInbox), then opens UnderBlue, which adds them to its queue.
/// The model and the view are shared with the iPhone extension (ShareModel.swift).
final class ShareViewController: NSViewController {
    private let model = ShareModel()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
        preferredContentSize = NSSize(width: 380, height: 300)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(model: model, open: { [weak self] in self?.openApp() },
                             done: { [weak self] in self?.done() }, cancel: { [weak self] in self?.cancel() })
        let host = NSHostingController(rootView: root.preferredColorScheme(.dark).tint(.mint))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        model.start(providers)
    }

    /// Opens UnderBlue through its `underblue://` address. If the Mac refuses, the share still waits in the inbox
    /// and UnderBlue picks it up the next time it becomes active.
    private func openApp() {
        if NSWorkspace.shared.open(SharedInbox.openURL) { done() } else { model.openFailed = true }
    }

    private func done() { extensionContext?.completeRequest(returningItems: nil) }
    private func cancel() {
        model.cancel()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
