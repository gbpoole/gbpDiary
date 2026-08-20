#if os(macOS)
import Foundation
import Testing
@testable import gbpDiary

struct CalendarAccessTests {
    // Right after the first approval, EventKit's `authorizationStatus` may still read `.notDetermined`,
    // so `granted == true` must win regardless of the fallback (this was the empty-list bug).
    @Test func resolve_grantedIsAuthoritative() {
        #expect(CalendarService.resolve(granted: true, fallback: .denied) == .authorized)
        #expect(CalendarService.resolve(granted: true, fallback: .notDetermined) == .authorized)
    }

    // When not granted, the fallback status distinguishes denied / restricted / writeOnly.
    @Test func resolve_notGranted_usesFallback() {
        #expect(CalendarService.resolve(granted: false, fallback: .denied) == .denied)
        #expect(CalendarService.resolve(granted: false, fallback: .restricted) == .restricted)
        #expect(CalendarService.resolve(granted: false, fallback: .writeOnly) == .writeOnly)
        #expect(CalendarService.resolve(granted: false, fallback: .notDetermined) == .notDetermined)
    }
}
#endif
