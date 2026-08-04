import SwiftUI
import SwiftData
import Combine
import OSLog

// Invisible, global background driver (placed once in WorkspaceView). Summarises pending emails
// on-device, one at a time. Async is bridged via the `.task` modifier + `withCheckedThrowingContinuation`
// because the `Task` type is shadowed by the `@Model final class Task`. Nothing leaves the device: the
// body is read from local Mail, summarised by the on-device model, and discarded (only `summary` is kept).
//
// Availability is transient (Apple Intelligence off / model downloading), so we NEVER mark an email
// terminally "unavailable": when the model isn't ready we leave it `pending`. A steady idle-kick timer
// re-runs the queue, so summaries begin automatically once the model becomes available — no restart.
struct EmailSummaryDriver: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pending: [EmailMessage]
    @State private var mailService = MailScriptService()
    @State private var kick = 0
    @State private var isRunning = false
    private let summarizer = FoundationModelsSummarizer()
    private let log = Logger(subsystem: "gbpDiary", category: "EmailSummary")

    init() {
        let pendingRaw = EmailSummaryState.pending.rawValue
        _pending = Query(
            filter: #Predicate<EmailMessage> { $0.summaryState == pendingRaw && !$0.dismissed },
            sort: \EmailMessage.date, order: .reverse
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            // `id: kick` so mutating emails mid-run does NOT cancel the loop (only an explicit kick re-runs).
            .task(id: kick) { await runQueue() }
            // Idle heartbeat: while emails remain and we're not already running, re-run. This recovers
            // when the model transitions unavailable → available, and picks up freshly-fetched emails.
            .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
                if !pending.isEmpty && !isRunning { kick &+= 1 }
            }
            .onAppear { requeueStuckUnavailable() }
    }

    private func runQueue() async {
        guard !isRunning, summarizer.isAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        // Snapshot the pending set; mutating models won't cancel this task (id is `kick`, unchanged here).
        for email in pending {
            guard summarizer.isAvailable else { break }
            guard email.summaryState == EmailSummaryState.pending.rawValue else { continue }
            await summarizeOne(email)
        }
    }

    private func summarizeOne(_ email: EmailMessage) async {
        let body: String
        do {
            body = try await fetchBody(email)
        } catch {
            log.error("Body fetch failed: \(error.localizedDescription, privacy: .public)")
            email.summaryState = EmailSummaryState.failed.rawValue
            return
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            email.summaryState = EmailSummaryState.failed.rawValue
            return
        }
        do {
            let text = try await summarizer.summarize(
                subject: email.subject,
                from: email.fromName?.isEmpty == false ? email.fromName! : email.fromAddress,
                body: trimmed
            )
            email.summary = text.isEmpty ? nil : text
            email.summaryState = (text.isEmpty ? EmailSummaryState.failed : .done).rawValue
        } catch {
            log.error("Summarise failed: \(error.localizedDescription, privacy: .public)")
            email.summaryState = EmailSummaryState.failed.rawValue
        }
    }

    // Bridge the completion-handler Mail bridge to async (no `Task {}` — we're inside `.task`).
    private func fetchBody(_ email: EmailMessage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            mailService.fetchContent(email) { continuation.resume(with: $0) }
        }
    }

    // One-time cleanup: earlier builds terminally marked emails "unavailable" on a transient outage.
    // Re-queue them so they summarise now that availability is retried.
    private func requeueStuckUnavailable() {
        let unavailable = EmailSummaryState.unavailable.rawValue
        let descriptor = FetchDescriptor<EmailMessage>(
            predicate: #Predicate { $0.summaryState == unavailable }
        )
        guard let stuck = try? modelContext.fetch(descriptor), !stuck.isEmpty else { return }
        for email in stuck { email.summaryState = EmailSummaryState.pending.rawValue }
    }
}
