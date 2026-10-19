import SwiftUI

// Runs the export's email-body fetches and shows progress.
//
// The fetches are serial by force: `MailScriptRunner` is one run-loop thread, FIFO, with no cancellation and
// no Swift-side timeout. So "Stop" stops ISSUING fetches — the one already in flight finishes on the script
// thread — and the sheet says so rather than implying it can abort Mail.
//
// The async bridge is `.task(id:)` + `withCheckedThrowingContinuation`, copying `ChatView`'s email-body
// load: `Swift.Task { }` is unusable in this module because `@Model final class Task` shadows it.
@MainActor
@Observable
final class TimesheetBodyRun {
    let messages: [EmailMessage]
    private(set) var completed = 0
    private(set) var currentSubject = ""
    private(set) var outcomes: [UUID: TimesheetEmailBody]
    private(set) var isFinished = false
    var isStopped = false
    /// Set when a failure applies to every remaining fetch (permission, Mail unavailable).
    private(set) var fatalMessage: String?

    var total: Int { messages.count }
    var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }

    init(messages: [EmailMessage], preSkipped: [UUID: TimesheetEmailBody]) {
        self.messages = messages
        self.outcomes = preSkipped
    }

    func record(_ outcome: TimesheetEmailBody, for id: UUID) {
        outcomes[id] = outcome
        completed += 1
    }
    func stopRemaining(from index: Int, reason: TimesheetEmailBody) {
        for message in messages[index...] where outcomes[message.id] == nil {
            outcomes[message.id] = reason
        }
    }
    func noteFatal(_ message: String) { fatalMessage = message }
    func finish() { isFinished = true }
    func setCurrent(_ subject: String) { currentSubject = subject }
}

struct TimesheetExportProgressSheet: View {
    @Bindable var run: TimesheetBodyRun
    let mailService: MailScriptService
    /// Called once with every outcome, whether the run completed or was stopped.
    let onFinish: ([UUID: TimesheetEmailBody]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading email bodies from Mail")
                .font(.headline)
            ProgressView(value: run.fraction) {
                Text("\(run.completed) of \(run.total)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !run.currentSubject.isEmpty {
                Text(run.currentSubject)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("One message at a time. Stopping leaves the remaining bodies out of the export — the "
                 + "message in flight still finishes.")
                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            if let fatal = run.fatalMessage {
                Text(fatal).font(.caption).foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Stop") { run.isStopped = true }
                    .disabled(run.isFinished)
            }
        }
        .padding()
        .frame(width: 420)
        .task(id: run.total) { await fetchAll() }
    }

    private func fetchAll() async {
        for (index, message) in run.messages.enumerated() {
            if run.isStopped {
                run.stopRemaining(from: index, reason: .skippedStopped)
                break
            }
            run.setCurrent(message.subject)
            do {
                let body = try await fetchBody(message)
                run.record(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           ? .failed("the message had no readable content")
                           : TimesheetContentTree.clamp(body),
                           for: message.id)
            } catch let error as MailScriptError {
                run.record(.failed(error.userMessage), for: message.id)
                if TimesheetBodyScope.isFatal(error) {
                    // Applies to every remaining fetch — stop rather than repeat it N times.
                    run.noteFatal(error.userMessage)
                    run.stopRemaining(from: index + 1, reason: .failed(error.userMessage))
                    break
                }
            } catch {
                run.record(.failed(error.localizedDescription), for: message.id)
            }
        }
        run.finish()
        onFinish(run.outcomes)
        dismiss()
    }

    private func fetchBody(_ message: EmailMessage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            mailService.fetchContent(message) { continuation.resume(with: $0) }
        }
    }
}
