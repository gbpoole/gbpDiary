import Foundation

enum DayEntryDetailTarget {
    case task(Task)
    case meeting(Minutes)
}

extension DayEntry {
    var detailTarget: DayEntryDetailTarget? {
        switch kind {
        case .task:
            guard let task else { return nil }
            return .task(task)
        case .meeting:
            guard let minutes else { return nil }
            return .meeting(minutes)
        case .note:
            return nil
        }
    }

    var inlineSummary: String {
        get {
            switch kind {
            case .note:
                return text
            case .task:
                return task?.summary ?? ""
            case .meeting:
                return minutes?.summary ?? ""
            }
        }
        set {
            switch kind {
            case .note:
                text = newValue
            case .task:
                task?.summary = newValue
            case .meeting:
                minutes?.summary = newValue.isEmpty ? nil : newValue
            }
        }
    }

    var isInlineSummaryEmpty: Bool {
        inlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
