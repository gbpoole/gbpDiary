import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct ContentNoteSortKeysTests {
    @Test func titleKey_isLowercased() {
        let n = Note(title: "Design Notes")
        #expect(n.titleKey == "design notes")
    }

    @Test func tagsKey_isLowercasedJoinOrEmpty() {
        let n = Note(title: "N")
        #expect(n.tagsKey == "")   // no tags
        n.tags = ["Alpha", "Beta"]
        #expect(n.tagsKey == "alpha, beta")
    }

    @Test func projectKey_isLowercasedOrEmpty() {
        let n = Note(title: "N")
        #expect(n.projectKey == "")   // no project
        n.project = Project(name: "Cosmology")
        #expect(n.projectKey == "cosmology")
    }
}

@MainActor
struct InstitutionSortKeysTests {
    @Test func nameKey_isLowercased() {
        #expect(Institution(name: "Swinburne").nameKey == "swinburne")
    }

    @Test func memberCount_countsMembers() {
        let inst = Institution(name: "I")
        #expect(inst.memberCount == 0)
        inst.members = [Person(name: "a"), Person(name: "b")]
        #expect(inst.memberCount == 2)
    }

    @Test func projectCount_countsProjects() {
        let inst = Institution(name: "I")
        #expect(inst.projectCount == 0)
        inst.projects = [Project(name: "a"), Project(name: "b"), Project(name: "c")]
        #expect(inst.projectCount == 3)
    }
}
