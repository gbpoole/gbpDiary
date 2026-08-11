import Foundation

// One contiguous run of the chip editor's *display* string: either a plain-text run (display length ==
// markdown length) or an image/link chip (display length 1, but expands to its full markdown ref).
struct ChipRun: Equatable {
    let displayLength: Int
    let markdownLength: Int
}

// Converts a caret/insertion location in the chip editor's **display** string (where each image/link
// chip is a single U+FFFC placeholder) into the equivalent offset in the serialized **markdown**
// string (where each chip expands to `![name](attachment://uuid)` / `[title](note://uuid)`).
//
// Without this, an insertion index taken from the display string is applied to the markdown string and
// lands inside an existing ref once the note contains a chip — corrupting it. See ImageChipTextEditor.
enum ChipMarkdownOffset {
    static func markdownOffset(displayLocation: Int, runs: [ChipRun]) -> Int {
        guard displayLocation > 0 else { return 0 }
        var displayPos = 0
        var markdownPos = 0
        for run in runs {
            if displayLocation >= displayPos + run.displayLength {
                // The whole run precedes the location.
                markdownPos += run.markdownLength
                displayPos += run.displayLength
            } else {
                // The location falls within this run. Chips (displayLength 1) are atomic — snap to
                // before the chip; plain text advances character-for-character (1:1 with markdown).
                if run.displayLength > 1 {
                    markdownPos += displayLocation - displayPos
                }
                return markdownPos
            }
        }
        return markdownPos
    }
}
