import Foundation

// Pure markdown-formatting transforms for the note source editor's toolbar and keyboard shortcuts.
// Operates on the editor's display string + a UTF-16 selection (NSRange), returning the new string
// and the selection to restore. No AppKit — the macOS editor (ImageChipTextEditor) reads the text
// view's selection, calls `apply`, and writes the result back. Chips (image/note-link refs) appear
// as single placeholder characters in the display string and are treated as ordinary characters, so
// inline/line operations around them are safe.
enum FormatCommand: Equatable {
    case bold, italic, inlineCode          // inline wrap (toggle)
    case heading(Int)                      // 1…3: set/replace/toggle leading #'s on the line(s)
    case bulletList, numberedList, checkbox, quote   // line-prefix (toggle)
    case codeBlock, table                  // block insert at the caret
}

enum MarkdownFormatting {
    struct Result: Equatable {
        let text: String
        let selection: NSRange
    }

    static func apply(_ command: FormatCommand, to text: String, selection: NSRange) -> Result {
        switch command {
        case .bold:         return inlineWrap(text, selection, marker: "**")
        case .italic:       return inlineWrap(text, selection, marker: "*")
        case .inlineCode:   return inlineWrap(text, selection, marker: "`")
        case .heading(let level): return setHeading(text, selection, level: max(1, min(6, level)))
        case .bulletList:   return toggleLinePrefix(text, selection, prefix: "- ")
        case .checkbox:     return toggleLinePrefix(text, selection, prefix: "- [ ] ")
        case .quote:        return toggleLinePrefix(text, selection, prefix: "> ")
        case .numberedList: return toggleOrderedList(text, selection)
        case .codeBlock:    return insertBlock(text, selection, block: "```\n\n```")
        case .table:        return insertBlock(text, selection, block: tableSkeleton)
        }
    }

    static let tableSkeleton = "| Column | Column |\n| --- | --- |\n|  |  |"

    // MARK: - Return-in-list continuation

    private static let checkboxLine = try! NSRegularExpression(pattern: #"^(\s*)([-*+]) \[[ xX]\] (.*)$"#)
    private static let orderedLine  = try! NSRegularExpression(pattern: #"^(\s*)(\d+)\. (.*)$"#)
    private static let bulletLine   = try! NSRegularExpression(pattern: #"^(\s*)([-*+]) (.*)$"#)
    private static let quoteLine    = try! NSRegularExpression(pattern: #"^(\s*)((?:> )+)(.*)$"#)

    static let indentWidth = 4     // indentation is quantised to multiples of this many spaces

    private static func leadingSpaces(_ line: String) -> Int {
        var n = 0
        for ch in line { if ch == " " { n += 1 } else { break } }
        return n
    }

    // The [indent, markerPrefixLength, content, nextMarker] of a list/quote line, or nil if the line
    // is neither. `nextMarker` is what a continuation of this line should start with.
    private struct ListLine { let indent: String; let prefixLen: Int; let content: String; let nextMarker: String }
    private static func parseListLine(_ line: String) -> ListLine? {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let m = checkboxLine.firstMatch(in: line, range: whole) {
            let indent = ns.substring(with: m.range(at: 1)); let bullet = ns.substring(with: m.range(at: 2))
            let content = ns.substring(with: m.range(at: 3))
            return ListLine(indent: indent, prefixLen: ns.length - (content as NSString).length,
                            content: content, nextMarker: "\(bullet) [ ] ")
        }
        if let m = orderedLine.firstMatch(in: line, range: whole) {
            let indent = ns.substring(with: m.range(at: 1)); let n = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let content = ns.substring(with: m.range(at: 3))
            return ListLine(indent: indent, prefixLen: ns.length - (content as NSString).length,
                            content: content, nextMarker: "\(n + 1). ")
        }
        if let m = bulletLine.firstMatch(in: line, range: whole) {
            let indent = ns.substring(with: m.range(at: 1)); let bullet = ns.substring(with: m.range(at: 2))
            let content = ns.substring(with: m.range(at: 3))
            return ListLine(indent: indent, prefixLen: ns.length - (content as NSString).length,
                            content: content, nextMarker: "\(bullet) ")
        }
        if let m = quoteLine.firstMatch(in: line, range: whole) {
            let indent = ns.substring(with: m.range(at: 1)); let marker = ns.substring(with: m.range(at: 2))
            let content = ns.substring(with: m.range(at: 3))
            return ListLine(indent: indent, prefixLen: ns.length - (content as NSString).length,
                            content: content, nextMarker: marker)
        }
        return nil
    }

    // Behavior for pressing Return with the caret (empty selection) on a list item:
    // - on a non-empty item → start a new item below with the *same indentation* and marker
    //   (bullet char preserved; ordered number incremented; checkbox reset to unchecked);
    // - on an empty item (only indent + marker) → end the list by removing the marker.
    // Returns nil when the caret isn't on a list item (caller inserts a normal newline).
    static func returnInList(text: String, selection: NSRange) -> Result? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let caret = clamp(selection, to: ns.length).location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var lineContent = ns.substring(with: lineRange)
        if lineContent.hasSuffix("\n") { lineContent.removeLast() }
        guard let list = parseListLine(lineContent) else { return nil }

        // Empty item (marker only) → end the list/quote: remove [indent + marker] from the line.
        if list.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let removeRange = NSRange(location: lineRange.location, length: list.prefixLen)
            let newText = ns.replacingCharacters(in: removeRange, with: "")
            return Result(text: newText, selection: NSRange(location: lineRange.location, length: 0))
        }

        // Continue: insert newline + indent + marker at the caret.
        let insertion = "\n" + list.indent + list.nextMarker
        let newText = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: insertion)
        return Result(text: newText, selection: NSRange(location: caret + (insertion as NSString).length, length: 0))
    }

    // MARK: - Insert on a new line

    // Insert `insert` on a new line after the caret's line. When that line is a non-empty list/quote
    // item, the new line continues it (same indent + marker). An empty current line is used in place.
    static func insertOnNewLine(text: String, selection: NSRange, insert: String) -> Result {
        let ns = text as NSString
        let caret = clamp(selection, to: ns.length).location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var lineContent = ns.substring(with: lineRange)
        if lineContent.hasSuffix("\n") { lineContent.removeLast() }
        let insertPos = lineRange.location + (lineContent as NSString).length   // end of the line's text

        var prefix = ""
        if let list = parseListLine(lineContent), !list.content.trimmingCharacters(in: .whitespaces).isEmpty {
            prefix = list.indent + list.nextMarker
        }
        let fragment = lineContent.isEmpty ? (prefix + insert) : ("\n" + prefix + insert)
        let newText = ns.replacingCharacters(in: NSRange(location: insertPos, length: 0), with: fragment)
        let caretPos = insertPos + (fragment as NSString).length
        return Result(text: newText, selection: NSRange(location: caretPos, length: 0))
    }

    // MARK: - Indent / outdent

    // Tab / Shift-Tab: change the indentation of the line(s) touched by the selection — regardless of
    // where the caret sits on the line — quantising leading whitespace to multiples of `indentWidth`.
    // Tab moves the primary (first) line's start to the next multiple of 4; Shift-Tab to the previous
    // one (nil / no-op when already at column 0). The same space delta is applied to every line in the
    // block so relative nesting is preserved, and the block is extended to include any following
    // deeper-indented child lines so a nested bulleted sub-block moves with its parent.
    static func indentLines(text: String, selection: NSRange, outdent: Bool) -> Result? {
        let ns = text as NSString
        let sel = clamp(selection, to: ns.length)
        var lines = text.components(separatedBy: "\n")

        // UTF-16 start offset of each line.
        var starts = [Int](); starts.reserveCapacity(lines.count)
        var acc = 0
        for line in lines { starts.append(acc); acc += (line as NSString).length + 1 }
        func lineIndex(_ off: Int) -> Int {
            var result = 0
            for i in 0..<lines.count { if starts[i] <= off { result = i } else { break } }
            return result
        }

        let firstLine = lineIndex(sel.location)
        let lastSel = lineIndex(sel.length == 0 ? sel.location : max(sel.location, sel.location + sel.length - 1))
        let primaryLeading = leadingSpaces(lines[firstLine])

        // Space delta from the primary line's quantised move.
        let delta: Int
        if outdent {
            if primaryLeading == 0 { return nil }   // nothing to remove
            let target = primaryLeading % indentWidth == 0 ? primaryLeading - indentWidth
                                                           : (primaryLeading / indentWidth) * indentWidth
            delta = primaryLeading - max(0, target)
        } else {
            delta = ((primaryLeading / indentWidth) + 1) * indentWidth - primaryLeading
        }
        guard delta > 0 else { return nil }

        // Extend past the selection to include the nested child block (deeper-indented following lines).
        var blockEnd = lastSel
        while blockEnd + 1 < lines.count, leadingSpaces(lines[blockEnd + 1]) > primaryLeading { blockEnd += 1 }

        var caretShift = 0
        for i in firstLine...blockEnd {
            if outdent {
                let remove = min(delta, leadingSpaces(lines[i]))
                lines[i] = String((lines[i] as NSString).substring(from: remove))
                if i == firstLine { caretShift = -remove }
            } else {
                lines[i] = String(repeating: " ", count: delta) + lines[i]
                if i == firstLine { caretShift = delta }
            }
        }
        let newText = lines.joined(separator: "\n")

        if sel.length == 0 {
            let caret = max(starts[firstLine], sel.location + caretShift)
            return Result(text: newText, selection: NSRange(location: caret, length: 0))
        }
        // Select the whole affected block.
        var newStarts = [Int](); var acc2 = 0
        for line in lines { newStarts.append(acc2); acc2 += (line as NSString).length + 1 }
        let blockStart = newStarts[firstLine]
        let blockFinish = newStarts[blockEnd] + (lines[blockEnd] as NSString).length
        return Result(text: newText, selection: NSRange(location: blockStart, length: max(0, blockFinish - blockStart)))
    }

    // Remove up to one indent level (`indentWidth` spaces, or a leading tab) from a line.
    private static func outdentLine(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        var l = line, removed = 0
        while removed < indentWidth, l.hasPrefix(" ") { l.removeFirst(); removed += 1 }
        return l
    }

    // MARK: - Backspace at a list marker

    // Backspace with the caret exactly at the start of a list/quote item's content: outdent one level
    // if the item is indented, otherwise remove the marker (ending the list). Returns nil otherwise
    // (normal delete).
    static func backspaceInList(text: String, selection: NSRange) -> Result? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let caret = clamp(selection, to: ns.length).location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var lineContent = ns.substring(with: lineRange)
        if lineContent.hasSuffix("\n") { lineContent.removeLast() }
        guard let list = parseListLine(lineContent) else { return nil }
        // Only when the caret sits at the boundary between the marker and the content.
        guard caret == lineRange.location + list.prefixLen else { return nil }

        if !list.indent.isEmpty {
            // Outdent one level: drop leading indent from the line start.
            let dropped = (lineContent as NSString).length - (outdentLine(lineContent) as NSString).length
            let removeRange = NSRange(location: lineRange.location, length: dropped)
            let newText = ns.replacingCharacters(in: removeRange, with: "")
            return Result(text: newText, selection: NSRange(location: caret - dropped, length: 0))
        }
        // No indent → remove the marker entirely.
        let removeRange = NSRange(location: lineRange.location, length: list.prefixLen)
        let newText = ns.replacingCharacters(in: removeRange, with: "")
        return Result(text: newText, selection: NSRange(location: lineRange.location, length: 0))
    }

    // MARK: - Inline wrap (toggle)

    // Wrap the selection in `marker`, or unwrap when the selection is already wrapped (toggle). An
    // empty selection inserts the marker pair with the caret placed between them.
    private static func inlineWrap(_ text: String, _ sel: NSRange, marker: String) -> Result {
        let ns = text as NSString
        let range = clamp(sel, to: ns.length)
        let mLen = (marker as NSString).length

        // Already wrapped? (markers sit immediately outside the selection) → remove them.
        let before = NSRange(location: range.location - mLen, length: mLen)
        let after = NSRange(location: range.location + range.length, length: mLen)
        if before.location >= 0, after.location + after.length <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            let inner = ns.substring(with: range)
            let full = NSRange(location: before.location, length: mLen + range.length + mLen)
            let newText = ns.replacingCharacters(in: full, with: inner)
            return Result(text: newText, selection: NSRange(location: before.location, length: (inner as NSString).length))
        }

        // Selection itself already delimited by markers → strip them.
        let selected = ns.substring(with: range)
        if range.length >= 2 * mLen, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let innerNS = selected as NSString
            let inner = innerNS.substring(with: NSRange(location: mLen, length: innerNS.length - 2 * mLen))
            let newText = ns.replacingCharacters(in: range, with: inner)
            return Result(text: newText, selection: NSRange(location: range.location, length: (inner as NSString).length))
        }

        // Otherwise wrap.
        let wrapped = marker + selected + marker
        let newText = ns.replacingCharacters(in: range, with: wrapped)
        if range.length == 0 {
            // Caret between the markers.
            return Result(text: newText, selection: NSRange(location: range.location + mLen, length: 0))
        }
        return Result(text: newText, selection: NSRange(location: range.location + mLen, length: range.length))
    }

    // MARK: - Line prefix (toggle)

    private static func toggleLinePrefix(_ text: String, _ sel: NSRange, prefix: String) -> Result {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(sel, to: ns.length))
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }  // drop the empty element after a trailing \n

        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
            && lines.contains { $0.hasPrefix(prefix) }
        let newLines: [String] = lines.map { line in
            if allPrefixed {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            } else {
                return line.isEmpty ? line : prefix + line
            }
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: replacement)
        // Select the whole affected block so repeated toggles keep working.
        let newLen = (replacement as NSString).length - (hadTrailingNewline ? 1 : 0)
        return Result(text: newText, selection: NSRange(location: lineRange.location, length: max(0, newLen)))
    }

    // MARK: - Numbered list (toggle + renumber)

    private static func toggleOrderedList(_ text: String, _ sel: NSRange) -> Result {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(sel, to: ns.length))
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        let numberRegex = try! NSRegularExpression(pattern: #"^\d+\.\s"#)
        func isNumbered(_ s: String) -> Bool {
            numberRegex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        }
        let nonEmpty = lines.filter { !$0.isEmpty }
        let allNumbered = !nonEmpty.isEmpty && nonEmpty.allSatisfy(isNumbered)

        var counter = 0
        let newLines: [String] = lines.map { line in
            if line.isEmpty { return line }
            if allNumbered {
                let nsLine = line as NSString
                let m = numberRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))!
                return nsLine.substring(from: m.range.length)
            } else {
                counter += 1
                return "\(counter). " + line
            }
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: replacement)
        let newLen = (replacement as NSString).length - (hadTrailingNewline ? 1 : 0)
        return Result(text: newText, selection: NSRange(location: lineRange.location, length: max(0, newLen)))
    }

    // MARK: - Heading (set / replace / toggle)

    private static func setHeading(_ text: String, _ sel: NSRange, level: Int) -> Result {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(sel, to: ns.length))
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        let marker = String(repeating: "#", count: level) + " "
        let hashRegex = try! NSRegularExpression(pattern: #"^#{1,6}\s"#)
        func stripped(_ line: String) -> String {
            let nsLine = line as NSString
            if let m = hashRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                return nsLine.substring(from: m.range.length)
            }
            return line
        }
        // Toggle off only when every non-empty line already has exactly this level.
        let exactMarker = marker
        let nonEmpty = lines.filter { !$0.isEmpty }
        let allThisLevel = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(exactMarker) }

        let newLines: [String] = lines.map { line in
            if line.isEmpty { return line }
            let body = stripped(line)
            return allThisLevel ? body : marker + body
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: replacement)
        let newLen = (replacement as NSString).length - (hadTrailingNewline ? 1 : 0)
        return Result(text: newText, selection: NSRange(location: lineRange.location, length: max(0, newLen)))
    }

    // MARK: - Block insert

    // Insert a block at the caret (start of the selection), separated from surrounding text by blank
    // lines, mirroring MarkdownDocumentEditor.insertRefs. The caret is placed at the block's start.
    private static func insertBlock(_ text: String, _ sel: NSRange, block: String) -> Result {
        let ns = text as NSString
        let range = clamp(sel, to: ns.length)
        let idx = range.location
        var prefix = "", suffix = ""
        if idx > 0, ns.substring(with: NSRange(location: idx - 1, length: 1)) != "\n" { prefix = "\n\n" }
        if idx < ns.length, ns.substring(with: NSRange(location: idx, length: 1)) != "\n" { suffix = "\n\n" }
        let insertion = prefix + block + suffix
        let newText = ns.replacingCharacters(in: range, with: insertion)
        let caret = idx + (prefix as NSString).length
        return Result(text: newText, selection: NSRange(location: caret, length: (block as NSString).length))
    }

    // MARK: - Helpers

    private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }
}
