import Foundation

nonisolated enum ChatMarkdownNormalizer {
    static func normalize(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            text.removeSubrange(text.startIndex..<end.upperBound)
        }

        text = text.replacingOccurrences(of: "```[^\n]*\n?", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "!\\[([^]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^[ \\t]*- \\[[ xX]\\][ \\t]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^[ \\t]{0,3}(#{1,6}|>|[-+*]|\\d+[.)])[ \\t]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_~`]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum ChatChunker {
    static func chunks(document: ChatRetrievalDocument, maxCharacters: Int = 1_200,
                       overlapCharacters: Int = 160) -> [ChatRetrievalChunk] {
        let text = ChatMarkdownNormalizer.normalize(document.markdown)
        guard !text.isEmpty, maxCharacters > 0 else { return [] }
        let overlap = min(max(0, overlapCharacters), max(0, maxCharacters - 1))
        let words = text.split(whereSeparator: \Character.isWhitespace).flatMap { word -> [String] in
            var remainder = word[...]
            var pieces: [String] = []
            while !remainder.isEmpty {
                let end = remainder.index(remainder.startIndex, offsetBy: min(maxCharacters, remainder.count))
                pieces.append(String(remainder[..<end]))
                remainder = remainder[end...]
            }
            return pieces
        }
        guard !words.isEmpty else { return [] }

        var result: [ChatRetrievalChunk] = []
        var start = 0
        while start < words.count {
            var end = start
            var length = 0
            while end < words.count {
                let added = words[end].count + (end == start ? 0 : 1)
                if end > start && length + added > maxCharacters { break }
                length += added
                end += 1
                if length >= maxCharacters { break }
            }
            let chunkText = words[start..<end].joined(separator: " ")
            result.append(ChatRetrievalChunk(source: document.source, index: result.count, text: chunkText,
                                             projectNames: document.projectNames, sortDate: document.sortDate,
                                             importanceWeight: document.importanceWeight))
            guard end < words.count else { break }

            var nextStart = end
            var overlapLength = 0
            while nextStart > start {
                let candidate = words[nextStart - 1].count + (overlapLength == 0 ? 0 : 1)
                if overlapLength + candidate > overlap { break }
                overlapLength += candidate
                nextStart -= 1
            }
            start = max(start + 1, nextStart)
        }
        return result
    }
}
