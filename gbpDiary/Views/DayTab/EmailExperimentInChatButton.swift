import SwiftUI

struct EmailExperimentInChatButton: View {
    let email: EmailMessage

    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        Button("Experiment in Chat", systemImage: "bubble.left.and.bubble.right") {
            workspace.openEmailExplorerInNewTab(for: email)
        }
    }
}
