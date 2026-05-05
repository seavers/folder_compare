import AppKit
import Combine
import Foundation

@MainActor
final class FolderCompareViewModel: ObservableObject {
    private static let historyStorageKey = "FolderCompare.history"

    @Published var leftFolderPath = ""
    @Published var rightFolderPath = ""
    @Published var compareResult: CompareResult?
    @Published var compareProgress: CompareProgress?
    @Published var isComparing = false
    @Published var errorMessage: String?
    @Published var activeOperationMessage: String?
    @Published var historyItems: [CompareHistoryItem] = []

    private var compareTask: Task<Void, Never>?
    private var compareGeneration = 0

    init() {
        historyItems = loadHistoryItems()
    }

    deinit {
        compareTask?.cancel()
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

    func swapFolders() {
        let currentLeft = leftFolderPath
        leftFolderPath = rightFolderPath
        rightFolderPath = currentLeft
    }

    func compareFolders() {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先选择左右两个文件夹。"
            return
        }

        startCompare(leftPath: leftPath, rightPath: rightPath, saveHistory: true, operationMessage: nil)
    }

    func deleteFile(_ file: FileRecord, from side: CompareSide) {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先完成左右目录选择。"
            return
        }

        let rootPath = side == .left ? leftPath : rightPath
        let message = "正在删除\(side.displayName)文件..."
        runFileOperation(message: message) {
            let service = FolderCompareService()
            try service.deleteFile(file, from: side, root: URL(fileURLWithPath: rootPath))
        }
    }

    func copyFile(_ file: FileRecord, to side: CompareSide) {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先完成左右目录选择。"
            return
        }

        let destinationRoot = side == .left ? leftPath : rightPath
        let message = "正在复制文件到\(side.displayName)..."
        runFileOperation(message: message) {
            let service = FolderCompareService()
            try service.copyFile(file, to: URL(fileURLWithPath: destinationRoot))
        }
    }

    func compare(using historyItem: CompareHistoryItem) {
        leftFolderPath = historyItem.leftPath
        rightFolderPath = historyItem.rightPath
        compareFolders()
    }

    func cancelCompare() {
        compareTask?.cancel()
        compareTask = nil
        isComparing = false
        activeOperationMessage = nil
        compareProgress = nil
    }

    private func startCompare(leftPath: String, rightPath: String, saveHistory shouldSaveHistory: Bool, operationMessage: String?) {
        compareTask?.cancel()
        compareGeneration += 1
        let generation = compareGeneration

        isComparing = true
        errorMessage = nil
        activeOperationMessage = operationMessage
        compareProgress = CompareProgress(phase: .preparing, currentPath: nil, leftDiscoveredCount: 0, rightDiscoveredCount: 0, processedCount: 0, totalCount: nil)

        compareTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                // 1. 在后台任务中执行目录扫描和文件归类，避免主线程在大目录下失去响应。
                let result = try await compareInBackground(leftPath: leftPath, rightPath: rightPath, generation: generation)
                try Task.checkCancellation()

                guard generation == compareGeneration else {
                    return
                }

                // 2. 回到主线程更新界面状态，让统计卡片和结果视图同时刷新。
                compareResult = result
                if shouldSaveHistory {
                    saveHistory(leftPath: leftPath, rightPath: rightPath)
                }
                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            } catch is CancellationError {
                guard generation == compareGeneration else {
                    return
                }

                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            } catch {
                guard generation == compareGeneration else {
                    return
                }

                errorMessage = error.localizedDescription
                compareResult = nil
                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            }
        }
    }

    private func runFileOperation(message: String, operation: @escaping @Sendable () throws -> Void) {
        let leftPath = leftFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPath = rightFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftPath.isEmpty, !rightPath.isEmpty else {
            errorMessage = "请先完成左右目录选择。"
            return
        }

        compareTask?.cancel()
        compareGeneration += 1
        let generation = compareGeneration

        isComparing = true
        errorMessage = nil
        activeOperationMessage = message
        compareProgress = CompareProgress(phase: .preparing, currentPath: nil, leftDiscoveredCount: 0, rightDiscoveredCount: 0, processedCount: 0, totalCount: nil)

        compareTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                // 1. 先在后台执行删除或复制，避免文件系统操作阻塞界面。
                try await Task.detached(priority: .userInitiated, operation: operation).value
                try Task.checkCancellation()

                // 2. 操作完成后复用统一的后台对比流程，确保结果和统计一次性刷新。
                let result = try await compareInBackground(leftPath: leftPath, rightPath: rightPath, generation: generation)
                try Task.checkCancellation()

                guard generation == compareGeneration else {
                    return
                }

                compareResult = result
                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            } catch is CancellationError {
                guard generation == compareGeneration else {
                    return
                }

                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            } catch {
                guard generation == compareGeneration else {
                    return
                }

                errorMessage = error.localizedDescription
                isComparing = false
                activeOperationMessage = nil
                compareProgress = nil
            }
        }
    }

    private func compareInBackground(leftPath: String, rightPath: String, generation: Int) async throws -> CompareResult {
        try await Task.detached(priority: .userInitiated) {
            let service = FolderCompareService()
            return try service.compare(leftFolder: URL(fileURLWithPath: leftPath), rightFolder: URL(fileURLWithPath: rightPath)) { progress in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.compareGeneration else {
                        return
                    }

                    self.compareProgress = progress
                }
            }
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
