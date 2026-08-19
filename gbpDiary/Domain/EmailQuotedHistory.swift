import Foundation

// Strips quoted reply / forward history from an email body, returning just the *newest* message — the
// text a top-posting reply places above the quoted thread. The Mail header already gives us the true
// sender/recipient and direction; this keeps the on-device summariser's *evidence* aligned with that
// header, so a long "On <date>, X wrote:" chain of other people can't be mis-attributed to the newest
// message.
//
// Deliberately conservative: it cuts only at strong, well-known reply/forward boundaries, and if none is
// found (or the body is quoted from its very first line) it returns the body unchanged — we never drop
// content on a guess. Inline (interleaved) replies are left intact; only trailing quoted history is
// removed.
nonisolated enum EmailQuotedHistory {
    /// The newest message: body text above the first quoted-history boundary (trimmed). Unchanged when
    /// there is no recognised boundary or the body is quoted from the start.
    static func newestMessage(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lines = trimmed.components(separatedBy: "\n")
        guard let cut = boundaryIndex(lines), cut > 0 else { return trimmed }
        return lines[0..<cut].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Index of the first line that begins quoted history, or nil if none is recognised.
    static func boundaryIndex(_ lines: [String]) -> Int? {
        var best: Int?
        func consider(_ i: Int) { best = best.map { min($0, i) } ?? i }

        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()

            // Attribution line — "On <…> wrote:" (require the "On " prefix so a sentence merely ending in
            // "wrote:" isn't cut). Handles the wrapped two-line form ("On …\n<addr> wrote:").
            if lower.hasSuffix("wrote:") {
                if lower.hasPrefix("on ") {
                    consider(i)
                } else if i > 0, lines[i - 1].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("on ") {
                    consider(i - 1)
                }
                continue
            }
            // "-----Original Message-----" / "---------- Forwarded message ----------" dividers.
            if isDivider(lower) { consider(i); continue }
            // Outlook long underscore separator (usually precedes a From:/Sent:/To: header block).
            if line.count >= 10, line.allSatisfy({ $0 == "_" }) { consider(i); continue }
            // Quoted mail-header block: "From:" soon followed by Sent/Date + To.
            if lower.hasPrefix("from:"), looksLikeHeaderBlock(lines, from: i) { consider(i); continue }
        }
        return best
    }

    /// A "-----Original Message-----"-style divider (any dash run, case-insensitive), or a forwarded-
    /// message banner.
    private static func isDivider(_ lower: String) -> Bool {
        let words = lower.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces)
        return words == "original message" || words == "forwarded message" || words == "original appointment"
    }

    /// True when a "From:" line is part of a quoted header block (Sent:/Date: and To: within a few lines),
    /// not just prose that happens to start with "From:".
    private static func looksLikeHeaderBlock(_ lines: [String], from i: Int) -> Bool {
        let window = lines[i..<min(i + 5, lines.count)]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let hasWhen = window.contains { $0.hasPrefix("sent:") || $0.hasPrefix("date:") }
        let hasTo = window.contains { $0.hasPrefix("to:") }
        return hasWhen && hasTo
    }
}
