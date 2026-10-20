import Foundation
#if os(iOS)
import UIKit
#endif

/// Asks the system for extra time to finish a save or export when the app leaves the screen.
/// iOS grants a short background window. macOS does not suspend a running app, so it needs nothing.
@MainActor
struct BackgroundTask {
    #if os(iOS)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    /// `onExpire` runs when the system is about to end the extra time.
    mutating func begin(_ name: String, onExpire: @escaping @Sendable () -> Void) {
        #if os(iOS)
        identifier = UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: onExpire)
        #endif
    }

    mutating func end() {
        #if os(iOS)
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        #endif
    }
}
