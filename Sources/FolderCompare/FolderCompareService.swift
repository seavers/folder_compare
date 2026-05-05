import Foundation

struct FolderCompareService {
    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

    func compare(leftFolder: URL, rightFolder: URL, progress: @escaping @Sendable (CompareProgress) -> Void = { _ in }) throws -> CompareResult {
        progress(CompareProgress(phase: .preparing, currentPath: nil, leftDiscoveredCount: 0, rightDiscoveredCount: 0, processedCount: 0, totalCount: nil))

        let leftSnapshot = try snapshot(for: leftFolder, side: .left, otherSideCount: 0, progress: progress)
        let rightSnapshot = try snapshot(for: rightFolder, side: .right, otherSideCount: leftSnapshot.filesByPath.count, progress: progress)

        let leftPaths = Set(leftSnapshot.filesByPath.keys)
        let rightPaths = Set(rightSnapshot.filesByPath.keys)
        let commonPaths = leftPaths.intersection(rightPaths).sorted(by: compareRelativePaths)

        var identicalFiles: [PathPair] = []
        var samePathDifferentSizeFiles: [PathPair] = []
        var processedCommonPathCount = 0

        // 1. 先按相对路径精确匹配，识别完全一致和同路径不同大小的文件。
        for path in commonPaths {
            try Task.checkCancellation()

            guard let leftFile = leftSnapshot.filesByPath[path], let rightFile = rightSnapshot.filesByPath[path] else {
                continue
            }

            let pair = PathPair(relativePath: path, left: leftFile, right: rightFile)
            if leftFile.size == rightFile.size {
                identicalFiles.append(pair)
            } else {
                samePathDifferentSizeFiles.append(pair)
            }

            processedCommonPathCount += 1
            if shouldReportProgress(current: processedCommonPathCount, total: commonPaths.count) {
                progress(
                    CompareProgress(
                        phase: .matchingPaths,
                        currentPath: path,
                        leftDiscoveredCount: leftSnapshot.filesByPath.count,
                        rightDiscoveredCount: rightSnapshot.filesByPath.count,
                        processedCount: processedCommonPathCount,
                        totalCount: commonPaths.count
                    )
                )
            }
        }

        let leftUnmatchedFiles = leftPaths.subtracting(commonPaths).compactMap { leftSnapshot.filesByPath[$0] }
        let rightUnmatchedFiles = rightPaths.subtracting(commonPaths).compactMap { rightSnapshot.filesByPath[$0] }
        let leftGroupsBySize = Dictionary(grouping: leftUnmatchedFiles, by: \.size)
        let rightGroupsBySize = Dictionary(grouping: rightUnmatchedFiles, by: \.size)
        let sameSizes = Set(leftGroupsBySize.keys).intersection(rightGroupsBySize.keys).sorted()

        var sameSizeDifferentPathGroups: [SizeMatchGroup] = []
        var sameSizeDifferentPathSet: Set<String> = []
        var sameSizeCounterpartsByPath: [String: [FileRecord]] = [:]
        var sameSizeCounterpartSideByPath: [String: CompareSide] = [:]
        var processedSameSizeGroupCount = 0

        // 2. 再从未命中路径的文件中，按大小归类，识别“大小一致但路径不同”的文件组。
        for size in sameSizes {
            try Task.checkCancellation()

            let leftFiles = sortFiles(leftGroupsBySize[size] ?? [])
            let rightFiles = sortFiles(rightGroupsBySize[size] ?? [])
            guard !leftFiles.isEmpty, !rightFiles.isEmpty else {
                continue
            }

            sameSizeDifferentPathGroups.append(SizeMatchGroup(size: size, leftFiles: leftFiles, rightFiles: rightFiles))

            for leftFile in leftFiles {
                sameSizeDifferentPathSet.insert(leftFile.relativePath)
                sameSizeCounterpartsByPath[leftFile.relativePath] = rightFiles
                sameSizeCounterpartSideByPath[leftFile.relativePath] = .right
            }

            for rightFile in rightFiles {
                sameSizeDifferentPathSet.insert(rightFile.relativePath)
                sameSizeCounterpartsByPath[rightFile.relativePath] = leftFiles
                sameSizeCounterpartSideByPath[rightFile.relativePath] = .left
            }

            processedSameSizeGroupCount += 1
            if shouldReportProgress(current: processedSameSizeGroupCount, total: sameSizes.count) {
                progress(
                    CompareProgress(
                        phase: .groupingSameSize,
                        currentPath: leftFiles.first?.relativePath ?? rightFiles.first?.relativePath,
                        leftDiscoveredCount: leftSnapshot.filesByPath.count,
                        rightDiscoveredCount: rightSnapshot.filesByPath.count,
                        processedCount: processedSameSizeGroupCount,
                        totalCount: sameSizes.count
                    )
                )
            }
        }

        // 3. 剩余没有任何对应关系的文件，归入左右独有结果，便于用户快速定位缺失项。
        let leftOnlyFiles = leftUnmatchedFiles.filter { !sameSizeDifferentPathSet.contains($0.relativePath) }.sorted(by: compareFiles)
        let rightOnlyFiles = rightUnmatchedFiles.filter { !sameSizeDifferentPathSet.contains($0.relativePath) }.sorted(by: compareFiles)

        let directoryIndex = try buildDirectoryIndex(
            leftFiles: leftSnapshot.filesByPath,
            rightFiles: rightSnapshot.filesByPath,
            identicalFiles: Set(identicalFiles.map(\.relativePath)),
            samePathDifferentSizeFiles: Set(samePathDifferentSizeFiles.map(\.relativePath)),
            sameSizeDifferentPathFiles: sameSizeDifferentPathSet,
            sameSizeCounterpartsByPath: sameSizeCounterpartsByPath,
            sameSizeCounterpartSideByPath: sameSizeCounterpartSideByPath,
            discoveredLeftCount: leftSnapshot.filesByPath.count,
            discoveredRightCount: rightSnapshot.filesByPath.count,
            progress: progress
        )

        let summary = CompareSummary(
            leftCount: leftSnapshot.filesByPath.count,
            rightCount: rightSnapshot.filesByPath.count,
            identicalCount: identicalFiles.count,
            samePathDifferentSizeCount: samePathDifferentSizeFiles.count,
            sameSizeDifferentPathCount: sameSizeDifferentPathGroups.reduce(0) { $0 + $1.leftFiles.count + $1.rightFiles.count },
            leftOnlyCount: leftOnlyFiles.count,
            rightOnlyCount: rightOnlyFiles.count
        )

        return CompareResult(
            leftRootPath: leftSnapshot.rootPath,
            rightRootPath: rightSnapshot.rootPath,
            identicalFiles: identicalFiles.sorted(by: comparePairs),
            samePathDifferentSizeFiles: samePathDifferentSizeFiles.sorted(by: comparePairs),
            sameSizeDifferentPathGroups: sameSizeDifferentPathGroups.sorted { $0.size < $1.size },
            leftOnlyFiles: leftOnlyFiles,
            rightOnlyFiles: rightOnlyFiles,
            directoryRoots: directoryIndex.roots,
            directoryItemsByPath: directoryIndex.itemsByPath,
            summary: summary
        )
    }

    func deleteFile(_ file: FileRecord, from side: CompareSide, root: URL) throws {
        let fileURL = URL(fileURLWithPath: file.absolutePath)
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath + "/") else {
            throw FolderCompareError.invalidFileOperation("目标文件不在\(side.displayName)目录下：\(file.relativePath)")
        }

        // 1. 删除当前侧文件，避免误删比较范围外的内容。
        try fileManager.removeItem(at: fileURL)

        // 2. 自底向上清理空目录，保持目标侧目录结构整洁，但不会越过根目录。
        try pruneEmptyDirectories(from: fileURL.deletingLastPathComponent(), root: root.standardizedFileURL)
    }

    func copyFile(_ file: FileRecord, to destinationRoot: URL) throws {
        let sourceURL = URL(fileURLWithPath: file.absolutePath)
        let destinationURL = destinationRoot.appendingPathComponent(file.relativePath)

        // 1. 先确保目标父目录存在，再执行复制，保证文件能落到目标侧对应层级。
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw FolderCompareError.invalidFileOperation("目标侧已存在同名文件：\(file.relativePath)")
        }

        // 2. 直接调用系统 cp 复制文件并保留元数据，避免为时间戳额外发起一次属性读取。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-anp", sourceURL.path, destinationURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FolderCompareError.invalidFileOperation("复制文件失败：\(file.relativePath)")
        }
    }

    private func snapshot(for folder: URL, side: CompareSide, otherSideCount: Int, progress: @escaping @Sendable (CompareProgress) -> Void) throws -> FolderSnapshot {
        let rootURL = folder.standardizedFileURL
        let rootPath = rootURL.path

        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles]) else {
            throw FolderCompareError.unableToEnumerateFolder(rootPath)
        }

        var filesByPath: [String: FileRecord] = [:]
        var scannedCount = 0
        var discoveredFileCount = 0

        // 1. 递归遍历目录，只收集常规文件，避免文件夹参与大小比较。
        for case let fileURL as URL in enumerator {
            scannedCount += 1
            if scannedCount.isMultiple(of: 128) {
                try Task.checkCancellation()
            }

            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                continue
            }

            let relativePath = String(filePath.dropFirst(rootPath.count + 1))
            let size = UInt64(values.fileSize ?? 0)
            filesByPath[relativePath] = FileRecord(relativePath: relativePath, absolutePath: filePath, size: size)
            discoveredFileCount += 1

            if shouldReportProgress(current: discoveredFileCount, total: nil) {
                progress(makeSnapshotProgress(side: side, currentPath: relativePath, discoveredFileCount: discoveredFileCount, otherSideCount: otherSideCount))
            }
        }

        progress(makeSnapshotProgress(side: side, currentPath: nil, discoveredFileCount: discoveredFileCount, otherSideCount: otherSideCount))
        return FolderSnapshot(rootPath: rootPath, filesByPath: filesByPath)
    }

    private func buildDirectoryIndex(leftFiles: [String: FileRecord], rightFiles: [String: FileRecord], identicalFiles: Set<String>, samePathDifferentSizeFiles: Set<String>, sameSizeDifferentPathFiles: Set<String>, sameSizeCounterpartsByPath: [String: [FileRecord]], sameSizeCounterpartSideByPath: [String: CompareSide], discoveredLeftCount: Int, discoveredRightCount: Int, progress: @escaping @Sendable (CompareProgress) -> Void) throws -> DirectoryIndex {
        let root = MutableDirectoryNode(name: "", path: "")
        let allPaths = Set(leftFiles.keys).union(rightFiles.keys).sorted(by: compareRelativePaths)
        var processedIndexCount = 0

        // 1. 只把目录结构和每个目录的直接子项写入索引，避免构建整棵文件树。
        for path in allPaths {
            try Task.checkCancellation()
            let leftFile = leftFiles[path]
            let rightFile = rightFiles[path]
            let status = statusForPath(path: path, leftFile: leftFile, rightFile: rightFile, identicalFiles: identicalFiles, samePathDifferentSizeFiles: samePathDifferentSizeFiles, sameSizeDifferentPathFiles: sameSizeDifferentPathFiles)
            let pathComponents = path.split(separator: "/").map(String.init)
            guard let fileName = pathComponents.last else {
                continue
            }

            let item = DirectoryItem(
                path: path,
                name: fileName,
                directoryPath: directoryPath(for: path),
                isDirectory: false,
                status: status,
                leftFile: leftFile,
                rightFile: rightFile,
                counterpartFiles: sameSizeCounterpartsByPath[path] ?? [],
                counterpartSide: sameSizeCounterpartSideByPath[path]
            )

            root.insertFile(pathComponents: pathComponents, item: item)
            processedIndexCount += 1

            if shouldReportProgress(current: processedIndexCount, total: allPaths.count) {
                progress(
                    CompareProgress(
                        phase: .buildingIndex,
                        currentPath: path,
                        leftDiscoveredCount: discoveredLeftCount,
                        rightDiscoveredCount: discoveredRightCount,
                        processedCount: processedIndexCount,
                        totalCount: allPaths.count
                    )
                )
            }
        }

        var itemsByPath: [String: [DirectoryItem]] = [:]
        let roots = root.children.values.map { $0.freeze(into: &itemsByPath, sorter: compareDirectoryItems) }.sorted(by: compareDirectoryNodes)
        itemsByPath[""] = root.listingItems(sortedChildren: roots).sorted(by: compareDirectoryItems)
        return DirectoryIndex(roots: roots, itemsByPath: itemsByPath)
    }

    private func shouldReportProgress(current: Int, total: Int?) -> Bool {
        if let total, current >= total {
            return true
        }

        return current.isMultiple(of: 128)
    }

    private func makeSnapshotProgress(side: CompareSide, currentPath: String?, discoveredFileCount: Int, otherSideCount: Int) -> CompareProgress {
        switch side {
        case .left:
            return CompareProgress(phase: .scanningLeft, currentPath: currentPath, leftDiscoveredCount: discoveredFileCount, rightDiscoveredCount: otherSideCount, processedCount: discoveredFileCount, totalCount: nil)
        case .right:
            return CompareProgress(phase: .scanningRight, currentPath: currentPath, leftDiscoveredCount: otherSideCount, rightDiscoveredCount: discoveredFileCount, processedCount: discoveredFileCount, totalCount: nil)
        }
    }

    private func statusForPath(path: String, leftFile: FileRecord?, rightFile: FileRecord?, identicalFiles: Set<String>, samePathDifferentSizeFiles: Set<String>, sameSizeDifferentPathFiles: Set<String>) -> DiffStatus {
        if identicalFiles.contains(path) {
            return .identical
        }

        if samePathDifferentSizeFiles.contains(path) {
            return .samePathDifferentSize
        }

        if sameSizeDifferentPathFiles.contains(path) {
            return .sameSizeDifferentPath
        }

        if leftFile != nil, rightFile == nil {
            return .leftOnly
        }

        if leftFile == nil, rightFile != nil {
            return .rightOnly
        }

        return .mixed
    }

    private func directoryPath(for relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }

    private func pruneEmptyDirectories(from directoryURL: URL, root: URL) throws {
        var currentURL = directoryURL.standardizedFileURL
        let rootURL = root.standardizedFileURL

        while currentURL.path != rootURL.path {
            let contents = try fileManager.contentsOfDirectory(atPath: currentURL.path)
            guard contents.isEmpty else {
                return
            }

            try fileManager.removeItem(at: currentURL)
            currentURL.deleteLastPathComponent()
        }
    }

    private func sortFiles(_ files: [FileRecord]) -> [FileRecord] {
        files.sorted(by: compareFiles)
    }

    private func compareFiles(_ lhs: FileRecord, _ rhs: FileRecord) -> Bool {
        compareRelativePaths(lhs.relativePath, rhs.relativePath)
    }

    private func comparePairs(_ lhs: PathPair, _ rhs: PathPair) -> Bool {
        compareRelativePaths(lhs.relativePath, rhs.relativePath)
    }

    private func compareDirectoryNodes(_ lhs: DirectoryNode, _ rhs: DirectoryNode) -> Bool {
        compareNames(lhs.name, rhs.name)
    }

    private func compareDirectoryItems(_ lhs: DirectoryItem, _ rhs: DirectoryItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }

        return compareNames(lhs.name, rhs.name)
    }

    private func compareRelativePaths(_ lhs: String, _ rhs: String) -> Bool {
        let leftComponents = lhs.split(separator: "/").map(String.init)
        let rightComponents = rhs.split(separator: "/").map(String.init)
        let minCount = min(leftComponents.count, rightComponents.count)

        for index in 0..<minCount {
            if leftComponents[index] == rightComponents[index] {
                continue
            }

            return compareNames(leftComponents[index], rightComponents[index])
        }

        return leftComponents.count < rightComponents.count
    }

    private func compareNames(_ lhs: String, _ rhs: String) -> Bool {
        let leftCategory = sortCategory(for: lhs)
        let rightCategory = sortCategory(for: rhs)

        if leftCategory != rightCategory {
            return leftCategory < rightCategory
        }

        let leftKey = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let rightKey = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let result = leftKey.compare(rightKey, options: [.widthInsensitive, .forcedOrdering], locale: Locale(identifier: "zh_Hans_CN"))
        return result == .orderedSame ? lhs < rhs : result == .orderedAscending
    }

    private func sortCategory(for name: String) -> Int {
        for scalar in name.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if scalar.isASCII {
                return 0
            }

            if (0x4E00...0x9FFF).contains(scalar.value) {
                return 2
            }

            return 1
        }

        return 0
    }
}

enum FolderCompareError: LocalizedError {
    case unableToEnumerateFolder(String)
    case invalidFileOperation(String)

    var errorDescription: String? {
        switch self {
        case let .unableToEnumerateFolder(path):
            "无法遍历目录：\(path)"
        case let .invalidFileOperation(message):
            message
        }
    }
}

private struct DirectoryIndex {
    let roots: [DirectoryNode]
    let itemsByPath: [String: [DirectoryItem]]
}

private final class MutableDirectoryNode {
    let name: String
    let path: String
    var fileItems: [DirectoryItem] = []
    var children: [String: MutableDirectoryNode] = [:]
    var containedStatuses: Set<DiffStatus> = []

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func insertFile(pathComponents: [String], item: DirectoryItem) {
        containedStatuses.insert(item.status)

        guard pathComponents.count > 1, let head = pathComponents.first else {
            fileItems.append(item)
            return
        }

        let childPath = path.isEmpty ? head : path + "/" + head
        let child = children[head] ?? MutableDirectoryNode(name: head, path: childPath)
        children[head] = child
        child.insertFile(pathComponents: Array(pathComponents.dropFirst()), item: item)
        containedStatuses.formUnion(child.containedStatuses)
    }

    func freeze(into itemsByPath: inout [String: [DirectoryItem]], sorter: (DirectoryItem, DirectoryItem) -> Bool) -> DirectoryNode {
        let frozenChildren = children.values.map { $0.freeze(into: &itemsByPath, sorter: sorter) }.sorted { lhs, rhs in
            sorter(
                DirectoryItem(path: lhs.path, name: lhs.name, directoryPath: path, isDirectory: true, status: lhs.status, leftFile: nil, rightFile: nil, counterpartFiles: [], counterpartSide: nil),
                DirectoryItem(path: rhs.path, name: rhs.name, directoryPath: path, isDirectory: true, status: rhs.status, leftFile: nil, rightFile: nil, counterpartFiles: [], counterpartSide: nil)
            )
        }

        let status = resolveStatus(childStatuses: frozenChildren.map(\.status), ownStatuses: fileItems.map(\.status))
        let combinedStatuses = containedStatuses.union(frozenChildren.flatMap(\.containedStatuses))
        itemsByPath[path] = listingItems(sortedChildren: frozenChildren).sorted(by: sorter)

        return DirectoryNode(path: path, name: name, status: status, containedStatuses: combinedStatuses, children: frozenChildren)
    }

    func listingItems(sortedChildren: [DirectoryNode]) -> [DirectoryItem] {
        let directoryItems = sortedChildren.map {
            DirectoryItem(path: $0.path, name: $0.name, directoryPath: path, isDirectory: true, status: $0.status, leftFile: nil, rightFile: nil, counterpartFiles: [], counterpartSide: nil)
        }

        return directoryItems + fileItems
    }

    private func resolveStatus(childStatuses: [DiffStatus], ownStatuses: [DiffStatus]) -> DiffStatus {
        let statusSet = Set(childStatuses + ownStatuses)
        if statusSet.isEmpty {
            return .folder
        }

        if statusSet.count == 1, let onlyStatus = statusSet.first {
            return onlyStatus == .folder ? .mixed : onlyStatus
        }

        return .mixed
    }
}
