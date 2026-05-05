import Foundation

struct FileRecord: Hashable, Identifiable, Sendable {
    let relativePath: String
    let absolutePath: String
    let size: UInt64

    var id: String { relativePath + "#" + absolutePath }
    var fileName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
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

    var compactDisplayName: String {
        switch self {
        case .identical:
            "一致"
        case .samePathDifferentSize:
            "同路径异大小"
        case .sameSizeDifferentPath:
            "同大小异路径"
        case .leftOnly:
            "仅左侧"
        case .rightOnly:
            "仅右侧"
        case .folder:
            "文件夹"
        case .mixed:
            "混合"
        }
    }
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

    var opposite: CompareSide {
        switch self {
        case .left:
            .right
        case .right:
            .left
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

struct CompareSummary: Sendable {
    let leftCount: Int
    let rightCount: Int
    let identicalCount: Int
    let samePathDifferentSizeCount: Int
    let sameSizeDifferentPathCount: Int
    let leftOnlyCount: Int
    let rightOnlyCount: Int
}

enum CompareProgressPhase: String, Sendable {
    case preparing
    case scanningLeft
    case scanningRight
    case matchingPaths
    case groupingSameSize
    case buildingIndex

    var displayName: String {
        switch self {
        case .preparing:
            "准备对比"
        case .scanningLeft:
            "扫描左侧"
        case .scanningRight:
            "扫描右侧"
        case .matchingPaths:
            "按路径比对"
        case .groupingSameSize:
            "按大小归组"
        case .buildingIndex:
            "生成结果索引"
        }
    }
}

struct CompareProgress: Sendable {
    let phase: CompareProgressPhase
    let currentPath: String?
    let leftDiscoveredCount: Int
    let rightDiscoveredCount: Int
    let processedCount: Int
    let totalCount: Int?

    var fractionCompleted: Double? {
        guard let totalCount, totalCount > 0 else {
            return nil
        }

        return min(max(Double(processedCount) / Double(totalCount), 0), 1)
    }
}

struct CompareResult: Sendable {
    let leftRootPath: String
    let rightRootPath: String
    let identicalFiles: [PathPair]
    let samePathDifferentSizeFiles: [PathPair]
    let sameSizeDifferentPathGroups: [SizeMatchGroup]
    let leftOnlyFiles: [FileRecord]
    let rightOnlyFiles: [FileRecord]
    let directoryRoots: [DirectoryNode]
    let directoryItemsByPath: [String: [DirectoryItem]]
    let summary: CompareSummary
}

struct DirectoryNode: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let status: DiffStatus
    let containedStatuses: Set<DiffStatus>
    let children: [DirectoryNode]

    var id: String { path }
}

struct DirectoryItem: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let directoryPath: String
    let isDirectory: Bool
    let status: DiffStatus
    let leftFile: FileRecord?
    let rightFile: FileRecord?
    let counterpartFiles: [FileRecord]
    let counterpartSide: CompareSide?

    var id: String { path }
    var leftSize: UInt64? { leftFile?.size }
    var rightSize: UInt64? { rightFile?.size }
    var leftAbsolutePath: String? { leftFile?.absolutePath }
    var rightAbsolutePath: String? { rightFile?.absolutePath }

    var primarySide: CompareSide? {
        if leftFile != nil, rightFile == nil {
            return .left
        }

        if leftFile == nil, rightFile != nil {
            return .right
        }

        return nil
    }
}

struct FolderSnapshot: Sendable {
    let rootPath: String
    let filesByPath: [String: FileRecord]
}

struct CompareHistoryItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let leftPath: String
    let rightPath: String
    let comparedAt: Date

    init(id: UUID = UUID(), leftPath: String, rightPath: String, comparedAt: Date = Date()) {
        self.id = id
        self.leftPath = leftPath
        self.rightPath = rightPath
        self.comparedAt = comparedAt
    }
}

struct PendingDeleteAction: Identifiable, Hashable {
    let side: CompareSide
    let file: FileRecord

    var id: String { side.rawValue + "#" + file.id }
}
