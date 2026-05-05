import AppKit
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 FolderCompare") {
                    showAboutPanel()
                }
            }
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let buildDate = Bundle.main.object(forInfoDictionaryKey: "FolderCompareBuildDate") as? String ?? "-"

        // 1. 复用系统 About 面板，同时展示本次打包写入的版本号和构建日期。
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "FolderCompare",
                .applicationVersion: "版本 \(version)\n构建日期 \(buildDate)"
            ]
        )
    }
}
