import SwiftUI

struct MinutesInspectorView: View {
    @Environment(MinutesEditorContext.self) private var editorContext

    var body: some View {
        if let note = editorContext.activeNote {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if editorContext.canGoBack {
                        Button {
                            editorContext.back()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Back to previous meeting")
                    }
                    Text(editorContext.activeTitle ?? "Meeting Minutes")
                        .font(AppTheme.interfaceFont(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Button {
                        editorContext.close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Close minutes panel")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.background)
                Divider()
                ScrollView {
                    NoteEditingArea(note: note)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
