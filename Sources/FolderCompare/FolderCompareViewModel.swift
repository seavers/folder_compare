import AppKit
import Combine
import Foundation

@MainActor
final class FolderCompareViewModel: ObservableObject {
    private static let historyStorageKey = "FolderCompare.history"

    @Published var leftFolderPath = ""
    @Published var rightFolderPath = ""
    @Published var compareResult: CompareResult?
    @Published var isComparing = false
    @Published var errorMessage: String?
    @Published var activeOperationMessage: String?
    @Published var historyItems: [CompareHistoryItem] = []

    init() {
        historyItems = loadHistoryItems()
    }

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
        activeOperationMessage = nil

        Task {
            do {
                // 1. 在后台任务中执行目录扫描和文件归类，避免主线程在大目录下失去响应。
                let result = try await compareInBackground(leftPath: leftPath, rightPath: rightPath)

                // 2. 回到主线程更新界面状态，让统计卡片和结果视图同时刷新。
                compareResult = result
                saveHistory(leftPath: leftPath, rightPath: rightPath)
                isComparing = false
            } catch {
                errorMessage = error.localizedDescription
                compareResult = nil
                isComparing = false
            }
        }
    }

    func deleteLeftOnlyFile(_ file: FileRecord) {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先完成左右目录选择。"
            return
        }

        isComparing = true
        errorMessage = nil
        activeOperationMessage = "正在删除左侧文件..."

        Task {
            do {
                // 1. 先在后台删除左侧独有文件，避免大目录操作阻塞界面。
                try await Task.detached(priority: .userInitiated) {
                    let service = FolderCompareService()
                    try service.deleteLeftOnlyFile(file, leftRoot: URL(fileURLWithPath: leftPath))
                }.value

                // 2. 删除完成后重新执行对比，确保树视图和扁平视图状态同步更新。
                compareResult = try await compareInBackground(leftPath: leftPath, rightPath: rightPath)
                isComparing = false
                activeOperationMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                isComparing = false
                activeOperationMessage = nil
            }
        }
    }

    func copyRightOnlyFileToLeft(_ file: FileRecord) {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先完成左右目录选择。"
            return
        }

        isComparing = true
        errorMessage = nil
        activeOperationMessage = "正在复制右侧文件到左侧..."

        Task {
            do {
                // 1. 先复制右侧独有文件到左侧对应路径，并保留右侧文件时间戳。
                try await Task.detached(priority: .userInitiated) {
                    let service = FolderCompareService()
                    try service.copyRightOnlyFileToLeft(file, leftRoot: URL(fileURLWithPath: leftPath))
                }.value

                // 2. 复制完成后刷新比对结果，让新增文件立即进入一致或差异分类。
                compareResult = try await compareInBackground(leftPath: leftPath, rightPath: rightPath)
                isComparing = false
                activeOperationMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                isComparing = false
                activeOperationMessage = nil
            }
        }
    }

    func compare(using historyItem: CompareHistoryItem) {
        leftFolderPath = historyItem.leftPath
        rightFolderPath = historyItem.rightPath
        compareFolders()
    }

    private func compareInBackground(leftPath: String, rightPath: String) async throws -> CompareResult {
        try await Task.detached(priority: .userInitiated) {
            let service = FolderCompareService()
            return try service.compare(leftFolder: URL(fileURLWithPath: leftPath), rightFolder: URL(fileURLWithPath: rightPath))
        }.value
    }

    private func saveHistory(leftPath: String, rightPath: String) {
        let normalizedLeft = leftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRight = rightPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else {
            return
        }

        var updatedItems = historyItems.filter { !($0.leftPath == normalizedLeft && $0.rightPath == normalizedRight) }
        updatedItems.insert(CompareHistoryItem(leftPath: normalizedLeft, rightPath: normalizedRight), at: 0)
        historyItems = Array(updatedItems.prefix(20))

        guard let data = try? JSONEncoder().encode(historyItems) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.historyStorageKey)
    }

    private func loadHistoryItems() -> [CompareHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyStorageKey),
              let items = try? JSONDecoder().decode([CompareHistoryItem].self, from: data) else {
            return []
        }

        return items.sorted { $0.comparedAt > $1.comparedAt }
    }
}
