import SwiftUI

struct MessagesHostActions {
    let requestExpanded: () -> Void
    let postSnapshot: (CachedMessagesTripV1, Bool) -> Void
    let reconnect: (URL?) -> Void
}

struct MessagesRootView: View {
    @ObservedObject var model: MessagesViewModel
    let actions: MessagesHostActions

    var body: some View {
        Group {
            switch model.presentationMode {
            case .compact:
                MessagesCompactView(model: model, actions: actions)
            case .expanded:
                MessagesExpandedView(model: model, actions: actions)
            case .transcript:
                MessagesTranscriptView(model: model)
            }
        }
        .tint(MessagesTheme.fairway)
        .preferredColorScheme(.dark)
    }
}
