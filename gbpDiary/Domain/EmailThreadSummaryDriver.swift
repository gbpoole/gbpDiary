import SwiftUI
import SwiftData
import Combine
import OSLog

// Invisible, global background driver (placed once in WorkspaceView, beside EmailSummaryDriver). Builds
// the whole-thread day summaries: for each day's conversation (both directions) with ≥2 messages whose
// per-email summaries are all `done`, it summarises on-device over those per-email summaries (never raw
// bodies) and caches the result in an `EmailThreadSummary`. Same "never mark unavailable / idle-kick"
// posture as EmailSummaryDriver, so summaries appear once Apple Intelligence is ready.
struct EmailThreadSummaryDriver: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var emails: [EmailMessage]
    @Query private var stored: [EmailThreadSummary]
    @State private var kick = 0
    @State private var isRunning = false
    private let summarizer = FoundationModelsSummarizer()
    private let calendar = Calendar.current
    private let log = Logger(subsystem: "gbpDiary", category: "EmailThreadSummary")

    init() {
        // Candidate messages: accepted, non-dismissed (the ones the diary/activity surfaces show).
        _emails = Query(filter: #Predicate<EmailMessage> { $0.accepted && !$0.dismissed },
                        sort: \EmailMessage.date, order: .reverse)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: kick) { await runQueue() }
            // Idle heartbeat: re-run to pick up freshly-fetched/summarised mail and recover when the model
            // transitions unavailable → available.
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                if !isRunning { kick &+= 1 }
            }
    }

    // One day's conversation, keyed by (dayStart, threadKey).
    private struct Group { let threadKey: String; let dayStart: Date; let messages: [EmailMessage] }

    private func candidateGroups() -> [Group] {
        var byKey: [String: [EmailMessage]] = [:]
        for email in emails {
            let day = calendar.startOfDay(for: email.date)
            let key = "\(EmailThreadBuilder.threadKey(for: email))@@\(day.timeIntervalSinceReferenceDate)"
            byKey[key, default: []].append(email)
        }
        return byKey.compactMap { _, msgs in
            guard msgs.count >= 2 else { return nil }                       // multi-message threads only
            guard msgs.allSatisfy({ $0.summaryState == EmailSummaryState.done.rawValue }) else { return nil }
            let day = calendar.startOfDay(for: msgs[0].date)
            return Group(threadKey: EmailThreadBuilder.threadKey(for: msgs[0]), dayStart: day, messages: msgs)
        }
    }

    private func runQueue() async {
        guard !isRunning, summarizer.isAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        for group in candidateGroups() {
            guard summarizer.isAvailable else { break }
            let fingerprint = EmailThreadSummaryFingerprint.make(group.messages.map { ($0.id, $0.summaryPromptVersion) })
            let record = existingRecord(threadKey: group.threadKey, dayStart: group.dayStart)
            let state = record.flatMap { EmailSummaryState(rawValue: $0.summaryState) }
            guard EmailThreadSummaryPlanning.needsSummary(
                state: state, storedFingerprint: record?.sourceFingerprint, fingerprint: fingerprint,
                storedVersion: record?.summaryPromptVersion ?? -1) else { continue }
            await summarize(group, fingerprint: fingerprint, into: record)
        }
    }

    private func summarize(_ group: Group, fingerprint: String, into existing: EmailThreadSummary?) async {
        let ordered = group.messages.sorted { $0.date < $1.date }   // oldest first for the narrative
        let lines = ordered.map {
            ThreadMessageLine(directionIsSent: $0.direction == .sent,
                              time: Self.timeFormatter.string(from: $0.date),
                              summary: $0.summary ?? "")
        }
        let participants = distinctParticipants(ordered)
        let subject = ordered.last?.subject ?? ordered.first?.subject ?? ""
        let prompt = EmailThreadSummaryPrompt.build(subject: subject, participants: participants, messages: lines)

        let record = existing ?? {
            let r = EmailThreadSummary(threadKey: group.threadKey, dayStart: group.dayStart)
            modelContext.insert(r)
            return r
        }()
        do {
            let text = try await summarizer.summarizeThread(prompt: prompt)
            record.text = text
            record.summaryState = EmailSummaryState.done.rawValue
        } catch EmailSummaryError.modelUnavailable {
            return   // leave as-is; the idle kick retries when the model returns (never a terminal state)
        } catch {
            log.error("thread summary failed: \(error.localizedDescription, privacy: .public)")
            record.summaryState = EmailSummaryState.failed.rawValue
        }
        record.sourceFingerprint = fingerprint
        record.summaryPromptVersion = EmailThreadSummaryPrompt.promptVersion
    }

    private func existingRecord(threadKey: String, dayStart: Date) -> EmailThreadSummary? {
        stored.first { $0.threadKey == threadKey && $0.dayStart == dayStart }
    }

    private func distinctParticipants(_ messages: [EmailMessage]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for m in messages {
            let name = m.person?.name ?? m.fromName ?? m.fromAddress
            let key = name.lowercased()
            if !name.isEmpty, seen.insert(key).inserted { names.append(name) }
        }
        return names
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}
