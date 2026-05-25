import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case diary = "Diary"
    case timesheet = "Timesheet"
    case projects = "Projects"
    case people = "People"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .diary

    var body: some View {
        Group {
            switch selectedTab {
            case .diary:      DiaryView()
            case .timesheet:  TimesheetView()
            case .projects:   ProjectsView()
            case .people:     PeopleView()
            }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 320)
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Task.self, DayRecord.self, DayEntry.self, Project.self,
                               Person.self, Institution.self, Minutes.self,
                               Attachment.self, Document.self, Note.self],
                        inMemory: true)
}
