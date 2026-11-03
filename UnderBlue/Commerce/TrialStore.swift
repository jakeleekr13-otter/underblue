import Foundation
import Observation
import Security

/// What the free trial has used on this device. Kept in the Keychain (`KeychainTrialPersistence`).
/// Free exports carry a watermark (`Watermark`). Rules (Jake, 2 Nov 2026):
/// - Photos: the first `TrialPolicy.welcomePhotos` exports at any time, then one per `TrialPolicy.interval`.
/// - Videos: one per `TrialPolicy.interval`, first `TrialStore.videoSeconds` only, 1080p SDR.
struct TrialState: Codable, Equatable {
    /// How many of the welcome photos are used.
    var welcomePhotosUsed = 0
    /// The last free photo and video export, as absolute times. Nil: none yet.
    var lastPhoto: Date?
    var lastVideo: Date?
    var pending: String?

    init(welcomePhotosUsed: Int = 0, lastPhoto: Date? = nil, lastVideo: Date? = nil, pending: String? = nil) {
        self.welcomePhotosUsed = welcomePhotosUsed
        self.lastPhoto = lastPhoto
        self.lastVideo = lastVideo
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey {
        case welcomePhotosUsed, lastPhoto, lastVideo, pending
        // Up to 1.1.9 the trial was one photo and one video in total, saved as two flags.
        case photoUsed, videoUsed
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pending = try values.decodeIfPresent(String.self, forKey: .pending)
        lastPhoto = try values.decodeIfPresent(Date.self, forKey: .lastPhoto)
        lastVideo = try values.decodeIfPresent(Date.self, forKey: .lastVideo)
        if let used = try values.decodeIfPresent(Int.self, forKey: .welcomePhotosUsed) {
            welcomePhotosUsed = used
        } else {
            // The old free photo counts as one welcome photo, so 2 are left (Jake, 2 Nov 2026).
            // The old free video gives no wait: the daily video starts now.
            welcomePhotosUsed = try values.decodeIfPresent(Bool.self, forKey: .photoUsed) == true ? 1 : 0
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(welcomePhotosUsed, forKey: .welcomePhotosUsed)
        try values.encodeIfPresent(lastPhoto, forKey: .lastPhoto)
        try values.encodeIfPresent(lastVideo, forKey: .lastVideo)
        try values.encodeIfPresent(pending, forKey: .pending)
    }
}

/// The trial rules as pure functions of the state and the time, so tests can set the clock.
enum TrialPolicy {
    static let welcomePhotos = 3
    static let videoSeconds: Double = 10
    static let interval: TimeInterval = 24 * 60 * 60

    static func welcomePhotosLeft(_ state: TrialState) -> Int { max(0, welcomePhotos - state.welcomePhotosUsed) }

    /// When the next free export of this kind is allowed. Nil: allowed now.
    /// The wait counts from the last free export, in absolute time, so a time-zone change does nothing.
    /// A clock set back before the last export does not help: the wait still ends at last + interval.
    /// A clock set forward only takes the next day early: back on the real time, the wait is longer by the same amount.
    static func nextFree(_ kind: ImportedMedia.Kind, state: TrialState, now: Date) -> Date? {
        if kind == .photo, welcomePhotosLeft(state) > 0 { return nil }
        guard let last = kind == .photo ? state.lastPhoto : state.lastVideo else { return nil }
        let next = last.addingTimeInterval(interval)
        return now >= next ? nil : next
    }
}

protocol TrialPersistence {
    func read() throws -> TrialState
    func write(_ state: TrialState) throws
}
struct KeychainTrialPersistence: TrialPersistence {
    let service: String
    init(service: String = "com.underblue.trial.v1") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "local-trial", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> TrialState {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return TrialState() }
        guard status == errSecSuccess, let data = result as? Data,
              let state = try? JSONDecoder().decode(TrialState.self, from: data) else { throw UnderBlueError.trialUnavailable }
        return state
    }
    func write(_ state: TrialState) throws {
        let data = try JSONEncoder().encode(state)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw UnderBlueError.trialUnavailable }
        } else if status != errSecSuccess { throw UnderBlueError.trialUnavailable }
    }
}

@MainActor @Observable
final class TrialStore {
    static let videoSeconds = TrialPolicy.videoSeconds
    private(set) var state = TrialState()
    private(set) var available = false
    private let persistence: any TrialPersistence
    private let diagnostics: DiagnosticRecorder?
    private let now: () -> Date
    init(persistence: any TrialPersistence = KeychainTrialPersistence(), diagnostics: DiagnosticRecorder? = nil,
         now: @escaping () -> Date = Date.init) {
        self.diagnostics = diagnostics
        self.persistence = persistence
        self.now = now
        reload()
    }
    func reload() {
        do {
            var saved = try persistence.read()
            // A pending export from a terminated process produced no deliverable file.
            if saved.pending != nil { saved.pending = nil; try persistence.write(saved) }
            state = saved; available = true
        } catch {
            available = false
            let failure = Failure.classify(error, operation: .trial)
            Task { await diagnostics?.record(failure, operation: .trial) }
        }
    }
    var welcomePhotosLeft: Int { TrialPolicy.welcomePhotosLeft(state) }
    /// When the next free export of this kind is allowed. Nil: allowed now (or the trial can't be read).
    func nextFree(_ kind: ImportedMedia.Kind) -> Date? { TrialPolicy.nextFree(kind, state: state, now: now()) }
    func canExport(_ kind: ImportedMedia.Kind) -> Bool { available && state.pending == nil && nextFree(kind) == nil }
    /// Why a free export is not allowed now, for the Pro screen. Nil when it is allowed.
    func waitReason(_ kind: ImportedMedia.Kind) -> String? {
        guard available, let next = nextFree(kind) else { return nil }
        let wait = Self.formatWait(next.timeIntervalSince(now()))
        return kind == .photo ? String(localized: "Your next free photo is ready in \(wait). Pro exports without waiting or a watermark.")
            : String(localized: "Your next free video is ready in \(wait). Pro exports without waiting or a watermark.")
    }
    /// Hours and minutes, rounded up to the minute: "5 hr, 3 min".
    static func formatWait(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
    func reserve(_ kind: ImportedMedia.Kind) throws {
        guard canExport(kind) else { throw UnderBlueError.trialUnavailable }
        var next = state
        next.pending = kind == .photo ? "photo" : "video"
        try persistence.write(next); state = next
    }
    func commit(_ kind: ImportedMedia.Kind) throws {
        guard state.pending == (kind == .photo ? "photo" : "video") else { throw UnderBlueError.trialUnavailable }
        var next = state
        // Every free photo starts the wait, also a welcome one. So the first day gives 3 photos, not 4.
        if kind == .photo {
            if TrialPolicy.welcomePhotosLeft(next) > 0 { next.welcomePhotosUsed += 1 }
            next.lastPhoto = now()
        } else { next.lastVideo = now() }
        next.pending = nil
        try persistence.write(next); state = next
    }
    func rollback() throws {
        var next = state; next.pending = nil
        try persistence.write(next); state = next
    }
}
