import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

// Self-contained block-based note editor. Owns its own @FocusState, selectedBlockId,
// and keyboard monitors. Use when editing a single Note without sharing monitor context
// with a parent view — e.g. MinutesDetailView. Passes onEdit: nil and onDelete: nil
// to DayNoteRow so those context-menu items are hidden.
struct NoteEditingArea: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedEntryId: UUID?
    @State private var selectedBlockId: UUID?
    @State private var pendingFocusId: UUID?
    @State private var pendingBlockDeletion: (() -> Void)?

    #if os(macOS)
    @State private var deleteMonitor     = DeleteKeyMonitor()
    @State private var returnMonitor     = ReturnKeyMonitor()
    @State private var focusClearMonitor = FocusClearMonitor()
    @State private var escapeMonitor     = EscapeKeyMonitor()
    @State private var shiftArrowMonitor = ShiftArrowMonitor()
    #endif

    var body: some View {
        DayNoteRow(
            note: note,
            focusedEntryId: $focusedEntryId,
            selectedBlockId: $selectedBlockId,
            consumeLastClearedSelectedBlockId: {
                #if os(macOS)
                return focusClearMonitor.consumeLastClearedSelectedId()
                #else
                return nil
                #endif
            }
        )
        .onChange(of: pendingFocusId) { _, newId in
            if let id = newId { focusedEntryId = id; pendingFocusId = nil }
        }
        #if os(macOS)
        .onAppear {
            focusClearMonitor.captureId = { focusedEntryId }
            focusClearMonitor.captureSelectedId = { selectedBlockId }
            focusClearMonitor.action = {
                focusedEntryId = nil
                selectedBlockId = nil
            }
            escapeMonitor.action = {
                if let focused = focusedEntryId {
                    focusedEntryId = nil
                    selectedBlockId = focused
                    return true
                } else if selectedBlockId != nil {
                    selectedBlockId = nil
                    return true
                }
                return false
            }
            deleteMonitor.start(); returnMonitor.start()
            focusClearMonitor.start(); escapeMonitor.start()
            shiftArrowMonitor.start()
            updateMonitorActions()
        }
        .onDisappear {
            deleteMonitor.stop(); returnMonitor.stop()
            focusClearMonitor.stop(); escapeMonitor.stop()
            shiftArrowMonitor.stop()
        }
        .onChange(of: focusedEntryId) { _, newId in
            if let newId { selectedBlockId = newId }
            updateDeleteAction(for: newId)
        }
        .onChange(of: selectedBlockId) { _, newId in
            updateDeleteAction(for: focusedEntryId)
            updateReturnAction(for: newId)
            updateShiftArrowActions(for: newId)
        }
        .alert("Delete Block?", isPresented: Binding(
            get: { pendingBlockDeletion != nil },
            set: { if !$0 { pendingBlockDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) { pendingBlockDeletion?(); pendingBlockDeletion = nil }
            Button("Cancel", role: .cancel) { pendingBlockDeletion = nil }
        } message: {
            Text("This block will be permanently deleted.")
        }
        #endif
    }

    #if os(macOS)
    private func updateMonitorActions() {
        updateDeleteAction(for: focusedEntryId)
        updateReturnAction(for: selectedBlockId)
        updateShiftArrowActions(for: selectedBlockId)
    }

    private func updateDeleteAction(for focusId: UUID?) {
        if focusId == nil, let selId = selectedBlockId {
            if let idx = note.blocks.firstIndex(where: { $0.id == selId }) {
                switch note.blocks[idx].kind {
                case .image:
                    guard let attId = note.blocks[idx].attachmentId,
                          let att = note.attachments.first(where: { $0.id == attId }) else { break }
                    deleteMonitor.action = {
                        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
                        pendingBlockDeletion = {
                            var blocks = note.blocks
                            guard blocks.indices.contains(idx), blocks[idx].kind == .image else { return }
                            blocks.remove(at: idx)
                            let prev = idx - 1, next = idx
                            if blocks.indices.contains(prev), blocks.indices.contains(next),
                               blocks[prev].kind == .text, blocks[next].kind == .text {
                                let merged = [blocks[prev].textContent.trimmingCharacters(in: .newlines),
                                              blocks[next].textContent.trimmingCharacters(in: .newlines)]
                                    .filter { !$0.isEmpty }.joined(separator: "\n\n")
                                blocks[prev].textContent = merged
                                blocks.remove(at: next)
                            }
                            if blocks.isEmpty { blocks = [.text("")] }
                            note.blocks = blocks
                            if let r = att.renderURL { AttachmentStorage.delete(at: r) }
                            AttachmentStorage.delete(at: att.fileURL)
                            modelContext.delete(att)
                            note.attachments.removeAll { $0.id == att.id }
                            note.updatedAt = Date()
                            selectedBlockId = nil
                        }
                        return true
                    }
                case .text:
                    let blockId = note.blocks[idx].id
                    deleteMonitor.action = {
                        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
                        let content = note.blocks.first(where: { $0.id == blockId })?.textContent ?? ""
                        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            deleteTextBlock(blockId: blockId)
                        } else {
                            pendingBlockDeletion = { deleteTextBlock(blockId: blockId) }
                        }
                        return true
                    }
                }
                return
            }
        }
        guard let focusId else { deleteMonitor.action = nil; return }
        if note.blocks.contains(where: { $0.id == focusId && $0.kind == .text }) {
            let blockId = focusId
            deleteMonitor.action = {
                // Check live NSTextView content; backing store lags by up to 2s (debouncer)
                let isEmpty: Bool
                if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                    isEmpty = tv.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } else {
                    isEmpty = note.blocks.first(where: { $0.id == blockId })?
                        .textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                }
                guard isEmpty else { return false }
                deleteTextBlock(blockId: blockId)
                return true
            }
        } else {
            deleteMonitor.action = nil
        }
    }

    private func deleteTextBlock(blockId: UUID) {
        var blocks = note.blocks
        guard let idx = blocks.firstIndex(where: { $0.id == blockId }),
              blocks[idx].kind == .text else { return }
        let prevBlock = idx > 0 ? blocks[idx - 1] : nil
        let nextBlock = idx < blocks.count - 1 ? blocks[idx + 1] : nil
        blocks.remove(at: idx)
        if blocks.isEmpty { blocks = [.text("")] }
        note.blocks = blocks
        note.updatedAt = Date()
        selectedBlockId = nil
        if let prev = prevBlock {
            if prev.kind == .text { pendingFocusId = prev.id }
            else { selectedBlockId = prev.id }
        } else if let next = nextBlock {
            if next.kind == .text { pendingFocusId = next.id }
            else { selectedBlockId = next.id }
        }
    }

    private func updateReturnAction(for selId: UUID?) {
        guard let selId else { returnMonitor.action = nil; return }
        if let idx = note.blocks.firstIndex(where: { $0.id == selId }) {
            switch note.blocks[idx].kind {
            case .image:
                returnMonitor.action = {
                    var blocks = note.blocks
                    if let gid = blocks[idx].groupId {
                        let newGid = UUID()
                        for i in (idx + 1)..<blocks.count where blocks[i].groupId == gid {
                            blocks[i].groupId = newGid
                        }
                        NoteBlock.cleanupGroupIds(in: &blocks)
                    }
                    let newBlock = NoteBlock.text("")
                    blocks.insert(newBlock, at: idx + 1)
                    note.blocks = blocks
                    note.updatedAt = Date()
                    pendingFocusId = newBlock.id
                    return true
                }
            case .text:
                returnMonitor.action = { pendingFocusId = selId; return true }
            }
        } else {
            returnMonitor.action = nil
        }
    }

    private func updateShiftArrowActions(for selId: UUID?) {
        guard let selId else { clearShiftArrowActions(); return }
        if note.blocks.contains(where: { $0.id == selId }) {
            shiftArrowMonitor.actionUp = {
                guard let updated = NoteBlock.shiftUp(blocks: note.blocks, selId: selId) else { return false }
                note.blocks = updated; note.updatedAt = Date(); return true
            }
            shiftArrowMonitor.actionDown = {
                guard let updated = NoteBlock.shiftDown(blocks: note.blocks, selId: selId) else { return false }
                note.blocks = updated; note.updatedAt = Date(); return true
            }
            shiftArrowMonitor.actionLeft = {
                guard let updated = NoteBlock.shiftLeft(blocks: note.blocks, selId: selId) else { return false }
                note.blocks = updated; note.updatedAt = Date(); return true
            }
            shiftArrowMonitor.actionRight = {
                guard let updated = NoteBlock.shiftRight(blocks: note.blocks, selId: selId) else { return false }
                note.blocks = updated; note.updatedAt = Date(); return true
            }
            shiftArrowMonitor.actionPlainUp = {
                guard let idx = note.blocks.firstIndex(where: { $0.id == selId }) else { return false }
                let blocks = note.blocks
                var prevIdx = idx - 1
                if let gid = blocks[idx].groupId {
                    var groupStart = idx
                    while groupStart > 0 && blocks[groupStart - 1].groupId == gid { groupStart -= 1 }
                    prevIdx = groupStart - 1
                }
                if prevIdx >= 0 { selectedBlockId = blocks[prevIdx].id; return true }
                return false
            }
            shiftArrowMonitor.actionPlainDown = {
                guard let idx = note.blocks.firstIndex(where: { $0.id == selId }) else { return false }
                let blocks = note.blocks
                var nextIdx = idx + 1
                if let gid = blocks[idx].groupId {
                    var groupEnd = idx
                    while groupEnd < blocks.count - 1 && blocks[groupEnd + 1].groupId == gid { groupEnd += 1 }
                    nextIdx = groupEnd + 1
                }
                if nextIdx < blocks.count { selectedBlockId = blocks[nextIdx].id; return true }
                return false
            }
            shiftArrowMonitor.actionPlainLeft = {
                guard let idx = note.blocks.firstIndex(where: { $0.id == selId }),
                      idx > 0,
                      let gid = note.blocks[idx].groupId,
                      note.blocks[idx - 1].groupId == gid else { return false }
                selectedBlockId = note.blocks[idx - 1].id; return true
            }
            shiftArrowMonitor.actionPlainRight = {
                guard let idx = note.blocks.firstIndex(where: { $0.id == selId }),
                      idx < note.blocks.count - 1,
                      let gid = note.blocks[idx].groupId,
                      note.blocks[idx + 1].groupId == gid else { return false }
                selectedBlockId = note.blocks[idx + 1].id; return true
            }
        } else {
            clearShiftArrowActions()
        }
    }

    private func clearShiftArrowActions() {
        shiftArrowMonitor.actionUp    = nil; shiftArrowMonitor.actionDown  = nil
        shiftArrowMonitor.actionLeft  = nil; shiftArrowMonitor.actionRight = nil
        shiftArrowMonitor.actionPlainUp   = nil; shiftArrowMonitor.actionPlainDown  = nil
        shiftArrowMonitor.actionPlainLeft = nil; shiftArrowMonitor.actionPlainRight = nil
    }
    #endif
}
