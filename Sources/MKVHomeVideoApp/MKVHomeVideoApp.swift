import SwiftUI
import MKVHomeVideoCore

@main
struct MKVHomeVideoApp: App {
    @State private var model: AppViewModel

    init() {
        _model = State(initialValue: AppViewModel(store: QueueProjectStore()))
    }

    var body: some Scene {
        WindowGroup("MKV Home Video") {
            Group {
                switch model.screen {
                case .setup:
                    SetupView(model: model)
                case .queue:
                    QueueView(model: model)
                }
            }
            .frame(minWidth: 860, minHeight: 580)
        }
    }
}
