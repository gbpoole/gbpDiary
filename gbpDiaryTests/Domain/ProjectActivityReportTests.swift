import Foundation
import Testing
@testable import gbpDiary

struct ProjectActivityReportTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: day))! }

    private func item(_ label: String, _ day: Int) -> ChatActivityItem {
        ChatActivityItem(date: d(day), label: label)
    }

    @Test func headerLine_showsHoursDaysWeeks() {
        let s = ProjectActivitySection(projectName: "NODES", hours: 15.2, distinctWeeks: 3,
                                       items: [item("Meeting: sprint (1h)", 3)])
        #expect(s.headerLine == "NODES — 15.2h · 2d · 3 weeks")   // 15.2 / 7.6 = 2d
    }

    @Test func render_headerThenBullets_sectionsInOrder() {
        let report = ProjectActivityReport(sections: [
            ProjectActivitySection(projectName: "NODES", hours: 12, distinctWeeks: 2,
                                   items: [item("Meeting: review (1h)", 3), item("Completed: EoI draft", 4)]),
            ProjectActivitySection(projectName: "Other", hours: 2, distinctWeeks: 1, items: []),
        ], interval: d(1)..<d(10))
        let text = report.render()
        #expect(text.contains("NODES — 12h"))
        #expect(text.contains("• Meeting: review (1h)"))
        #expect(text.contains("• Completed: EoI draft"))
        #expect(text.contains("Other — 2h"))              // a section with no items shows just its header
        #expect(text.range(of: "NODES")!.lowerBound < text.range(of: "Other")!.lowerBound)
    }

    @Test func sectionMatching_isCaseInsensitive() {
        let report = ProjectActivityReport(sections: [
            ProjectActivitySection(projectName: "NODES - 2026B", hours: 1, distinctWeeks: 1, items: []),
        ], interval: nil)
        #expect(report.section(matching: "nodes - 2026b")?.projectName == "NODES - 2026B")
        #expect(report.section(matching: "missing") == nil)
    }

    @Test func narrativeBlock_bulletsGroupedByProject_noTimeHeader_optionallyScoped() {
        let report = ProjectActivityReport(sections: [
            ProjectActivitySection(projectName: "NODES", hours: 12, distinctWeeks: 2,
                                   items: [item("Meeting: review (1h)", 3)]),
            ProjectActivitySection(projectName: "Other", hours: 2, distinctWeeks: 1, items: []),
        ], interval: nil)
        let all = report.narrativeBlock()
        #expect(all.contains("NODES:\n• Meeting: review (1h)"))
        #expect(!all.contains("12h"))                 // no time header — the report already states hours
        #expect(!all.contains("Other"))               // a section with no items contributes nothing
        // Scoped to one project returns only that project's bullets.
        #expect(report.narrativeBlock(projectName: "nodes") == "NODES:\n• Meeting: review (1h)")
        #expect(report.narrativeBlock(projectName: "missing") == "")
    }

    @Test func phrasingPrompt_isStrictRephraseOnly() {
        let s = ProjectActivitySection(projectName: "NODES", hours: 3, distinctWeeks: 1,
                                       items: [item("Meeting: review (1h)", 3)])
        let prompt = ProjectActivityReport.phrasingPrompt(section: s)
        #expect(prompt.contains("Use ONLY these items"))
        #expect(prompt.contains("do not add, infer, embellish, or omit"))
        #expect(prompt.contains("third person"))          // professional business tone, not casual
        #expect(prompt.contains("business tone"))
        #expect(prompt.contains("NODES"))
        #expect(prompt.contains("• Meeting: review (1h)"))
    }
}
