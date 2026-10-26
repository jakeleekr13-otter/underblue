import Foundation
import UniformTypeIdentifiers

/// Turns dropped or picked files and folders into queue items. It reads the files where they are and copies nothing.
enum MediaScanner {
    /// Photos and videos in `urls`. A folder is searched deeply. Hidden files and package contents are skipped.
    /// `skipped` counts files that are neither a photo nor a video. A folder counts only what it holds.
    /// @concurrent: a deep folder walk blocks, so it runs off the caller's actor (the main actor).
    @concurrent static func scan(_ urls: [URL]) async -> (media: [ImportedMedia], skipped: Int) {
        var media: [ImportedMedia] = []
        var skipped = 0
        var seen = Set<String>()
        func take(_ url: URL) {
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
            guard let kind = FileImport.kind(of: type) else { skipped += 1; return }
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            media.append(ImportedMedia(url: url, kind: kind, originalName: url.lastPathComponent))
        }
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
                // Sorted by path, so a folder always queues in the same order.
                let files = (walker?.compactMap { $0 as? URL } ?? [])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                files.forEach(take)
            } else {
                take(url)
            }
        }
        return (media, skipped)
    }
}
