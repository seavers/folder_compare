import SwiftUI

@main
struct FolderCompareApp: App {
    @StateObject private var viewModel = FolderCompareViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
    }
}
