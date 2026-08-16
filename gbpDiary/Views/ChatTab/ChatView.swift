import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ChatView: View {
    @Bindable var state: ChatState

    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openURL) private var openURL
    @Query private var projects: [Project]
    @Query private var tasks: [Task]
    @Query private var people: [Person]
    @Query private var institutions: [Institution]
    @Query private var meetings: [Minutes]
    @Query private var notes: [Note]
    @Query private var days: [DayRecord]
    @Query private var documents: [Document]
    @Query(sort: \EmailMessage.date, order: .reverse) private var emails: [EmailMessage]
    @Query private var attachments: [Attachment]

    @State private var mailService = MailScriptService()
    @State private var selectedTask: Task?
    @State private var sourceError: String?

    private let answerer = FoundationModelsChatAnswerer()
    private let experimenter = FoundationModelsEmailSummaryExperimenter()
    private let retrievalWorker = ChatRetrievalWorker.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch state.mode {
            case .database:
                databaseChat
            case .emailExplorerLab:
                emailLab
            }
        }
        .background(AppTheme.background)
        .task(id: state.answerRequestToken) {
            let token = state.answerRequestToken
            guard token > 0 else { return }
            await answerPendingQuestion(requestToken: token)
        }
        .task(id: state.selectedEmailRevision) {
            let revision = state.selectedEmailRevision
            await loadSelectedEmailBody(selectionRevision: revision)
        }
        .task(id: state.lab.requestToken) {
            let token = state.lab.requestToken
            let revision = state.selectedEmailRevision
            guard token > 0 else { return }
            await generateExperiment(selectionRevision: revision, requestToken: token)
        }
        .onChange(of: Set(emails.map(\.id))) {
            if state.selectedEmailID != nil, selectedEmail == nil { state.selectEmail(nil) }
        }
        .sheet(item: $selectedTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.originEmail?.date ?? Date())
        }
        .alert("Source unavailable", isPresented: Binding(
            get: { sourceError != nil }, set: { if !$0 { sourceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(sourceError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.mode == .database ? "Ask your workspace" : "Email Summary Lab")
                    .font(AppTheme.interfaceFont(size: 17, weight: .semibold))
                Text("Apple Intelligence and semantic search run on this Mac")
                    .font(.caption).foregroundStyle(AppTheme.mutedText)
            }
            Spacer()
            Picker("Mode", selection: $state.mode) {
                Text("Database").tag(ChatMode.database)
                Text("Email Explorer").tag(ChatMode.emailExplorerLab)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            if state.mode == .database, !state.messages.isEmpty {
                Button("Clear") {
                    state.clearChat()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppTheme.card)
    }

    private var databaseChat: some View {
        VStack(spacing: 0) {
            if state.messages.isEmpty {
                ContentUnavailableView {
                    Label("Ask about your work", systemImage: "text.magnifyingglass")
                } description: {
                    Text("Search projects, tasks, people, meetings, notes, diary entries, documents, email summaries, PDFs, and text attachments.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(state.messages) { message in messageView(message) }
                        if state.isAnswering {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Searching local sources and generating on-device…")
                                    .font(.callout).foregroundStyle(AppTheme.mutedText)
                            }
                        }
                    }
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
            if let error = state.answerError {
                Text(error).font(.caption).foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 6)
            }
            Divider()
            composer
        }
    }

    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .user ? "YOU" : "ON-DEVICE ANSWER")
                .font(AppTheme.interfaceFont(size: 10, weight: .semibold))
                .foregroundStyle(message.role == .user ? AppTheme.accent : AppTheme.duration)
            Text(message.content)
                .font(AppTheme.bodyFont(size: 14))
                .textSelection(.enabled)
            if !message.sources.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(message.sources, id: \.key) { source in
                        Button { open(source) } label: {
                            Chip(label: source.displayLabel, color: color(for: source.kind))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? AppTheme.card : AppTheme.cardRaised.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a question about your workspace…", text: $state.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit { submitQuestion() }
            Button { submitQuestion() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isAnswering)
        }
        .padding(14)
        .background(AppTheme.card)
    }

    private var emailLab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Email") {
                    FuzzyPickerField(
                        allItems: emails,
                        selectedItem: selectedEmailBinding,
                        label: emailLabel,
                        chipColor: AppTheme.accent,
                        placeholder: "Search subject, correspondent, address, or date…",
                        tapArea: true,
                        emptyLabel: "Choose an email to experiment with…",
                        filters: emailFilters
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let email = selectedEmail {
                    labForEmail(email)
                } else {
                    ContentUnavailableView("Choose an email", systemImage: "envelope.badge",
                                           description: Text("Its body will be read transiently from Mail and will never be stored or indexed."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    @ViewBuilder
    private func labForEmail(_ email: EmailMessage) -> some View {
        GroupBox("Current production summary") {
            Text(email.summary?.isEmpty == false ? email.summary! : "No summary is currently stored.")
                .foregroundStyle(email.summary?.isEmpty == false ? AppTheme.text : AppTheme.mutedText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Transient Mail content") {
            if state.lab.isLoadingBody {
                HStack { ProgressView().controlSize(.small); Text("Reading from Mail…") }
            } else if let error = state.lab.bodyError {
                Text(error).foregroundStyle(AppTheme.warning)
            } else if let body = state.lab.body {
                DisclosureGroup("Show email body") {
                    ScrollView {
                        Text(body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                    .frame(maxHeight: 260)
                }
            }
            Text("The body is held only in this tab's memory and discarded when the tab closes or the email changes.")
                .font(.caption).foregroundStyle(AppTheme.mutedText)
        }

        GroupBox("Experiment") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Additional instructions").font(.caption).foregroundStyle(AppTheme.mutedText)
                TextEditor(text: $state.lab.instructions)
                    .font(AppTheme.bodyFont(size: 13))
                    .frame(minHeight: 72)
                    .padding(5)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border))
                Toggle("Use semantically related projects, tasks, meetings, notes, and documents as clarification context",
                       isOn: $state.lab.includeRelatedContext)
                HStack {
                    Button("Generate candidate", systemImage: "sparkles") {
                        state.lab.requestToken &+= 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.lab.body == nil || state.lab.isGenerating || !experimenter.isAvailable)
                    if state.lab.isGenerating { ProgressView().controlSize(.small) }
                    Spacer()
                    if !experimenter.isAvailable {
                        Text(answerer.unavailableReason ?? "Apple Intelligence is unavailable.")
                            .font(.caption).foregroundStyle(AppTheme.warning)
                    }
                }
                if let error = state.lab.generationError {
                    Text(error).font(.caption).foregroundStyle(AppTheme.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !state.lab.candidates.isEmpty {
            GroupBox("Candidates") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(state.lab.candidates) { candidate in
                        candidateView(candidate, email: email)
                        if candidate.id != state.lab.candidates.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func candidateView(_ candidate: ChatLabCandidate, email: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.summary).textSelection(.enabled)
            HStack {
                Picker("Evaluation", selection: ratingBinding(for: candidate.id)) {
                    Text("Not rated").tag(ChatLabRating?.none)
                    ForEach(ChatLabRating.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .frame(width: 190)
                Spacer()
                if candidate.isAdopted {
                    Label("Stored summary", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.completed)
                } else {
                    Button("Use this summary") { adopt(candidate, for: email) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var selectedEmail: EmailMessage? {
        guard let id = state.selectedEmailID else { return nil }
        return emails.first { $0.persistentModelID == id }
    }

    private var selectedEmailBinding: Binding<EmailMessage?> {
        Binding(get: { selectedEmail }, set: { email in
            state.selectEmail(email?.persistentModelID)
        })
    }

    private var emailFilters: [PickerFilter<EmailMessage>] {
        [
            PickerFilter(id: "direction.received", label: "Received", group: "Direction") { $0.direction == .inbox },
            PickerFilter(id: "direction.sent", label: "Sent", group: "Direction") { $0.direction == .sent },
        ]
    }

    private func emailLabel(_ email: EmailMessage) -> String {
        let subject = email.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let party = email.fromName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = party?.isEmpty == false ? party! : email.fromAddress
        let direction = email.direction == .sent ? "To" : "From"
        return "\(subject.isEmpty ? "(No subject)" : subject) — \(direction) \(who) — \(email.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func submitQuestion() {
        let question = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !state.isAnswering else { return }
        state.messages.append(ChatMessage(role: .user, content: question))
        state.pendingQuestion = question
        state.draft = ""
        state.answerRequestToken &+= 1
    }

    private func answerPendingQuestion(requestToken: Int) async {
        guard let question = state.beginAnswerRequest(requestToken) else { return }
        state.answerError = nil
        defer {
            if state.isCurrentAnswerRequest(requestToken) { state.isAnswering = false }
        }

        let priorMessages = Array(state.messages.dropLast())
        let history = priorMessages.map { ChatHistoryMessage(role: $0.role, text: $0.content) }
        let priorSources = priorMessages.reversed().first { $0.role == .assistant && !$0.sources.isEmpty }?.sources ?? []
        let input = ChatAnswerPipeline.Input(
            question: question, history: history, priorSources: priorSources,
            knownProjectNames: projects.map(\.name), now: Date())

        let result = await ChatAnswerPipeline().run(
            input,
            retrieve: { await rankedSources(for: $0, limit: $1) },
            timeRecords: { timeRecords() },
            activityProvider: { activityDigest(for: $0) },
            answerer: answerer,
            scopeResolver: FoundationModelsScopeResolver())

        guard state.isCurrentAnswerRequest(requestToken) else { return }
        state.answerError = result.answerError
        switch result.outcome {
        case .capability(let text):
            state.messages.append(ChatMessage(role: .assistant, content: text))
        case .noResults:
            state.messages.append(ChatMessage(role: .assistant,
                                              content: "I could not find relevant information in the local workspace."))
        case .unavailable(let reason, let sources):
            state.messages.append(ChatMessage(role: .assistant,
                                              content: reason ?? "Apple Intelligence is unavailable.",
                                              sources: sources))
        case .answered(let answer):
            state.messages.append(ChatMessage(role: .assistant, content: answer.text, sources: answer.citations))
        case .generationFailed(_, let sources):
            state.messages.append(ChatMessage(role: .assistant,
                                              content: "I found these relevant local sources, but could not generate a grounded answer.",
                                              sources: sources))
        }
    }

    private func loadSelectedEmailBody(selectionRevision: Int) async {
        guard let email = selectedEmail else { return }
        let emailID = email.persistentModelID
        guard state.isCurrentEmailRequest(emailID, revision: selectionRevision) else { return }
        state.lab.isLoadingBody = true
        do {
            let body = try await withCheckedThrowingContinuation { continuation in
                mailService.fetchContent(email) { continuation.resume(with: $0) }
            }
            guard state.isCurrentEmailRequest(emailID, revision: selectionRevision) else { return }
            state.lab.body = body
            state.lab.isLoadingBody = false
        } catch {
            guard state.isCurrentEmailRequest(emailID, revision: selectionRevision) else { return }
            state.lab.bodyError = (error as? MailScriptError)?.userMessage ?? error.localizedDescription
            state.lab.isLoadingBody = false
        }
    }

    private func generateExperiment(selectionRevision: Int, requestToken: Int) async {
        guard let email = selectedEmail, let body = state.lab.body, !state.lab.isGenerating else { return }
        let emailID = email.persistentModelID
        guard state.isCurrentLabRequest(emailID, revision: selectionRevision, token: requestToken) else { return }
        guard experimenter.isAvailable else {
            state.lab.generationError = answerer.unavailableReason
            return
        }
        state.lab.isGenerating = true
        state.lab.generationError = nil
        defer { state.finishLabGeneration(emailID, revision: selectionRevision, token: requestToken) }

        let background: [ChatPromptSource]
        if state.lab.includeRelatedContext {
            let query = email.subject + " " + String(body.prefix(1_200))
            let ranking = await rankedSources(for: query, limit: 6)
            guard state.isCurrentLabRequest(emailID, revision: selectionRevision, token: requestToken) else { return }
            state.answerError = ranking.error
            let emailKey = ChatSourceKey(kind: .email, modelID: email.id)
            let ranked = ranking.chunks.filter { $0.chunk.source.key != emailKey }
            background = ChatPromptBuilder.build(question: query, rankedChunks: ranked, history: [],
                                                 maxHistoryMessages: 0, maxHistoryCharacters: 0,
                                                 maxSourceCharacters: 5_000).sources
        } else {
            background = []
        }

        let request = EmailSummaryExperimentRequest(
            context: summaryContext(for: email), subject: email.subject, body: body,
            experimentalInstructions: state.lab.instructions, backgroundSources: background)
        do {
            let summary = try await experimenter.generate(request)
            guard state.isCurrentLabRequest(emailID, revision: selectionRevision, token: requestToken) else { return }
            guard !summary.isEmpty else { throw ChatAnswerError.emptyAnswer }
            state.lab.candidates.insert(ChatLabCandidate(summary: summary), at: 0)
        } catch {
            guard state.isCurrentLabRequest(emailID, revision: selectionRevision, token: requestToken) else { return }
            state.lab.generationError = "Candidate generation failed: \(error.localizedDescription)"
        }
    }

    private func rankedSources(for query: String, limit: Int) async -> (chunks: [ChatRankedChunk], error: String?) {
        let snapshot = corpusSnapshot()
        do {
            let url = try ChatSemanticIndex.defaultURL()
            let result = await retrievalWorker.rebuildAndSearch(snapshot: snapshot, indexURL: url,
                                                                query: query, limit: limit)
            return (result.chunks, result.error)
        } catch {
            return ([], "The local search index location is unavailable.")
        }
    }

    /// Every logged-time record (task time entries, standalone email time entries, and meetings) with its own
    /// date + project(s). Chat sums these deterministically for interval totals — never the RAG corpus/model.
    private func timeRecords() -> [ChatTimeRecord] {
        // All logged time is work — weekend entries fold back to the preceding Friday (overtime), so
        // interval/week bucketing never attributes work to a Saturday.
        var records: [ChatTimeRecord] = []
        for task in tasks {
            let names = [task.project?.name].compactMap { $0 }
            for entry in task.timeEntries {
                records.append(ChatTimeRecord(sourceKey: entry.id.uuidString, date: ChatWeekendFold.foldWork(entry.date),
                                              hours: entry.duration.hoursNormalized, projectNames: names))
            }
        }
        for email in emails {
            let names = email.projects.map(\.name)
            for entry in email.timeEntries where entry.task == nil {
                records.append(ChatTimeRecord(sourceKey: entry.id.uuidString, date: ChatWeekendFold.foldWork(entry.date),
                                              hours: entry.duration.hoursNormalized, projectNames: names))
            }
        }
        for meeting in meetings {
            guard let hours = meeting.duration?.hoursNormalized, hours > 0 else { continue }
            records.append(ChatTimeRecord(sourceKey: meeting.id.uuidString, date: ChatWeekendFold.foldWork(meeting.meetingAt),
                                          hours: hours, projectNames: meeting.projects.map(\.name)))
        }
        return records
    }

    /// The real activity (meetings attended + tasks completed) in a window, weekend-folded, for the
    /// activity-digest lens. Only genuine records — the model rephrases these and can invent nothing.
    private func activityDigest(for interval: Range<Date>) -> ChatActivityDigest {
        var items: [ChatActivityItem] = []
        for meeting in meetings {
            let date = ChatWeekendFold.fold(meeting.meetingAt, kind: .meeting)
            let title = meeting.summary ?? "Meeting"
            let label = meeting.duration.map { "Meeting: \(title) (\($0.displayString))" } ?? "Meeting: \(title)"
            let ref = ChatSourceReference(id: meeting.id, kind: .meeting, title: title, detail: nil,
                                          navigationKind: .meeting, navigationID: meeting.id)
            items.append(ChatActivityItem(date: date, label: label, source: ref))
        }
        for task in tasks {
            guard task.status == .completed, let completedAt = task.completedAt else { continue }
            let date = ChatWeekendFold.foldWork(completedAt)
            let ref = ChatSourceReference(id: task.id, kind: .task, title: task.summary, detail: nil,
                                          navigationKind: .task, navigationID: task.id)
            items.append(ChatActivityItem(date: date, label: "Completed: \(task.summary)", source: ref))
        }
        return ChatActivityDigestBuilder.build(items: items, interval: interval)
    }

    private func corpusSnapshot() -> ChatCorpusSnapshot {
        ChatCorpusBuilder().snapshot(projects: projects, tasks: tasks, people: people,
                                     institutions: institutions, meetings: meetings, notes: notes,
                                     days: days, documents: documents, emails: emails,
                                     attachments: attachments)
    }

    private func summaryContext(for email: EmailMessage) -> SummaryContext {
        let mePerson = AppSettingsStore.myPersonID.flatMap { id in people.first { $0.id == id } }
        let me = mePerson.map { SummaryPerson(name: $0.name, emails: $0.emails) }
        let other = email.person.map { SummaryPerson(name: $0.name, emails: $0.emails) }
        var priority = Set<UUID>()
        if let person = email.person { priority.insert(person.id) }
        for project in email.projects {
            for person in project.devTeam + project.sciTeam { priority.insert(person.id) }
        }
        let candidates = people.filter { $0.id != mePerson?.id }.map {
            EmailSummaryRoster.Candidate(id: $0.id, name: $0.name, emails: $0.emails,
                                         isPriority: priority.contains($0.id))
        }
        return SummaryContext(me: me, other: other, directionIsSent: email.direction == .sent,
                              roster: EmailSummaryRoster.build(candidates))
    }

    private func ratingBinding(for id: UUID) -> Binding<ChatLabRating?> {
        Binding(get: { state.lab.candidates.first { $0.id == id }?.rating }, set: { rating in
            guard let index = state.lab.candidates.firstIndex(where: { $0.id == id }) else { return }
            state.lab.candidates[index].rating = rating
        })
    }

    private func adopt(_ candidate: ChatLabCandidate, for email: EmailMessage) {
        guard let values = EmailSummaryAdoption.values(for: candidate.summary) else { return }
        email.summary = values.summary
        email.summaryState = values.state
        email.summaryPromptVersion = values.promptVersion
        for index in state.lab.candidates.indices {
            state.lab.candidates[index].isAdopted = state.lab.candidates[index].id == candidate.id
        }
    }

    private func open(_ source: ChatSourceReference) {
        switch source.navigationKind {
        case .project:
            if let item = projects.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.project(item.persistentModelID))
            }
        case .person:
            if let item = people.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.person(item.persistentModelID))
            }
        case .institution:
            if let item = institutions.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.institution(item.persistentModelID))
            }
        case .meeting:
            if let item = meetings.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.minutes(item.persistentModelID))
            }
        case .note:
            if let item = notes.first(where: { $0.id == source.navigationID }) { workspace.reveal(note: item) }
        case .task:
            selectedTask = tasks.first { $0.id == source.navigationID }
        case .document:
            if let item = documents.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.document(item.persistentModelID))
            }
        case .email:
            guard let email = emails.first(where: { $0.id == source.navigationID }) else { return }
            mailService.openMessage(email) { result in
                if case .failure(let error) = result { sourceError = error.userMessage }
            }
        case .day:
            if let day = days.first(where: { $0.id == source.navigationID }) {
                workspace.focusDiary(date: day.date, scrollTo: nil)
            }
        case .attachment:
            guard let url = source.navigationURL else {
                sourceError = "The attachment file is unavailable."
                return
            }
            #if os(macOS)
            if !NSWorkspace.shared.open(url) {
                sourceError = "The attachment file could not be opened."
            }
            #else
            openURL(url)
            #endif
        }
    }

    private func color(for kind: ChatSourceKind) -> Color {
        switch kind {
        case .project, .document, .attachment: AppTheme.project
        case .person: AppTheme.person
        case .institution: AppTheme.institution
        case .meeting, .day: AppTheme.duration
        case .task: AppTheme.action
        case .note: AppTheme.tag
        case .email: AppTheme.accent
        }
    }
}
