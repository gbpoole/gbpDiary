import SwiftUI

// Present in the ZStack when the note row is unfocused.
// hitTest returns nil so AppKit's mouse dispatch skips this view - mouse events
// fall through to SwiftUI's gesture recognizers, enabling .draggable() and
// .onTapGesture to work normally from anywhere on the row.
// NSDraggingDestination is retained because drag delivery is frame-based (not
// hit-test-based): it swallows UUID string drops, preventing them from landing
// in the hidden TextEditor below.
#if os(macOS)
struct NoteViewModeOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NoteViewModeNSView { NoteViewModeNSView() }
    func updateNSView(_ nsView: NoteViewModeNSView, context: Context) {}
}

final class NoteViewModeNSView: NSView {
    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .generic }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
}
#endif
