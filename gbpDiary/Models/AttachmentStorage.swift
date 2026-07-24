import Foundation

// Manages the on-disk location for copied attachment files.
//
// All imported files are copied into the app container so they are always accessible
// without security-scoped bookmark resolution, and so the same path works on iOS.
//
// iCloud migration: when the ubiquity container is configured, uncomment the
// `url(forUbiquityContainerIdentifier:)` block below and run a one-time migration
// that moves existing files from the local directory to the iCloud container.
enum AttachmentStorage {

    static var attachmentsDirectory: URL {
        // Future iCloud path — enable when cloudKitContainerIdentifier is added:
        // if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
        //     .appendingPathComponent("Documents/Attachments") {
        //     try? FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        //     return iCloud
        // }

        let base: URL
        #if os(macOS)
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("Attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Copies the file at `sourceURL` into the attachments directory.
    // The destination filename is `<fileId>.<ext>` to guarantee uniqueness.
    static func store(from sourceURL: URL, fileId: UUID) throws -> URL {
        let dest = attachmentsDirectory
            .appendingPathComponent(fileId.uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }

    static func delete(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
