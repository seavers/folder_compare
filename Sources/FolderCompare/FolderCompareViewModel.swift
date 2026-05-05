import AppKit
import Combine
import Foundation

@MainActor
final class FolderCompareViewModel: ObservableObject {
    @Published var leftFolderPath = ""
    @Published var rightFolderPath = ""
    @Published var compareResult: CompareResult?
    @Published var isComparing = false
    @Published var errorMessage: String?

    func chooseFolder(for side: CompareSide) {
        let panel = NSOpenPanel()
        panel.title = side == .left ? "选择左侧文件夹" : "选择右侧文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        switch side {
        case .left:
            leftFolderPath = url.path
        case .right:
            rightFolderPath = url.path
        }
    }

    func compareFolders() {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先选择左右两个文件夹。"
            return
        }

        isComparing = true
        errorMessage = nil

        Task {
            do {
                // 1. 在后台任务中执行目录扫描和文件归类，避免主线程在大目录下失去响应。
                let result = try await Task.detached(priority: .userInitiated) {
                    let service = FolderCompareService()
                    return try service.compare(leftFolder: URL(fileURLWithPath: leftPath), rightFolder: URL(fileURLWithPath: rightPath))
                }.value

                // 2. 回到主线程更新界面状态，让统计卡片和结果视图同时刷新。
                compareResult = result
                isComparing = false
            } catch {
                errorMessage = error.localizedDescription
                compareResult = nil
                isComparing = false
            }
        }
    }
}
