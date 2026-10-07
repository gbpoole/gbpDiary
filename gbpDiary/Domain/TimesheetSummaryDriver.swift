import SwiftUI
import SwiftData
import Combine
import OSLog

// Invisible background driver for the Timesheet's per-project prose. Unlike the global email drivers this
// one is placed INSIDE `TimesheetView`, because what needs summarising depends on the period on screen.
//
// For every node of the current report it rephrases the app-assembled rows (`TimesheetReport.phrasingPrompt`
// — covering the node's whole subtree, so a parent reads as the project-level summary) on-device, one at a
// time, and caches the paragraph in a `TimesheetSummary` keyed by `(nodeID, interval)`. The model only ever
// rephrases: every figure on the page is computed by the app.
//
// It is debounced (so dragging a custom date picker doesn't start a generation storm), skips work whose
// cached paragraph is current, and touches what it shows so the five-week sweep keeps what you use.
struct TimesheetSummaryDriver: View {
    let nodes: [TimesheetNode]
    let interval: Range<Date>

    @Environment(\.modelContext) private var modelContext
    @Query private var stored: [TimesheetSummary]
    @State private var isRunning = false
    @State private var kick = 0
    private let summarizer = FoundationModelsSummarizer()
    private let log = Logger(subsystem: "gbpDiary", category: "TimesheetSummary")

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: workToken) { await run() }
            // Idle heartbeat: recover when Apple Intelligence transitions unavailable → available.
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                if !isRunning { kick &+= 1 }
            }
    }

    /// Changes when the period, the material, or the heartbeat changes — and cancels an in-flight debounce.
    private var workToken: String {
        let period = "\(interval.lowerBound.timeIntervalSinceReferenceDate)"
            + "-\(interval.upperBound.timeIntervalSinceReferenceDate)"
        let material = nodes.map { "\($0.id.uuidString):\(TimesheetSummaryPlanning.fingerprint(node: $0).count)" }
            .joined(separator: ",")
        return "\(period)|\(kick)|\(material.hashValue)"
    }

    private func run() async {
        guard !TestEnvironment.isRunningUnitTests else { return }
        // Debounce: a cancelled task (period still being adjusted) never reaches the model.
        try? await ContinuousClock().sleep(for: .milliseconds(500))
        guard !isRunning, summarizer.isAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        for node in nodes {
            guard summarizer.isAvailable else { break }
            let fingerprint = TimesheetSummaryPlanning.fingerprint(node: node)
            let record = existingRecord(for: node)
            // Seen on screen → survives the sweep. Only written when it has drifted by an hour, so the
            // 15-second heartbeat doesn't dirty the store on every tick.
            if let record, Date().timeIntervalSince(record.touchedAt) > 3600 { record.touchedAt = Date() }
            guard TimesheetSummaryPlanning.needsSummary(
                hasContent: !node.subtreeRows.isEmpty,
                state: record?.state,
                storedFingerprint: record?.sourceFingerprint,
                storedPromptVersion: record?.summaryPromptVersion,
                fingerprint: fingerprint) else { continue }
            await summarize(node, fingerprint: fingerprint, into: record)
        }
    }

    private func summarize(_ node: TimesheetNode, fingerprint: String, into existing: TimesheetSummary?) async {
        let record = existing ?? {
            let r = TimesheetSummary(nodeID: node.id, rangeStart: interval.lowerBound,
                                     rangeEnd: interval.upperBound)
            modelContext.insert(r)
            return r
        }()
        do {
            let text = try await summarizer.summarizeThread(prompt: TimesheetReport.phrasingPrompt(node: node))
            record.text = text
            record.state = .done
        } catch EmailSummaryError.modelUnavailable {
            return   // never a terminal state; the heartbeat retries when the model returns
        } catch {
            log.error("timesheet summary failed: \(error.localizedDescription, privacy: .public)")
            record.state = .failed
        }
        record.sourceFingerprint = fingerprint
        record.summaryPromptVersion = TimesheetSummaryPlanning.promptVersion
        record.touchedAt = Date()
    }

    private func existingRecord(for node: TimesheetNode) -> TimesheetSummary? {
        stored.first { $0.matches(nodeID: node.id, interval: interval) }
    }
}
