import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: FolderCompareViewModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                CompactToolbarView(viewModel: viewModel)
                SummaryStripView(result: viewModel.compareResult, isComparing: viewModel.isComparing)
                ResultWorkspaceView(viewModel: viewModel)
            }
            .padding(14)
        }
        .overlay(alignment: .top) {
            if let message = overlayMessage {
                Text(message)
                    .font(AppTypography.smallStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.74))
                    .clipShape(Capsule())
                    .padding(.top, 10)
            }
        }
    }

    private var overlayMessage: String? {
        if let errorMessage = viewModel.errorMessage {
            return errorMessage
        }

        return viewModel.activeOperationMessage
    }
}

private struct CompactToolbarView: View {
    @ObservedObject var viewModel: FolderCompareViewModel
    @State private var isHistoryPresented = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("文件夹对比工具")
                        .font(AppTypography.title)

                    Text("对比路径与大小")
                        .font(AppTypography.small)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                FolderInputField(title: "左侧", path: $viewModel.leftFolderPath, tint: .blue) {
                    viewModel.chooseFolder(for: .left)
                }

                FolderInputField(title: "右侧", path: $viewModel.rightFolderPath, tint: .indigo) {
                    viewModel.chooseFolder(for: .right)
                }

                Button {
                    viewModel.compareFolders()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isComparing {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(viewModel.isComparing ? "处理中" : "开始对比")
                            .font(AppTypography.smallStrong)
                    }
                    .frame(minWidth: 94)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isComparing)

                Button("历史记录") {
                    isHistoryPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .font(AppTypography.smallStrong)
                .disabled(viewModel.historyItems.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .panelSurface()
        .sheet(isPresented: $isHistoryPresented) {
            HistorySheetView(viewModel: viewModel)
        }
    }
}

private struct FolderInputField: View {
    let title: String
    @Binding var path: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)

            TextField("请选择文件夹", text: $path)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            Button("浏览", action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .font(AppTypography.small)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryStripView: View {
    let result: CompareResult?
    let isComparing: Bool

    var body: some View {
        Group {
            if let result {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SummaryChip(title: "左侧", value: result.summary.leftCount, tint: .blue)
                        SummaryChip(title: "右侧", value: result.summary.rightCount, tint: .indigo)
                        SummaryChip(title: "一致", value: result.summary.identicalCount, tint: .green)
                        SummaryChip(title: "同路径异大小", value: result.summary.samePathDifferentSizeCount, tint: .orange)
                        SummaryChip(title: "同大小异路径", value: result.summary.sameSizeDifferentPathCount, tint: .mint)
                        SummaryChip(title: "仅左侧", value: result.summary.leftOnlyCount, tint: .red)
                        SummaryChip(title: "仅右侧", value: result.summary.rightOnlyCount, tint: .pink)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack(spacing: 8) {
                    if isComparing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(isComparing ? "正在扫描并生成对比结果..." : "选择左右目录后开始对比。")
                        .font(AppTypography.small)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelSurface()
    }
}

private struct SummaryChip: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTypography.small)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct ResultWorkspaceView: View {
    @ObservedObject var viewModel: FolderCompareViewModel
    @State private var viewMode = ViewMode.tree
    @State private var deleteCandidate: FileRecord?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("结果")
                    .font(AppTypography.section)

                if let result = viewModel.compareResult {
                    Text("\(result.summary.leftCount + result.summary.rightCount) 个文件")
                        .font(AppTypography.small)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker("视图", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Group {
                if let result = viewModel.compareResult {
                    switch viewMode {
                    case .tree:
                        TreeSplitResultView(result: result, onDeleteRequest: { deleteCandidate = $0 }, onCopyRequest: viewModel.copyRightOnlyFileToLeft)
                    case .flat:
                        FlatResultView(result: result, onDeleteRequest: { deleteCandidate = $0 }, onCopyRequest: viewModel.copyRightOnlyFileToLeft)
                    }
                } else {
                    EmptyWorkspaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .panelSurface()
        .confirmationDialog(
            "删除左侧文件？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            presenting: deleteCandidate
        ) { file in
            Button("删除", role: .destructive) {
                viewModel.deleteLeftOnlyFile(file)
                deleteCandidate = nil
            }

            Button("取消", role: .cancel) {}
        } message: { file in
            Text(file.relativePath)
        }
    }
}

private enum ViewMode: String, CaseIterable, Identifiable {
    case tree
    case flat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tree:
            "树状"
        case .flat:
            "扁平"
        }
    }
}

private struct EmptyWorkspaceView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("暂无结果")
                .font(AppTypography.section)

            Text("主区域会优先展示可操作的对比列表。")
                .font(AppTypography.small)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TreeSplitResultView: View {
    let result: CompareResult
    let onDeleteRequest: (FileRecord) -> Void
    let onCopyRequest: (FileRecord) -> Void
    @State private var expandedNodes: Set<String> = []
    @State private var selectedDirectoryPath = ""

    private var treeIdentity: String {
        [
            result.leftRootPath,
            result.rightRootPath,
            "\(result.summary.leftCount)",
            "\(result.summary.rightCount)",
            "\(result.summary.leftOnlyCount)",
            "\(result.summary.rightOnlyCount)"
        ].joined(separator: "|")
    }

    var body: some View {
        HSplitView {
            DirectorySidebarView(directoryRoots: directoryRoots, selectedDirectoryPath: $selectedDirectoryPath, expandedNodes: $expandedNodes)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            DirectoryDetailView(
                directoryPath: selectedDirectoryPath,
                nodes: currentNodes,
                onDeleteRequest: onDeleteRequest,
                onCopyRequest: onCopyRequest,
                onOpenDirectory: openDirectory
            )
            .frame(minWidth: 540)
        }
        .id(treeIdentity)
    }

    private var directoryRoots: [FileTreeNode] {
        result.treeRoots.filter(\.isDirectory)
    }

    private var currentNodes: [FileTreeNode] {
        if selectedDirectoryPath.isEmpty {
            return result.treeRoots
        }

        return findDirectoryNode(path: selectedDirectoryPath, in: result.treeRoots)?.children ?? []
    }

    private func findDirectoryNode(path: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes where node.isDirectory {
            if node.path == path {
                return node
            }

            if let matched = findDirectoryNode(path: path, in: node.children) {
                return matched
            }
        }

        return nil
    }

    private func openDirectory(_ path: String) {
        guard !path.isEmpty else {
            selectedDirectoryPath = ""
            return
        }

        selectedDirectoryPath = path
        expandAncestors(for: path)
    }

    private func expandAncestors(for path: String) {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else {
            return
        }

        var current = ""
        for component in components.dropLast() {
            current = current.isEmpty ? component : current + "/" + component
            expandedNodes.insert(current)
        }
    }
}

private struct DirectorySidebarView: View {
    let directoryRoots: [FileTreeNode]
    @Binding var selectedDirectoryPath: String
    @Binding var expandedNodes: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目录树")
                .font(AppTypography.smallStrong)
                .padding(.horizontal, 10)

            Button {
                selectedDirectoryPath = ""
            } label: {
                HStack {
                    Image(systemName: "tray.full")
                    Text("根目录")
                }
                .font(AppTypography.smallStrong)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(selectedDirectoryPath.isEmpty ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(directoryRoots) { node in
                        DirectoryTreeRowView(node: node, depth: 0, selectedDirectoryPath: $selectedDirectoryPath, expandedNodes: $expandedNodes)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DirectoryTreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var selectedDirectoryPath: String
    @Binding var expandedNodes: Set<String>

    private var isExpanded: Bool {
        expandedNodes.contains(node.path)
    }

    private var isSelected: Bool {
        selectedDirectoryPath == node.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Color.clear.frame(width: CGFloat(depth) * 12)

                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                Button {
                    selectedDirectoryPath = node.path
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color(nsColor: .systemYellow))

                        Text(node.name)
                            .font(AppTypography.nodeName)

                        Spacer(minLength: 4)

                        StatusBadge(status: node.status)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if isExpanded {
                ForEach(node.children.filter(\.isDirectory)) { child in
                    DirectoryTreeRowView(node: child, depth: depth + 1, selectedDirectoryPath: $selectedDirectoryPath, expandedNodes: $expandedNodes)
                }
            }
        }
    }

    private func toggleExpanded() {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            if isExpanded {
                expandedNodes.remove(node.path)
            } else {
                expandedNodes.insert(node.path)
            }
        }
    }
}

private struct DirectoryDetailView: View {
    let directoryPath: String
    let nodes: [FileTreeNode]
    let onDeleteRequest: (FileRecord) -> Void
    let onCopyRequest: (FileRecord) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(detailTitle)
                    .font(AppTypography.smallStrong)

                Spacer(minLength: 12)

                Text("\(nodes.count) 项")
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("名称")
                    .font(AppTypography.smallStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("状态")
                    .font(AppTypography.smallStrong)
                    .frame(width: 104, alignment: .leading)

                Text("左侧")
                    .font(AppTypography.smallStrong)
                    .frame(width: 88, alignment: .trailing)

                Text("右侧")
                    .font(AppTypography.smallStrong)
                    .frame(width: 88, alignment: .trailing)

                Text("操作")
                    .font(AppTypography.smallStrong)
                    .frame(width: 92, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(nodes) { node in
                        DetailListRowView(node: node, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest, onOpenDirectory: onOpenDirectory)
                    }
                }
                .padding(.vertical, 2)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var detailTitle: String {
        directoryPath.isEmpty ? "根目录文件列表" : directoryPath
    }
}

private struct DetailListRowView: View {
    let node: FileTreeNode
    let onDeleteRequest: (FileRecord) -> Void
    let onCopyRequest: (FileRecord) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(node.isDirectory ? Color(nsColor: .systemYellow) : .secondary)
                    .frame(width: 18)

                Text(node.name)
                    .font(AppTypography.nodeName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(status: node.status)
                .frame(width: 104, alignment: .leading)

            SizeValueView(value: node.leftSize)
                .frame(width: 88, alignment: .trailing)

            SizeValueView(value: node.rightSize)
                .frame(width: 88, alignment: .trailing)

            DetailActionView(node: node, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest, onOpenDirectory: onOpenDirectory)
                .frame(width: 92, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetailActionView: View {
    let node: FileTreeNode
    let onDeleteRequest: (FileRecord) -> Void
    let onCopyRequest: (FileRecord) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        switch action {
        case .openDirectory:
            Button("进入") {
                onOpenDirectory(node.path)
            }
            .buttonStyle(.borderless)
            .font(AppTypography.small)
        case let .delete(file):
            Button("删除左侧") {
                onDeleteRequest(file)
            }
            .buttonStyle(.borderless)
            .font(AppTypography.small)
            .foregroundStyle(.red)
        case let .copy(file):
            Button("拷到左侧") {
                onCopyRequest(file)
            }
            .buttonStyle(.borderless)
            .font(AppTypography.small)
        case .none:
            Color.clear
                .frame(width: 1, height: 18)
        }
    }

    private var action: DetailAction {
        if node.isDirectory {
            return .openDirectory
        }

        switch node.status {
        case .leftOnly:
            guard let leftSize = node.leftSize, let leftAbsolutePath = node.leftAbsolutePath else {
                return .none
            }

            return .delete(FileRecord(relativePath: node.path, absolutePath: leftAbsolutePath, size: leftSize))
        case .rightOnly:
            guard let rightSize = node.rightSize, let rightAbsolutePath = node.rightAbsolutePath else {
                return .none
            }

            return .copy(FileRecord(relativePath: node.path, absolutePath: rightAbsolutePath, size: rightSize))
        default:
            return .none
        }
    }
}

private enum DetailAction {
    case openDirectory
    case delete(FileRecord)
    case copy(FileRecord)
    case none
}

private struct SizeValueView: View {
    let value: UInt64?

    var body: some View {
        Group {
            if let value {
                Text(SizeFormatter.string(from: value))
                    .font(AppTypography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("")
                    .font(AppTypography.mono)
            }
        }
    }
}

private struct FlatResultView: View {
    let result: CompareResult
    let onDeleteRequest: (FileRecord) -> Void
    let onCopyRequest: (FileRecord) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PairSectionView(title: "路径和大小一致", pairs: result.identicalFiles, tint: .green, showBothSizes: false)
                PairSectionView(title: "路径一致大小不同", pairs: result.samePathDifferentSizeFiles, tint: .orange, showBothSizes: true)
                SameSizeDifferentPathSectionView(groups: result.sameSizeDifferentPathGroups)
                SideOnlySectionView(title: "仅左侧存在", files: result.leftOnlyFiles, tint: .red, actionTitle: "删除左侧", action: onDeleteRequest)
                SideOnlySectionView(title: "仅右侧存在", files: result.rightOnlyFiles, tint: .pink, actionTitle: "拷到左侧", action: onCopyRequest)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PairSectionView: View {
    let title: String
    let pairs: [PathPair]
    let tint: Color
    let showBothSizes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: pairs.count, tint: tint)

            if pairs.isEmpty {
                EmptySectionView()
            } else {
                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pair.relativePath)
                            .font(AppTypography.nodeName)

                        if showBothSizes {
                            HStack(spacing: 14) {
                                MetaValueView(title: "左侧", value: SizeFormatter.string(from: pair.left.size))
                                MetaValueView(title: "右侧", value: SizeFormatter.string(from: pair.right.size))
                            }
                        } else {
                            MetaValueView(title: "大小", value: SizeFormatter.string(from: pair.left.size))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct SameSizeDifferentPathSectionView: View {
    let groups: [SizeMatchGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "大小一致路径不同", count: groups.count, tint: .mint)

            if groups.isEmpty {
                EmptySectionView()
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        MetaValueView(title: "文件大小", value: SizeFormatter.string(from: group.size))

                        HStack(alignment: .top, spacing: 12) {
                            PathColumnView(title: "左侧", files: group.leftFiles, tint: .blue)
                            PathColumnView(title: "右侧", files: group.rightFiles, tint: .indigo)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct SideOnlySectionView: View {
    let title: String
    let files: [FileRecord]
    let tint: Color
    let actionTitle: String
    let action: (FileRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: files.count, tint: tint)

            if files.isEmpty {
                EmptySectionView()
            } else {
                ForEach(files) { file in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.relativePath)
                                .font(AppTypography.nodeName)
                                .lineLimit(2)

                            Text(SizeFormatter.string(from: file.size))
                                .font(AppTypography.mono)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Button(actionTitle) {
                            action(file)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(AppTypography.small)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct PathColumnView: View {
    let title: String
    let files: [FileRecord]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)

            ForEach(files) { file in
                Text(file.relativePath)
                    .font(AppTypography.mono)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetaValueView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppTypography.mono)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTypography.smallStrong)

            Text("\(count)")
                .font(AppTypography.small)
                .foregroundStyle(tint)
        }
    }
}

private struct EmptySectionView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
            .frame(height: 44)
            .overlay {
                Text("当前分类没有数据")
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct HistorySheetView: View {
    @ObservedObject var viewModel: FolderCompareViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("历史记录")
                .font(AppTypography.section)

            if viewModel.historyItems.isEmpty {
                Text("暂无历史记录")
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.historyItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.leftPath)
                                .font(AppTypography.smallStrong)
                                .lineLimit(1)

                            Text(item.rightPath)
                                .font(AppTypography.small)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(historyDateFormatter.string(from: item.comparedAt))
                                .font(AppTypography.small)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Button("重新对比") {
                            viewModel.compare(using: item)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 360)
    }

    private var historyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private struct StatusBadge: View {
    let status: DiffStatus

    var body: some View {
        Text(status.compactDisplayName)
            .font(AppTypography.small)
            .foregroundStyle(status.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.11))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private enum AppTypography {
    static let title = Font.system(size: 24, weight: .semibold)
    static let section = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let nodeName = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let small = Font.system(size: 14, weight: .regular)
    static let smallStrong = Font.system(size: 14, weight: .semibold)
}

private struct PanelSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension View {
    func panelSurface() -> some View {
        modifier(PanelSurfaceModifier())
    }
}

private extension DiffStatus {
    var color: Color {
        switch self {
        case .identical:
            .green
        case .samePathDifferentSize:
            .orange
        case .sameSizeDifferentPath:
            .mint
        case .leftOnly:
            .red
        case .rightOnly:
            .pink
        case .folder:
            Color(nsColor: .systemYellow)
        case .mixed:
            .secondary
        }
    }
}

private enum SizeFormatter {
    static func string(from bytes: UInt64?) -> String {
        guard let bytes else {
            return "-"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
