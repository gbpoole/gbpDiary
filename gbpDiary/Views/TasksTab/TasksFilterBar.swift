import SwiftUI

/// A date-range selector styled to match `FilterGroupSelector`, for use as an `extraRows`
/// entry in a `FilterBar`. Shows a neutral "Date" dropdown that opens a from/to popover and,
/// once a range is set, a removable chip with the range.
struct DateRangeFilterRow: View {
    @Binding var range: ClosedRange<Date>?

    @State private var showing = false
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                rangeStart = range?.lowerBound ?? Calendar.current.startOfDay(for: Date())
                rangeEnd = range?.upperBound ?? (Calendar.current.date(byAdding: .day, value: 7, to: rangeStart) ?? rangeStart)
                showing = true
            } label: {
                HStack(spacing: 5) {
                    Text("Date").font(.caption).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(width: 104, alignment: .leading)
            .popover(isPresented: $showing, arrowEdge: .bottom) { editor }

            if let range {
                PickerRemovableChip(label: rangeLabel(range), color: AppTheme.accent) { self.range = nil }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("From", selection: $rangeStart, displayedComponents: .date)
            DatePicker("To", selection: $rangeEnd, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Apply") {
                    let start = Calendar.current.startOfDay(for: rangeStart)
                    let end = Calendar.current.date(byAdding: .day, value: 1,
                                                    to: Calendar.current.startOfDay(for: rangeEnd)) ?? rangeEnd
                    range = start...end
                    showing = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 240)
    }

    private func rangeLabel(_ range: ClosedRange<Date>) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        return "\(fmt.string(from: range.lowerBound)) – \(fmt.string(from: range.upperBound))"
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
