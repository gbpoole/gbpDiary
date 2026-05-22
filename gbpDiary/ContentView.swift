import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case timesheet = "Timesheet"
    case projects = "Projects"
    case people = "People"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .day
    @State private var currentDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        Group {
            switch selectedTab {
            case .day:        DayView(date: currentDate)
            case .week:       WeekView(weekOf: currentDate)
            case .timesheet:  TimesheetView()
            case .projects:   ProjectsView()
            case .people:     PeopleView()
            }
        }
        .toolbar {
            #if os(macOS)
            if selectedTab == .day {
                ToolbarItemGroup(placement: .navigation) {
                    Button { stepDay(-1) } label: { Image(systemName: "chevron.left") }
                    Button { stepDay(1) }  label: { Image(systemName: "chevron.right") }
                    Button("Today") { currentDate = Calendar.current.startOfDay(for: Date()) }
                        .disabled(Calendar.current.isDateInToday(currentDate))
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 380)
            }
            #endif
        }
    }

    private func stepDay(_ delta: Int) {
        currentDate = Calendar.current.date(byAdding: .day, value: delta, to: currentDate) ?? currentDate
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Task.self, DayRecord.self, Project.self,
                               Person.self, Institution.self, Minutes.self,
                               Attachment.self, Document.self, Note.self],
                        inMemory: true)
}
