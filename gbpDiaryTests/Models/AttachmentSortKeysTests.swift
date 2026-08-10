import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct AttachmentSortKeysTests {
    private func makeImage(name: String) -> gbpDiary.Attachment {
        gbpDiary.Attachment(fileName: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), kind: .image)
    }

    @Test func libraryName_prefersDisplayNameThenFileName() {
        let a = makeImage(name: "photo.png")
        #expect(a.libraryName == "photo.png")   // no display name
        a.displayName = "Sunset"
        #expect(a.libraryName == "Sunset")
    }

    @Test func nameKey_isLowercasedLibraryName() {
        let a = makeImage(name: "Photo.PNG")
        #expect(a.nameKey == "photo.png")   // file name lowercased
        a.displayName = "Sunset Beach"
        #expect(a.nameKey == "sunset beach")
    }

    @Test func descriptionKey_isLowercasedOrEmpty() {
        let a = makeImage(name: "x.png")
        #expect(a.descriptionKey == "")   // nil description
        a.attachmentDescription = "Team Photo"
        #expect(a.descriptionKey == "team photo")
    }

    @Test func sizeSortKey_isBytesOrZero() {
        let a = makeImage(name: "x.png")
        #expect(a.sizeSortKey == 0)   // nil size
        a.fileSizeBytes = 2048
        #expect(a.sizeSortKey == 2048)
    }
}
