import Foundation

/// Coalesces rapid repeated calls into a single delayed execution.
/// Stored as `@State` in a SwiftUI view so it persists across re-renders.
final class Debouncer {
    private var work: DispatchWorkItem?

    func schedule(delay: Double, action: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() { work?.cancel(); work = nil }
}
