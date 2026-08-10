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
    @Query private var allPeople: [Person]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @State private var mailService = MailScriptService()
    @State private var kick = 0
    @State private var isRunning = false
    private let summarizer = FoundationModelsSummarizer()
    private let log = Logger(subsystem: "gbpDiary", category: "EmailSummary")

    init() {
        // Needs a summary: non-dismissed AND (pending, OR done with a stale prompt version → re-summarise).
        let pendingRaw = EmailSummaryState.pending.rawValue
        let doneRaw = EmailSummaryState.done.rawValue
        let currentVersion = EmailSummaryPrompt.promptVersion
        _pending = Query(
            filter: #Predicate<EmailMessage> {
                !$0.dismissed && ($0.summaryState == pendingRaw
                    || ($0.summaryState == doneRaw && $0.summaryPromptVersion < currentVersion))
            },
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
            let state = EmailSummaryState(rawValue: email.summaryState) ?? .pending
            guard EmailSummaryPlanning.needsSummary(state: state, dismissed: email.dismissed,
                                                    version: email.summaryPromptVersion) else { continue }
            await summarizeOne(email)
        }
    }

    private func summarizeOne(_ email: EmailMessage) async {
        let body: String
        do {
            body = try await fetchBody(email)
        } catch {
            log.error("Body fetch failed: \(error.localizedDescription, privacy: .public)")
            if needsSummary(email) { email.summaryState = EmailSummaryState.failed.rawValue }
            return
        }
        guard needsSummary(email) else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            email.summaryState = EmailSummaryState.failed.rawValue
            return
        }
        do {
            let text = try await summarizer.summarize(
                context: makeContext(for: email),
                subject: email.subject,
                body: trimmed
            )
            guard needsSummary(email) else { return }
            email.summary = text.isEmpty ? nil : text
            email.summaryState = (text.isEmpty ? EmailSummaryState.failed : .done).rawValue
            email.summaryPromptVersion = EmailSummaryPrompt.promptVersion
            await pickProject(for: email, summary: text)
        } catch {
            log.error("Summarise failed: \(error.localizedDescription, privacy: .public)")
            if needsSummary(email) { email.summaryState = EmailSummaryState.failed.rawValue }
        }
    }

    private func needsSummary(_ email: EmailMessage) -> Bool {
        let state = EmailSummaryState(rawValue: email.summaryState) ?? .pending
        return EmailSummaryPlanning.needsSummary(state: state, dismissed: email.dismissed,
                                                 version: email.summaryPromptVersion)
    }

    // Best-effort on-device project pick for triage suggestions (never auto-applied). Skipped when
    // there are no projects or the email is already filed.
    private func pickProject(for email: EmailMessage, summary: String) async {
        guard email.projects.isEmpty, !allProjects.isEmpty, !summary.isEmpty else { return }
        let names = allProjects.map(\.name)
        if let name = await summarizer.suggestProjectName(summary: summary, projectNames: names),
           let project = allProjects.first(where: { $0.name == name }) {
            email.suggestedProjectID = project.id
        }
    }

    // System context for the prompt: the user ("me"), the other party, direction, and a known-people roster.
    private func makeContext(for email: EmailMessage) -> SummaryContext {
        let mePerson = AppSettingsStore.myPersonID.flatMap { id in allPeople.first { $0.id == id } }
        let me = mePerson.map { SummaryPerson(name: $0.name, emails: $0.emails) }
        let other = email.person.map { SummaryPerson(name: $0.name, emails: $0.emails) }

        // Priority roster members: the other party + anyone on a team of one of the email's projects.
        var priorityIDs = Set<UUID>()
        if let p = email.person { priorityIDs.insert(p.id) }
        for project in email.projects {
            for person in project.devTeam + project.sciTeam { priorityIDs.insert(person.id) }
        }
        let meID = mePerson?.id
        let candidates = allPeople
            .filter { $0.id != meID }   // "me" is identified separately as "you"
            .map { person in
                EmailSummaryRoster.Candidate(id: person.id, name: person.name, emails: person.emails,
                                             isPriority: priorityIDs.contains(person.id))
            }
        let roster = EmailSummaryRoster.build(candidates)
        return SummaryContext(me: me, other: other,
                              directionIsSent: email.direction == .sent, roster: roster)
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
