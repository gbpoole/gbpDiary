import Foundation

// Formats how long an answer took, for the muted latency label under each response. Sub-second shows
// milliseconds ("820 ms"); a second or more shows one decimal ("1.4 s"). Pure/testable.
nonisolated enum ChatDurationFormat {
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 1 { return "\(Int((s * 1000).rounded())) ms" }
        return String(format: "%.1f s", s)
    }
}
