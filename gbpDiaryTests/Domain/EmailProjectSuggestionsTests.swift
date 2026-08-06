import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailProjectSuggestions")
struct EmailProjectSuggestionsTests {
    private let p1 = ProjectRef(id: UUID(), name: "NODES")
    private let p2 = ProjectRef(id: UUID(), name: "IMOS")
    private let p3 = ProjectRef(id: UUID(), name: "ADACS")
    private var all: [ProjectRef] { [p1, p2, p3] }

    @Test func rank_aiFirstThenPriorThenSender() {
        let input = EmailProjectSuggestions.Input(
            assignedIDs: [], senderProjectIDs: [p1.id], priorProjectIDs: [p2.id], aiSuggestedID: p3.id)
        let out = EmailProjectSuggestions.rank(input, projects: all)
        #expect(out.map(\.name) == ["ADACS", "IMOS", "NODES"])   // AI(100) > prior(10) > sender(1)
    }

    @Test func rank_priorFrequencyAccumulates() {
        let input = EmailProjectSuggestions.Input(
            assignedIDs: [], senderProjectIDs: [], priorProjectIDs: [p1.id, p2.id, p1.id], aiSuggestedID: nil)
        let out = EmailProjectSuggestions.rank(input, projects: all)
        #expect(out.first?.name == "NODES")   // p1 seen twice → higher
    }

    @Test func rank_excludesAlreadyAssigned() {
        let input = EmailProjectSuggestions.Input(
            assignedIDs: [p1.id], senderProjectIDs: [p1.id], priorProjectIDs: [], aiSuggestedID: p1.id)
        let out = EmailProjectSuggestions.rank(input, projects: all)
        #expect(!out.contains(p1))
    }

    @Test func rank_capsAndIgnoresUnknownIDs() {
        let unknown = UUID()
        let input = EmailProjectSuggestions.Input(
            assignedIDs: [], senderProjectIDs: [unknown], priorProjectIDs: [p1.id, p2.id, p3.id], aiSuggestedID: nil)
        let out = EmailProjectSuggestions.rank(input, projects: all, limit: 2)
        #expect(out.count == 2)
        #expect(!out.contains { $0.id == unknown })
    }
}
