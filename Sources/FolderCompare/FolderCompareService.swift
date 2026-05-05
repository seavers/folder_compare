import Foundation

struct FolderCompareService {
    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey]

    func compare(leftFolder: URL, rightFolder: URL) throws -> CompareResult {
        let leftSnapshot = try snapshot(for: leftFolder)
        let rightSnapshot = try snapshot(for: rightFolder)

        let leftPaths = Set(leftSnapshot.filesByPath.keys)
        let rightPaths = Set(rightSnapshot.filesByPath.keys)
        let commonPaths = leftPaths.intersection(rightPaths).sorted()

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
            let leftFiles = (leftGroupsBySize[size] ?? []).sorted { $0.relativePath < $1.relativePath }
            let rightFiles = (rightGroupsBySize[size] ?? []).sorted { $0.relativePath < $1.relativePath }

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
            .sorted { $0.relativePath < $1.relativePath }

        let rightOnlyFiles = rightUnmatchedFiles
            .filter { !sameSizeDifferentPathSet.contains($0.relativePath) }
            .sorted { $0.relativePath < $1.relativePath }

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
            identicalFiles: identicalFiles.sorted { $0.relativePath < $1.relativePath },
            samePathDifferentSizeFiles: samePathDifferentSizeFiles.sorted { $0.relativePath < $1.relativePath },
            sameSizeDifferentPathGroups: sameSizeDifferentPathGroups.sorted { $0.size < $1.size },
            leftOnlyFiles: leftOnlyFiles,
            rightOnlyFiles: rightOnlyFiles,
            treeRoots: treeRoots,
            summary: summary
        )
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
        let allPaths = Set(leftFiles.keys).union(rightFiles.keys).sorted()

        // 1. 逐个相对路径写入树节点，为后续目录聚合展示准备结构。
        for path in allPaths {
            let leftFile = leftFiles[path]
            let rightFile = rightFiles[path]
            let status = statusForPath(path: path, leftFile: leftFile, rightFile: rightFile, identicalFiles: identicalFiles, samePathDifferentSizeFiles: samePathDifferentSizeFiles, sameSizeDifferentPathFiles: sameSizeDifferentPathFiles)

            root.insert(pathComponents: path.split(separator: "/").map(String.init), fullPath: path, leftSize: leftFile?.size, rightSize: rightFile?.size, status: status)
        }

        // 2. 完成文件节点插入后，自底向上计算目录状态，输出适合 SwiftUI 展示的不可变树结构。
        return root.children
            .map(\.value)
            .map { $0.freeze(parentPath: "") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
}

enum FolderCompareError: LocalizedError {
    case unableToEnumerateFolder(String)

    var errorDescription: String? {
        switch self {
        case let .unableToEnumerateFolder(path):
            "无法遍历目录：\(path)"
        }
    }
}

private final class MutableTreeNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var leftSize: UInt64?
    var rightSize: UInt64?
    var status: DiffStatus
    var children: [String: MutableTreeNode]

    init(name: String, path: String, isDirectory: Bool, leftSize: UInt64? = nil, rightSize: UInt64? = nil, status: DiffStatus = .folder, children: [String: MutableTreeNode] = [:]) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.leftSize = leftSize
        self.rightSize = rightSize
        self.status = status
        self.children = children
    }

    func insert(pathComponents: [String], fullPath: String, leftSize: UInt64?, rightSize: UInt64?, status: DiffStatus) {
        guard let head = pathComponents.first else {
            return
        }

        if pathComponents.count == 1 {
            children[head] = MutableTreeNode(name: head, path: fullPath, isDirectory: false, leftSize: leftSize, rightSize: rightSize, status: status)
            return
        }

        let childPath = path.isEmpty ? head : path + "/" + head
        let child = children[head] ?? MutableTreeNode(name: head, path: childPath, isDirectory: true)
        children[head] = child
        child.insert(pathComponents: Array(pathComponents.dropFirst()), fullPath: fullPath, leftSize: leftSize, rightSize: rightSize, status: status)
    }

    func freeze(parentPath: String) -> FileTreeNode {
        let childNodes = children.values
            .map { $0.freeze(parentPath: path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

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
            leftSize: leftSize,
            rightSize: rightSize,
            children: childNodes
        )
    }
}
