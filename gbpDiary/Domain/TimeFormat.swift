import Foundation

// Minute-aware compact duration text for small, email-scale times where `Duration.displayString`'s
// hours (e.g. "0.1h" for five minutes) read poorly. Pure/testable; used only for the email time chips
// and the collapsed sent-email group total — `Duration.displayString`/timesheet math is left untouched.
enum TimeFormat {
    /// Format an hours value compactly: "Nm" under an hour, "Nh" for whole hours, else "Hh Mm".
    /// Rounds to the nearest minute; a non-zero value under 30s still shows as "1m" (never "0m").
    static func short(hours: Double) -> String {
        guard hours > 0 else { return "0m" }
        var minutes = Int((hours * 60).rounded())
        if minutes == 0 { minutes = 1 }   // keep a tiny logged time visible
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
