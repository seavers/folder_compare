import Foundation

struct FileRecord: Hashable, Identifiable, Sendable {
    let relativePath: String
    let absolutePath: String
    let size: UInt64

    var id: String { relativePath + "#" + absolutePath }
}

enum DiffStatus: String, CaseIterable, Identifiable, Sendable {
    case identical
    case samePathDifferentSize
    case sameSizeDifferentPath
    case leftOnly
    case rightOnly
    case folder
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .identical:
            "路径和大小一致"
        case .samePathDifferentSize:
            "路径一致大小不同"
        case .sameSizeDifferentPath:
            "大小一致路径不同"
        case .leftOnly:
            "仅左侧存在"
        case .rightOnly:
            "仅右侧存在"
        case .folder:
            "文件夹"
        case .mixed:
            "混合状态"
        }
    }
}

struct PathPair: Identifiable, Hashable, Sendable {
    let relativePath: String
    let left: FileRecord
    let right: FileRecord

    var id: String { relativePath }
}

struct SizeMatchGroup: Identifiable, Hashable, Sendable {
    let size: UInt64
    let leftFiles: [FileRecord]
    let rightFiles: [FileRecord]

    var id: String {
        let leftKey = leftFiles.map(\.relativePath).sorted().joined(separator: "|")
        let rightKey = rightFiles.map(\.relativePath).sorted().joined(separator: "|")
        return "\(size)#\(leftKey)#\(rightKey)"
    }
}

struct SideOnlyFile: Identifiable, Hashable, Sendable {
    let side: CompareSide
    let file: FileRecord

    var id: String { side.rawValue + "#" + file.id }
}

enum CompareSide: String, Hashable, Sendable {
    case left
    case right

    var displayName: String {
        switch self {
        case .left:
            "左侧"
        case .right:
            "右侧"
        }
    }
}

struct CompareSummary: Sendable {
    let leftCount: Int
    let rightCount: Int
    let identicalCount: Int
    let samePathDifferentSizeCount: Int
    let sameSizeDifferentPathCount: Int
    let leftOnlyCount: Int
    let rightOnlyCount: Int
}

struct CompareResult: Sendable {
    let leftRootPath: String
    let rightRootPath: String
    let identicalFiles: [PathPair]
    let samePathDifferentSizeFiles: [PathPair]
    let sameSizeDifferentPathGroups: [SizeMatchGroup]
    let leftOnlyFiles: [FileRecord]
    let rightOnlyFiles: [FileRecord]
    let treeRoots: [FileTreeNode]
    let summary: CompareSummary
}

struct FileTreeNode: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let status: DiffStatus
    let leftSize: UInt64?
    let rightSize: UInt64?
    let children: [FileTreeNode]

    var id: String { fullPath }
    var childNodes: [FileTreeNode]? { children.isEmpty ? nil : children }
}

struct FolderSnapshot: Sendable {
    let rootPath: String
    let filesByPath: [String: FileRecord]
}
