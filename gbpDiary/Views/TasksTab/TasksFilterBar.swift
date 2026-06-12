import SwiftUI
import SwiftData

struct TasksFilterBar: View {
    @Binding var statusFilter: TaskStatus?
    @Binding var projectFilter: Project?
    @Binding var personFilter: Person?
    @Binding var dateRangeFilter: ClosedRange<Date>?

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var showingDatePicker = false
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()

    var body: some View {
        HStack(spacing: 12) {
            statusPicker
            projectPicker
            personPicker
            dateRangePicker
            if hasActiveFilter {
                Button("Clear") { clearFilters() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
        }
        .font(AppTheme.interfaceFont(size: 12))
        .foregroundStyle(AppTheme.mutedText)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBackground)
    }

    private var hasActiveFilter: Bool {
        statusFilter != nil || projectFilter != nil || personFilter != nil || dateRangeFilter != nil
    }

    private var statusPicker: some View {
        Picker("Status", selection: $statusFilter) {
            Text("Any status").tag(Optional<TaskStatus>.none)
            Divider()
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Text(status.displayName).tag(Optional(status))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var projectPicker: some View {
        Picker("Project", selection: $projectFilter) {
            Text("Any project").tag(Optional<Project>.none)
            if !allProjects.isEmpty { Divider() }
            ForEach(allProjects) { project in
                Text(project.name).tag(Optional(project))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var personPicker: some View {
        Picker("Person", selection: $personFilter) {
            Text("Any person").tag(Optional<Person>.none)
            if !allPeople.isEmpty { Divider() }
            ForEach(allPeople) { person in
                Text(person.name).tag(Optional(person))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var dateRangePicker: some View {
        Button(dateRangeLabel) {
            if dateRangeFilter != nil {
                dateRangeFilter = nil
            } else {
                rangeStart = Calendar.current.startOfDay(for: Date())
                rangeEnd = Calendar.current.date(byAdding: .day, value: 7, to: rangeStart) ?? rangeStart
                showingDatePicker = true
            }
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showingDatePicker) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                DatePicker("To", selection: $rangeEnd, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Apply") {
                        let start = Calendar.current.startOfDay(for: rangeStart)
                        let end = Calendar.current.date(byAdding: .day, value: 1,
                                                        to: Calendar.current.startOfDay(for: rangeEnd)) ?? rangeEnd
                        dateRangeFilter = start...end
                        showingDatePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(minWidth: 240)
        }
    }

    private var dateRangeLabel: String {
        guard let range = dateRangeFilter else { return "Any date" }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        return "\(fmt.string(from: range.lowerBound)) – \(fmt.string(from: range.upperBound))"
    }

    private func clearFilters() {
        statusFilter = nil
        projectFilter = nil
        personFilter = nil
        dateRangeFilter = nil
    }
}

extension TaskStatus: CaseIterable {
    public static var allCases: [TaskStatus] {
        [.todo, .started, .completed, .cancelled, .followUpPending]
    }

    var displayName: String {
        switch self {
        case .todo:            return "To Do"
        case .started:         return "Started"
        case .completed:       return "Completed"
        case .cancelled:       return "Cancelled"
        case .followUpPending: return "Follow-up Pending"
        }
    }
}
