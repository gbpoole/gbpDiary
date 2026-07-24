import SwiftUI

// Lightweight image editor opened by tapping an image chip in the markdown source pane.
// Edits the managed image's display name / description, or removes it from the note.
struct NoteImageEditSheet: View {
    @Bindable var attachment: Attachment
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ImageThumbnail(url: attachment.fileURL, size: 200)
                        .frame(maxWidth: .infinity)

                    field("Display name") {
                        TextField("Display name", text: Binding(
                            get: { attachment.displayName ?? "" },
                            set: { attachment.displayName = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    field("Description") {
                        TextField("What this image shows…", text: Binding(
                            get: { attachment.attachmentDescription ?? "" },
                            set: { attachment.attachmentDescription = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                    }
                }
                .padding()
            }
            .navigationTitle(attachment.displayName ?? attachment.fileName)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove", role: .destructive) { showingRemove = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Remove image?", isPresented: $showingRemove) {
                Button("Remove", role: .destructive) { onRemove(); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the image from the note and deletes the file.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 380)
        #endif
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
