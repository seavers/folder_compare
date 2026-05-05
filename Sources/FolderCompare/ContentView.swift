import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: FolderCompareViewModel
    @State private var selectedFilter: DiffStatus?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                CompactToolbarView(viewModel: viewModel)
                SummaryStripView(result: viewModel.compareResult, isComparing: viewModel.isComparing, selectedFilter: $selectedFilter)
                ResultWorkspaceView(viewModel: viewModel, selectedFilter: $selectedFilter)
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
        .onChange(of: viewModel.compareResult?.summary.leftCount) { _ in
            selectedFilter = nil
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

            ToolbarIconButton(symbol: "arrow.left.arrow.right") {
                viewModel.swapFolders()
            }

            FolderInputField(title: "右侧", path: $viewModel.rightFolderPath, tint: .indigo) {
                viewModel.chooseFolder(for: .right)
            }

            PersistentAccentButton(title: viewModel.isComparing ? "取消对比" : "开始对比", isLoading: false) {
                if viewModel.isComparing {
                    viewModel.cancelCompare()
                } else {
                    viewModel.compareFolders()
                }
            }

            ToolbarTextButton(title: "历史记录", isDisabled: viewModel.historyItems.isEmpty) {
                isHistoryPresented = true
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

            ToolbarTextButton(title: "浏览", action: action)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryStripView: View {
    let result: CompareResult?
    let isComparing: Bool
    @Binding var selectedFilter: DiffStatus?

    var body: some View {
        Group {
            if let result {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SummaryChip(title: "左侧", value: result.summary.leftCount, tint: .blue)
                        SummaryChip(title: "右侧", value: result.summary.rightCount, tint: .indigo)
                        FilterChip(status: .identical, value: result.summary.identicalCount, selectedFilter: $selectedFilter)
                        FilterChip(status: .samePathDifferentSize, value: result.summary.samePathDifferentSizeCount, selectedFilter: $selectedFilter)
                        FilterChip(status: .sameSizeDifferentPath, value: result.summary.sameSizeDifferentPathCount, selectedFilter: $selectedFilter)
                        FilterChip(status: .leftOnly, value: result.summary.leftOnlyCount, selectedFilter: $selectedFilter)
                        FilterChip(status: .rightOnly, value: result.summary.rightOnlyCount, selectedFilter: $selectedFilter)
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

private struct FilterChip: View {
    let status: DiffStatus
    let value: Int
    @Binding var selectedFilter: DiffStatus?
    @State private var isHovered = false

    private var isSelected: Bool {
        selectedFilter == status
    }

    var body: some View {
        Button {
            selectedFilter = isSelected ? nil : status
        } label: {
            HStack(spacing: 8) {
                Text(status.compactDisplayName)
                    .font(AppTypography.small)

                Text("\(value)")
                    .font(AppTypography.smallStrong)
            }
            .foregroundStyle(isSelected ? .white : status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(status.color.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return status.color
        }

        return isHovered ? status.color.opacity(0.14) : status.color.opacity(0.08)
    }
}

private struct ResultWorkspaceView: View {
    @ObservedObject var viewModel: FolderCompareViewModel
    @Binding var selectedFilter: DiffStatus?
    @State private var viewMode = ViewMode.tree
    @State private var deleteCandidate: PendingDeleteAction?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("结果")
                    .font(AppTypography.section)

                if let result = viewModel.compareResult {
                    Text(summaryText(for: result))
                        .font(AppTypography.small)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ModeSwitch(selectedMode: $viewMode)
            }

            Group {
                if viewModel.isComparing, let progress = viewModel.compareProgress {
                    CompareProgressWorkspaceView(progress: progress)
                } else if let result = viewModel.compareResult {
                    switch viewMode {
                    case .tree:
                        TreeSplitResultView(
                            result: result,
                            selectedFilter: selectedFilter,
                            onDeleteRequest: { side, file in deleteCandidate = PendingDeleteAction(side: side, file: file) },
                            onCopyRequest: viewModel.copyFile(_:to:)
                        )
                    case .flat:
                        FlatResultView(
                            result: result,
                            selectedFilter: selectedFilter,
                            onDeleteRequest: { side, file in deleteCandidate = PendingDeleteAction(side: side, file: file) },
                            onCopyRequest: viewModel.copyFile(_:to:)
                        )
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
            deleteCandidate == nil ? "删除文件？" : "删除\(deleteCandidate?.side.displayName ?? "")文件？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            presenting: deleteCandidate
        ) { candidate in
            Button("删除", role: .destructive) {
                viewModel.deleteFile(candidate.file, from: candidate.side)
                deleteCandidate = nil
            }

            Button("取消", role: .cancel) {}
        } message: { candidate in
            Text(candidate.file.relativePath)
        }
    }

    private func summaryText(for result: CompareResult) -> String {
        if let selectedFilter {
            return "已筛选：\(selectedFilter.displayName)"
        }

        return "左 \(result.summary.leftCount) / 右 \(result.summary.rightCount)"
    }
}

private struct CompareProgressWorkspaceView: View {
    let progress: CompareProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(progress.phase.displayName)
                    .font(AppTypography.section)
            }

            Group {
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }

            HStack(spacing: 10) {
                ProgressMetricCard(title: "左侧已发现", value: "\(progress.leftDiscoveredCount)", tint: .blue)
                ProgressMetricCard(title: "右侧已发现", value: "\(progress.rightDiscoveredCount)", tint: .indigo)
                ProgressMetricCard(title: progress.totalCount == nil ? "当前阶段进度" : "已处理", value: processedText, tint: .green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当前文件")
                    .font(AppTypography.smallStrong)
                    .foregroundStyle(.secondary)

                Text(progress.currentPath ?? placeholderText)
                    .font(AppTypography.mono)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var processedText: String {
        if let totalCount = progress.totalCount {
            return "\(progress.processedCount) / \(totalCount)"
        }

        return "\(progress.processedCount)"
    }

    private var placeholderText: String {
        switch progress.phase {
        case .preparing:
            "正在准备扫描目录..."
        case .scanningLeft:
            "正在扫描左侧目录..."
        case .scanningRight:
            "正在扫描右侧目录..."
        case .matchingPaths:
            "正在按路径比对..."
        case .groupingSameSize:
            "正在处理同大小异路径文件..."
        case .buildingIndex:
            "正在生成结果索引..."
        }
    }
}

private struct ProgressMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.small)
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppTypography.section)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

private struct ModeSwitch: View {
    @Binding var selectedMode: ViewMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Text(mode.displayName)
                        .font(AppTypography.smallStrong)
                        .foregroundStyle(selectedMode == mode ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(selectedMode == mode ? Color.accentColor : Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
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

            Text("主区域会优先展示目录与可操作文件。")
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
    let selectedFilter: DiffStatus?
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void
    @State private var expandedNodes: Set<String> = []
    @State private var selectedDirectoryPath = ""

    var body: some View {
        HSplitView {
            DirectorySidebarView(
                directoryRoots: visibleDirectoryRoots,
                selectedFilter: selectedFilter,
                selectedDirectoryPath: $selectedDirectoryPath,
                expandedNodes: $expandedNodes
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            DirectoryDetailView(
                directoryPath: selectedDirectoryPath,
                nodes: currentItems,
                onDeleteRequest: onDeleteRequest,
                onCopyRequest: onCopyRequest,
                onOpenDirectory: openDirectory
            )
            .frame(minWidth: 560)
        }
        .onAppear {
            expandedNodes = []
            selectedDirectoryPath = ""
        }
    }

    private var visibleDirectoryRoots: [DirectoryNode] {
        result.directoryRoots.filter(matchesFilter)
    }

    private var currentItems: [DirectoryItem] {
        let items = result.directoryItemsByPath[selectedDirectoryPath] ?? []
        guard let selectedFilter else {
            return items
        }

        return items.filter { item in
            if item.isDirectory {
                return directoryNode(for: item.path)?.containedStatuses.contains(selectedFilter) == true
            }

            return item.status == selectedFilter
        }
    }

    private func matchesFilter(_ node: DirectoryNode) -> Bool {
        guard let selectedFilter else {
            return true
        }

        return node.containedStatuses.contains(selectedFilter)
    }

    private func directoryNode(for path: String) -> DirectoryNode? {
        findDirectoryNode(path: path, in: result.directoryRoots)
    }

    private func findDirectoryNode(path: String, in nodes: [DirectoryNode]) -> DirectoryNode? {
        for node in nodes {
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
    let directoryRoots: [DirectoryNode]
    let selectedFilter: DiffStatus?
    @Binding var selectedDirectoryPath: String
    @Binding var expandedNodes: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目录树")
                .font(AppTypography.smallStrong)
                .padding(.horizontal, 10)

            SidebarRootRowView(isSelected: selectedDirectoryPath.isEmpty) {
                selectedDirectoryPath = ""
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(directoryRoots) { node in
                        DirectoryTreeRowView(node: node, selectedFilter: selectedFilter, depth: 0, selectedDirectoryPath: $selectedDirectoryPath, expandedNodes: $expandedNodes)
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
    let node: DirectoryNode
    let selectedFilter: DiffStatus?
    let depth: Int
    @Binding var selectedDirectoryPath: String
    @Binding var expandedNodes: Set<String>
    @State private var isHovered = false
    @State private var isArrowHovered = false

    private var isExpanded: Bool {
        expandedNodes.contains(node.path)
    }

    private var isSelected: Bool {
        selectedDirectoryPath == node.path
    }

    private var visibleChildren: [DirectoryNode] {
        node.children.filter { child in
            guard let selectedFilter else {
                return true
            }

            return child.containedStatuses.contains(selectedFilter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Color.clear.frame(width: CGFloat(depth) * 14)

                Group {
                    if visibleChildren.isEmpty {
                        Color.clear.frame(width: 28, height: 28)
                    } else {
                        Button(action: toggleExpanded) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isArrowHovered ? .primary : .secondary)
                                .frame(width: 28, height: 28)
                                .background(isArrowHovered ? Color.primary.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .onHover { isArrowHovered = $0 }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color(nsColor: .systemYellow))

                    Text(node.name)
                        .font(AppTypography.nodeName)

                    Spacer(minLength: 4)

                    StatusBadge(status: node.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .background(rowBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    selectedDirectoryPath = node.path
                }
                .onHover { isHovered = $0 }
            }

            if isExpanded {
                ForEach(visibleChildren) { child in
                    DirectoryTreeRowView(node: child, selectedFilter: selectedFilter, depth: depth + 1, selectedDirectoryPath: $selectedDirectoryPath, expandedNodes: $expandedNodes)
                }
            }
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        return isHovered ? Color.primary.opacity(0.06) : .clear
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
    let nodes: [DirectoryItem]
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(detailTitle)
                    .font(AppTypography.smallStrong)
                    .lineLimit(1)
                    .truncationMode(.middle)

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
                    .frame(width: 116, alignment: .leading)

                Text("左侧")
                    .font(AppTypography.smallStrong)
                    .frame(width: 96, alignment: .trailing)

                Text("右侧")
                    .font(AppTypography.smallStrong)
                    .frame(width: 96, alignment: .trailing)

                Text("操作")
                    .font(AppTypography.smallStrong)
                    .frame(width: 120, alignment: .leading)
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
        directoryPath.isEmpty ? "根目录" : directoryPath
    }
}

private struct DetailListRowView: View {
    let node: DirectoryItem
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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

                if !node.isDirectory, node.status == .sameSizeDifferentPath {
                    SameSizePathPopoverButton(item: node)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(status: node.status)
                .frame(width: 116, alignment: .leading)

            SizeValueView(value: node.leftSize)
                .frame(width: 96, alignment: .trailing)

            SizeValueView(value: node.rightSize)
                .frame(width: 96, alignment: .trailing)

            DetailActionView(node: node, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest, onOpenDirectory: onOpenDirectory)
                .frame(width: 120, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetailActionView: View {
    let node: DirectoryItem
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void
    let onOpenDirectory: (String) -> Void

    var body: some View {
        switch action {
        case .openDirectory:
            HoverActionButton(title: "进入") {
                onOpenDirectory(node.path)
            }
        case let .menu(items):
            ActionMenuButton(title: "操作", items: items)
        case .none:
            Text("无操作")
                .font(AppTypography.small)
                .foregroundStyle(.tertiary)
        }
    }

    private var action: DetailAction {
        if node.isDirectory {
            return .openDirectory
        }

        switch node.status {
        case .leftOnly:
            guard let leftFile = node.leftFile else {
                return .none
            }

            return .menu(items: [
                ActionMenuItem(title: "拷到右侧") { onCopyRequest(leftFile, .right) },
                ActionMenuItem(title: "删除左侧", isDestructive: true) { onDeleteRequest(.left, leftFile) }
            ])
        case .rightOnly:
            guard let rightFile = node.rightFile else {
                return .none
            }

            return .menu(items: [
                ActionMenuItem(title: "拷到左侧") { onCopyRequest(rightFile, .left) },
                ActionMenuItem(title: "删除右侧", isDestructive: true) { onDeleteRequest(.right, rightFile) }
            ])
        case .sameSizeDifferentPath:
            if let leftFile = node.leftFile, node.primarySide == .left {
                return .menu(items: [
                    ActionMenuItem(title: "拷到右侧") { onCopyRequest(leftFile, .right) },
                    ActionMenuItem(title: "删除左侧", isDestructive: true) { onDeleteRequest(.left, leftFile) }
                ])
            }

            if let rightFile = node.rightFile, node.primarySide == .right {
                return .menu(items: [
                    ActionMenuItem(title: "拷到左侧") { onCopyRequest(rightFile, .left) },
                    ActionMenuItem(title: "删除右侧", isDestructive: true) { onDeleteRequest(.right, rightFile) }
                ])
            }

            return .none
        default:
            return .none
        }
    }
}

private enum DetailAction {
    case openDirectory
    case menu(items: [ActionMenuItem])
    case none
}

private struct SizeValueView: View {
    let value: UInt64?

    var body: some View {
        Text(SizeFormatter.string(from: value))
            .font(AppTypography.mono)
            .foregroundStyle(value == nil ? .tertiary : .secondary)
            .lineLimit(1)
    }
}

private struct SidebarRootRowView: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "tray.full")
            Text("根目录")
        }
        .font(AppTypography.smallStrong)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.primary.opacity(0.06) : .clear
    }
}

private struct HoverActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.small)
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ActionMenuButton: View {
    let title: String
    let items: [ActionMenuItem]
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(item.title, role: item.isDestructive ? .destructive : nil, action: item.action)
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(AppTypography.small)
            .foregroundStyle(isHovered ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
    }
}

private struct ActionMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    init(title: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }
}

private struct SameSizePathPopoverButton: View {
    let item: DirectoryItem
    @State private var isPresented = false

    var body: some View {
        Button("查看两侧路径") {
            isPresented = true
        }
        .buttonStyle(.plain)
        .font(AppTypography.small)
        .foregroundStyle(.secondary)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SameSizePathPopoverContent(item: item)
        }
    }
}

private struct SameSizePathPopoverContent: View {
    let item: DirectoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同大小异路径")
                .font(AppTypography.section)

            VStack(alignment: .leading, spacing: 6) {
                Text(currentSide.displayName)
                    .font(AppTypography.smallStrong)
                    .foregroundStyle(currentSide == .left ? Color.blue : Color.indigo)

                Text(currentFile.relativePath)
                    .font(AppTypography.mono)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(counterpartSide.displayName)
                    .font(AppTypography.smallStrong)
                    .foregroundStyle(counterpartSide == .left ? Color.blue : Color.indigo)

                ForEach(item.counterpartFiles) { file in
                    Text(file.relativePath)
                        .font(AppTypography.mono)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private var currentSide: CompareSide {
        item.primarySide ?? .left
    }

    private var currentFile: FileRecord {
        item.leftFile ?? item.rightFile ?? FileRecord(relativePath: item.path, absolutePath: "", size: 0)
    }

    private var counterpartSide: CompareSide {
        item.counterpartSide ?? currentSide.opposite
    }
}

private struct FlatResultView: View {
    let result: CompareResult
    let selectedFilter: DiffStatus?
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if shouldShow(.identical) {
                    PairSectionView(title: "路径和大小一致", pairs: result.identicalFiles, tint: .green, showBothSizes: false)
                }

                if shouldShow(.samePathDifferentSize) {
                    PairSectionView(title: "路径一致大小不同", pairs: result.samePathDifferentSizeFiles, tint: .orange, showBothSizes: true)
                }

                if shouldShow(.sameSizeDifferentPath) {
                    SameSizeDifferentPathSectionView(groups: result.sameSizeDifferentPathGroups, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest)
                }

                if shouldShow(.leftOnly) {
                    SideOnlySectionView(title: "仅左侧存在", files: result.leftOnlyFiles, tint: .red, side: .left, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest)
                }

                if shouldShow(.rightOnly) {
                    SideOnlySectionView(title: "仅右侧存在", files: result.rightOnlyFiles, tint: .pink, side: .right, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func shouldShow(_ status: DiffStatus) -> Bool {
        selectedFilter == nil || selectedFilter == status
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
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void

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
                            SameSizeGroupColumn(title: "左侧", files: group.leftFiles, tint: .blue, side: .left, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest)
                            SameSizeGroupColumn(title: "右侧", files: group.rightFiles, tint: .indigo, side: .right, onDeleteRequest: onDeleteRequest, onCopyRequest: onCopyRequest)
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

private struct SameSizeGroupColumn: View {
    let title: String
    let files: [FileRecord]
    let tint: Color
    let side: CompareSide
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)

            ForEach(files) { file in
                HStack(alignment: .top, spacing: 8) {
                    Text(file.relativePath)
                        .font(AppTypography.mono)
                        .lineLimit(3)

                    Spacer(minLength: 8)

                    ActionMenuButton(
                        title: "操作",
                        items: [
                            ActionMenuItem(title: side == .left ? "拷到右侧" : "拷到左侧") { onCopyRequest(file, side.opposite) },
                            ActionMenuItem(title: side == .left ? "删除左侧" : "删除右侧", isDestructive: true) { onDeleteRequest(side, file) }
                        ]
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SideOnlySectionView: View {
    let title: String
    let files: [FileRecord]
    let tint: Color
    let side: CompareSide
    let onDeleteRequest: (CompareSide, FileRecord) -> Void
    let onCopyRequest: (FileRecord, CompareSide) -> Void

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

                        ActionMenuButton(
                            title: "操作",
                            items: [
                                ActionMenuItem(title: side == .left ? "拷到右侧" : "拷到左侧") { onCopyRequest(file, side.opposite) },
                                ActionMenuItem(title: side == .left ? "删除左侧" : "删除右侧", isDestructive: true) { onDeleteRequest(side, file) }
                            ]
                        )
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

                        PersistentAccentButton(title: "重新对比", compact: true) {
                            viewModel.compare(using: item)
                            dismiss()
                        }
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

private struct PersistentAccentButton: View {
    let title: String
    var isLoading: Bool = false
    var compact: Bool = false
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(title)
                    .font(AppTypography.smallStrong)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 7 : 9)
            .background(isHovered ? Color.accentColor.opacity(0.88) : Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ToolbarTextButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(isDisabled ? .tertiary : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
