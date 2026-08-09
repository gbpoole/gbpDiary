import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct PersonSortKeysTests {
    @Test func nameKey_isLowercased() {
        #expect(Person(name: "Zoe").nameKey == "zoe")
    }

    @Test func emailKey_isPrimaryLowercasedOrEmpty() {
        let p = Person(name: "P")
        #expect(p.emailKey == "")   // no emails
        p.emails = ["First@Example.com", "second@example.com"]
        #expect(p.emailKey == "first@example.com")   // primary (first), lowercased
    }

    @Test func institutionKey_isLowercasedOrEmpty() {
        let p = Person(name: "P")
        #expect(p.institutionKey == "")   // no institution
        p.institution = Institution(name: "Swinburne")
        #expect(p.institutionKey == "swinburne")
    }

    @Test func tagsKey_isLowercasedJoin() {
        let p = Person(name: "P")
        #expect(p.tagsKey == "")   // no tags
        p.tags = ["Alpha", "Beta"]
        #expect(p.tagsKey == "alpha, beta")
    }

    @Test func projectCount_sumsDevAndSci() {
        let p = Person(name: "P")
        #expect(p.projectCount == 0)
        p.devProjects = [Project(name: "a"), Project(name: "b")]
        p.sciProjects = [Project(name: "c")]
        #expect(p.projectCount == 3)
    }
}
