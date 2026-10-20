import Foundation

/// Where the batch engine puts a finished file.
protocol BatchSink: Sendable {
    /// Takes the finished file and returns the name it was stored under.
    /// A sink must not overwrite an existing file. It picks another name instead.
    func deliver(_ file: URL, fileName: String, kind: ImportedMedia.Kind) async throws -> String
}

/// Moves finished files into a folder. A name that is already taken gets a number (`_2`, `_3`).
struct DirectorySink: BatchSink {
    let directory: URL

    func deliver(_ file: URL, fileName: String, kind: ImportedMedia.Kind) async throws -> String {
        // A folder the user picked in a sandboxed app needs this call. It is harmless for other folders.
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = ExportNaming.unique(fileName) { manager.fileExists(atPath: directory.appendingPathComponent($0).path) }
        try manager.moveItem(at: file, to: directory.appendingPathComponent(name))
        return name
    }
}

/// Saves finished files to the Photos library. The temporary file stays where it is; the engine removes it.
struct PhotosSink: BatchSink {
    func deliver(_ file: URL, fileName: String, kind: ImportedMedia.Kind) async throws -> String {
        try await PhotoLibrarySaver().save(file, kind: kind, fileName: fileName)
        return fileName
    }
}
