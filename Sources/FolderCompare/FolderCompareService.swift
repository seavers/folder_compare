import Foundation

struct FolderCompareService {
    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

    func compare(leftFolder: URL, rightFolder: URL) throws -> CompareResult {
        let leftSnapshot = try snapshot(for: leftFolder)
        let rightSnapshot = try snapshot(for: rightFolder)

        let leftPaths = Set(leftSnapshot.filesByPath.keys)
        let rightPaths = Set(rightSnapshot.filesByPath.keys)
        let commonPaths = leftPaths.intersection(rightPaths).sorted(by: compareRelativePaths)

        var identicalFiles: [PathPair] = []
        var samePathDifferentSizeFiles: [PathPair] = []

        // 1. 先按相对路径做一轮精确匹配，识别完全一致和同路径不同大小的文件。
        for path in commonPaths {
            guard let leftFile = leftSnapshot.filesByPath[path], let rightFile = rightSnapshot.filesByPath[path] else {
                continue
            }

            let pair = PathPair(relativePath: path, left: leftFile, right: rightFile)
            if leftFile.size == rightFile.size {
                identicalFiles.append(pair)
            } else {
                samePathDifferentSizeFiles.append(pair)
            }
        }

        let leftUnmatchedPaths = leftPaths.subtracting(commonPaths)
        let rightUnmatchedPaths = rightPaths.subtracting(commonPaths)

        let leftUnmatchedFiles = leftUnmatchedPaths.compactMap { leftSnapshot.filesByPath[$0] }
        let rightUnmatchedFiles = rightUnmatchedPaths.compactMap { rightSnapshot.filesByPath[$0] }

        let leftGroupsBySize = Dictionary(grouping: leftUnmatchedFiles, by: \.size)
        let rightGroupsBySize = Dictionary(grouping: rightUnmatchedFiles, by: \.size)
        let sameSizes = Set(leftGroupsBySize.keys).intersection(rightGroupsBySize.keys).sorted()

        var sameSizeDifferentPathGroups: [SizeMatchGroup] = []
        var sameSizeDifferentPathSet: Set<String> = []

        // 2. 再从未命中路径的文件中，按大小归类，识别“大小一致但路径不同”的文件组。
        for size in sameSizes {
            let leftFiles = sortFiles(leftGroupsBySize[size] ?? [])
            let rightFiles = sortFiles(rightGroupsBySize[size] ?? [])

            guard !leftFiles.isEmpty, !rightFiles.isEmpty else {
                continue
            }

            sameSizeDifferentPathGroups.append(SizeMatchGroup(size: size, leftFiles: leftFiles, rightFiles: rightFiles))
            leftFiles.forEach { sameSizeDifferentPathSet.insert($0.relativePath) }
            rightFiles.forEach { sameSizeDifferentPathSet.insert($0.relativePath) }
        }

        // 3. 剩余没有任何对应关系的文件，归入左右独有结果，便于用户快速定位缺失项。
        let leftOnlyFiles = leftUnmatchedFiles
            .filter { !sameSizeDifferentPathSet.contains($0.relativePath) }
            .sorted(by: compareFiles)

        let rightOnlyFiles = rightUnmatchedFiles
            .filter { !sameSizeDifferentPathSet.contains($0.relativePath) }
            .sorted(by: compareFiles)

        let treeRoots = buildTree(
            leftFiles: leftSnapshot.filesByPath,
            rightFiles: rightSnapshot.filesByPath,
            identicalFiles: Set(identicalFiles.map(\.relativePath)),
            samePathDifferentSizeFiles: Set(samePathDifferentSizeFiles.map(\.relativePath)),
            sameSizeDifferentPathFiles: sameSizeDifferentPathSet
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
            treeRoots: treeRoots,
            summary: summary
        )
    }

    func deleteLeftOnlyFile(_ file: FileRecord, leftRoot: URL) throws {
        let fileURL = URL(fileURLWithPath: file.absolutePath)
        guard fileURL.path.hasPrefix(leftRoot.path + "/") else {
            throw FolderCompareError.invalidFileOperation("目标文件不在左侧目录下：\(file.relativePath)")
        }

        // 1. 删除左侧独有文件，避免误删比较范围外的内容。
        try fileManager.removeItem(at: fileURL)

        // 2. 自底向上清理空目录，保持左侧目录结构整洁，但不会越过根目录。
        try pruneEmptyDirectories(from: fileURL.deletingLastPathComponent(), root: leftRoot)
    }

    func copyRightOnlyFileToLeft(_ file: FileRecord, leftRoot: URL) throws {
        let sourceURL = URL(fileURLWithPath: file.absolutePath)
        let destinationURL = leftRoot.appendingPathComponent(file.relativePath)

        // 1. 先确保目标父目录存在，再执行复制，保证右侧独有文件能完整落入左侧对应层级。
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw FolderCompareError.invalidFileOperation("左侧已存在同名文件：\(file.relativePath)")
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        // 2. 复制完成后补齐创建时间和修改时间，保证时间戳与右侧源文件一致。
        let sourceValues = try sourceURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        var destinationValues = URLResourceValues()
        destinationValues.creationDate = sourceValues.creationDate
        destinationValues.contentModificationDate = sourceValues.contentModificationDate
        var mutableDestinationURL = destinationURL
        try mutableDestinationURL.setResourceValues(destinationValues)
    }

    private func snapshot(for folder: URL) throws -> FolderSnapshot {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles]) else {
            throw FolderCompareError.unableToEnumerateFolder(folder.path)
        }

        var filesByPath: [String: FileRecord] = [:]

        // 1. 递归遍历目录，只收集常规文件，避免文件夹参与大小比较。
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: folder.path + "/", with: "")
            let size = UInt64(values.fileSize ?? 0)
            filesByPath[relativePath] = FileRecord(relativePath: relativePath, absolutePath: fileURL.path, size: size)
        }

        return FolderSnapshot(rootPath: folder.path, filesByPath: filesByPath)
    }

    private func buildTree(leftFiles: [String: FileRecord], rightFiles: [String: FileRecord], identicalFiles: Set<String>, samePathDifferentSizeFiles: Set<String>, sameSizeDifferentPathFiles: Set<String>) -> [FileTreeNode] {
        let root = MutableTreeNode(name: "", path: "", isDirectory: true)
        let allPaths = Set(leftFiles.keys).union(rightFiles.keys).sorted(by: compareRelativePaths)

        // 1. 逐个相对路径写入树节点，为后续目录聚合展示准备结构。
        for path in allPaths {
            let leftFile = leftFiles[path]
            let rightFile = rightFiles[path]
            let status = statusForPath(path: path, leftFile: leftFile, rightFile: rightFile, identicalFiles: identicalFiles, samePathDifferentSizeFiles: samePathDifferentSizeFiles, sameSizeDifferentPathFiles: sameSizeDifferentPathFiles)

            root.insert(
                pathComponents: path.split(separator: "/").map(String.init),
                fullPath: path,
                leftAbsolutePath: leftFile?.absolutePath,
                rightAbsolutePath: rightFile?.absolutePath,
                leftSize: leftFile?.size,
                rightSize: rightFile?.size,
                status: status
            )
        }

        // 2. 完成文件节点插入后，自底向上计算目录状态，输出适合 SwiftUI 展示的不可变树结构。
        return root.children
            .map(\.value)
            .map { $0.freeze(parentPath: "") }
            .sorted(by: compareTreeNodes)
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

    private func pruneEmptyDirectories(from directoryURL: URL, root: URL) throws {
        var currentURL = directoryURL

        while currentURL.path != root.path {
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

    private func compareTreeNodes(_ lhs: FileTreeNode, _ rhs: FileTreeNode) -> Bool {
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

        if result == .orderedSame {
            return lhs < rhs
        }

        return result == .orderedAscending
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

private final class MutableTreeNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var leftAbsolutePath: String?
    var rightAbsolutePath: String?
    var leftSize: UInt64?
    var rightSize: UInt64?
    var status: DiffStatus
    var children: [String: MutableTreeNode]

    init(name: String, path: String, isDirectory: Bool, leftAbsolutePath: String? = nil, rightAbsolutePath: String? = nil, leftSize: UInt64? = nil, rightSize: UInt64? = nil, status: DiffStatus = .folder, children: [String: MutableTreeNode] = [:]) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.leftAbsolutePath = leftAbsolutePath
        self.rightAbsolutePath = rightAbsolutePath
        self.leftSize = leftSize
        self.rightSize = rightSize
        self.status = status
        self.children = children
    }

    func insert(pathComponents: [String], fullPath: String, leftAbsolutePath: String?, rightAbsolutePath: String?, leftSize: UInt64?, rightSize: UInt64?, status: DiffStatus) {
        guard let head = pathComponents.first else {
            return
        }

        if pathComponents.count == 1 {
            children[head] = MutableTreeNode(name: head, path: fullPath, isDirectory: false, leftAbsolutePath: leftAbsolutePath, rightAbsolutePath: rightAbsolutePath, leftSize: leftSize, rightSize: rightSize, status: status)
            return
        }

        let childPath = path.isEmpty ? head : path + "/" + head
        let child = children[head] ?? MutableTreeNode(name: head, path: childPath, isDirectory: true)
        children[head] = child
        child.insert(pathComponents: Array(pathComponents.dropFirst()), fullPath: fullPath, leftAbsolutePath: leftAbsolutePath, rightAbsolutePath: rightAbsolutePath, leftSize: leftSize, rightSize: rightSize, status: status)
    }

    func freeze(parentPath: String) -> FileTreeNode {
        let childNodes = children.values
            .map { $0.freeze(parentPath: path) }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }

                return sortName($0.name, $1.name)
            }

        let resolvedPath = path.isEmpty ? name : path
        let resolvedStatus: DiffStatus

        if isDirectory {
            let childStatuses = Set(childNodes.map(\.status))
            if childStatuses.count == 1, let onlyStatus = childStatuses.first {
                resolvedStatus = onlyStatus == .folder ? .folder : onlyStatus
            } else {
                resolvedStatus = childStatuses.isEmpty ? .folder : .mixed
            }
        } else {
            resolvedStatus = status
        }

        return FileTreeNode(
            path: resolvedPath,
            name: name,
            fullPath: parentPath.isEmpty ? resolvedPath : parentPath + "/" + name,
            isDirectory: isDirectory,
            status: resolvedStatus,
            leftAbsolutePath: leftAbsolutePath,
            rightAbsolutePath: rightAbsolutePath,
            leftSize: leftSize,
            rightSize: rightSize,
            children: childNodes
        )
    }

    private func sortName(_ lhs: String, _ rhs: String) -> Bool {
        let leftCategory = sortCategory(for: lhs)
        let rightCategory = sortCategory(for: rhs)

        if leftCategory != rightCategory {
            return leftCategory < rightCategory
        }

        let leftKey = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let rightKey = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let result = leftKey.compare(rightKey, options: [.widthInsensitive, .forcedOrdering], locale: Locale(identifier: "zh_Hans_CN"))

        if result == .orderedSame {
            return lhs < rhs
        }

        return result == .orderedAscending
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
