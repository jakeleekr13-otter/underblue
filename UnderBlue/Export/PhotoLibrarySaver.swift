import Photos

struct PhotoLibrarySaver {
    /// `fileName` is the name Photos keeps for the asset (ExportNaming). Without it Photos uses the temporary file's name.
    /// Asks for add-only access the first time. Throws `permission` when it is denied or restricted.
    static func requireAddAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw UnderBlueError.permission }
    }
    func save(_ url: URL, kind: ImportedMedia.Kind, fileName: String? = nil) async throws {
        try await Self.requireAddAccess()
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileName
            request.addResource(with: kind == .photo ? .photo : .video, fileURL: url, options: options)
        }
    }
}
