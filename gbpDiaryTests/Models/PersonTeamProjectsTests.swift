import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct PersonTeamProjectsTests {
    @Test func teamProjects_unionsDevAndSci() {
        let p = Person(name: "P")
        let a = Project(name: "Alpha"); let b = Project(name: "Beta")
        p.devProjects = [a]
        p.sciProjects = [b]
        #expect(p.teamProjects.map(\.name) == ["Alpha", "Beta"])
    }

    @Test func teamProjects_dedupesWhenOnBothTeams() {
        let p = Person(name: "P")
        let a = Project(name: "Alpha")
        p.devProjects = [a]
        p.sciProjects = [a]   // same project on both teams
        #expect(p.teamProjects.count == 1)
        #expect(p.teamProjects.first?.id == a.id)
    }

    @Test func teamProjects_sortedByName() {
        let p = Person(name: "P")
        p.devProjects = [Project(name: "Zeta"), Project(name: "alpha")]
        p.sciProjects = [Project(name: "Mu")]
        #expect(p.teamProjects.map(\.name) == ["alpha", "Mu", "Zeta"])   // case-insensitive order
    }

    @Test func teamProjects_emptyWhenNoTeams() {
        #expect(Person(name: "P").teamProjects.isEmpty)
    }
}
