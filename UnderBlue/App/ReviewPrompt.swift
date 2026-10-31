import Foundation
import Network
import StoreKit
import SwiftUI
import os

/// Asks for an App Store rating once the user has saved 10 exports to Photos (Jake, 31 Oct 2026).
/// Only online: the app works offline, and a rating sheet with no network would look broken.
/// At most once per app version. StoreKit still decides whether the sheet appears (at most 3 times in 365 days).
struct ReviewPrompt {
    static let savesKey = "reviewPrompt.saves"
    static let askedVersionKey = "reviewPrompt.askedVersion"
    static let savesBeforeAsking = 10
    private let defaults: UserDefaults
    private let version: String

    init(defaults: UserDefaults = .standard,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
        self.defaults = defaults
        self.version = version
    }

    var saves: Int { defaults.integer(forKey: Self.savesKey) }
    func recordSaves(_ count: Int) {
        guard count > 0 else { return }
        defaults.set(saves + count, forKey: Self.savesKey)
    }
    func shouldAsk(online: Bool) -> Bool {
        online && saves >= Self.savesBeforeAsking && defaults.string(forKey: Self.askedVersionKey) != version
    }

    func markAsked() { defaults.set(version, forKey: Self.askedVersionKey) }

    /// Call after the "Saved to Photos" notice closes, so the sheet never covers a running task.
    @MainActor
    func askIfDue(_ requestReview: RequestReviewAction) async {
        guard shouldAsk(online: true), await Self.isOnline() else { return }
        markAsked()
        requestReview()
    }

    /// One reading of the current network path. A path that is up counts as online.
    static func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let answered = OSAllocatedUnfairLock(initialState: false)
            monitor.pathUpdateHandler = { path in
                guard answered.withLock({ done in defer { done = true }; return !done }) else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "com.underblue.app.review-online"))
        }
    }
}
