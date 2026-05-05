import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: FolderCompareViewModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HeaderControlsView(viewModel: viewModel)
                SummaryDashboardView(result: viewModel.compareResult)
                ResultContainerView(result: viewModel.compareResult)
            }
            .font(AppTypography.body)
            .padding(20)
        }
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppTypography.smallStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .padding(.top, 8)
            }
        }
    }
}

private struct HeaderControlsView: View {
    @ObservedObject var viewModel: FolderCompareViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件夹对比工具")
                        .font(AppTypography.hero)

                    Text("面向 macOS 的文件比对工作台。聚焦路径、大小和层级关系，让深目录对比依然清晰。")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                Button {
                    viewModel.compareFolders()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isComparing {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(viewModel.isComparing ? "对比中..." : "开始对比")
                            .font(AppTypography.smallStrong)
                    }
                    .frame(minWidth: 116)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isComparing)
            }

            HStack(spacing: 12) {
                CapabilityBadge(symbol: "point.3.filled.connected.trianglepath.dotted", title: "树状层级", subtitle: "递归查看目录结构")
                CapabilityBadge(symbol: "rectangle.split.3x1", title: "扁平结果", subtitle: "按分类集中比对")
                CapabilityBadge(symbol: "arrow.left.and.right.square", title: "路径与大小", subtitle: "明确识别差异类型")
            }

            HStack(spacing: 14) {
                FolderSelectorField(title: "左侧文件夹", path: $viewModel.leftFolderPath, tint: .blue) {
                    viewModel.chooseFolder(for: .left)
                }

                FolderSelectorField(title: "右侧文件夹", path: $viewModel.rightFolderPath, tint: .indigo) {
                    viewModel.chooseFolder(for: .right)
                }
            }
        }
        .padding(22)
        .panelSurface()
    }
}

private struct CapabilityBadge: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.smallStrong)

                Text(subtitle)
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FolderSelectorField: View {
    let title: String
    @Binding var path: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(AppTypography.smallStrong)
            }

            HStack(spacing: 10) {
                TextField("请选择文件夹", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)

                Button("浏览", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .font(AppTypography.smallStrong)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SummaryDashboardView: View {
    let result: CompareResult?

    private let columns = [
        GridItem(.flexible(minimum: 180)),
        GridItem(.flexible(minimum: 180)),
        GridItem(.flexible(minimum: 180)),
        GridItem(.flexible(minimum: 180))
    ]

    var body: some View {
        if let result {
            LazyVGrid(columns: columns, spacing: 12) {
                SummaryCard(title: "左侧文件", value: "\(result.summary.leftCount)", tint: .blue, symbol: "folder")
                SummaryCard(title: "右侧文件", value: "\(result.summary.rightCount)", tint: .indigo, symbol: "folder.fill")
                SummaryCard(title: "完全一致", value: "\(result.summary.identicalCount)", tint: .green, symbol: "checkmark.circle")
                SummaryCard(title: "同路径异大小", value: "\(result.summary.samePathDifferentSizeCount)", tint: .orange, symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                SummaryCard(title: "同大小异路径", value: "\(result.summary.sameSizeDifferentPathCount)", tint: .mint, symbol: "point.3.connected.trianglepath.dotted")
                SummaryCard(title: "仅左侧存在", value: "\(result.summary.leftOnlyCount)", tint: .red, symbol: "arrow.left.circle")
                SummaryCard(title: "仅右侧存在", value: "\(result.summary.rightOnlyCount)", tint: .pink, symbol: "arrow.right.circle")
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("选择两个文件夹后开始对比，统计卡片会在这里展示。")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(.horizontal, 18)
            .panelSurface()
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(AppTypography.metric)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.055))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ResultContainerView: View {
    let result: CompareResult?
    @State private var viewMode = ViewMode.tree

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("对比结果")
                        .font(AppTypography.section)

                    Text(viewMode == .tree ? "树视图强调目录层级和缩进关系。" : "扁平视图强调分类归纳和逐项检视。")
                        .font(AppTypography.small)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                Picker("视图", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            if let result {
                StatusLegendView()

                Group {
                    switch viewMode {
                    case .tree:
                        TreeResultView(result: result)
                    case .flat:
                        FlatResultView(result: result)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyResultPlaceholderView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .panelSurface()
    }
}

private enum ViewMode: String, CaseIterable, Identifiable {
    case tree
    case flat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tree:
            "树状结构"
        case .flat:
            "扁平结构"
        }
    }
}

private struct StatusLegendView: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                LegendChip(status: .identical)
                LegendChip(status: .samePathDifferentSize)
                LegendChip(status: .sameSizeDifferentPath)
                LegendChip(status: .leftOnly)
                LegendChip(status: .rightOnly)
                LegendChip(status: .mixed)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct LegendChip: View {
    let status: DiffStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)

            Text(status.displayName)
                .font(AppTypography.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(Capsule())
    }
}

private struct TreeResultView: View {
    let result: CompareResult
    @State private var expandedNodes: Set<String> = []

    private var treeIdentity: String {
        [
            result.leftRootPath,
            result.rightRootPath,
            "\(result.summary.leftCount)",
            "\(result.summary.rightCount)",
            "\(result.summary.samePathDifferentSizeCount)"
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 12) {
            RootPathBannerView(result: result)
            TreeTableHeaderView()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(result.treeRoots) { node in
                        TreeNodeBranchView(node: node, depth: 0, expandedNodes: $expandedNodes)
                    }
                }
                .padding(10)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .id(treeIdentity)
        .onAppear {
            expandedNodes = Set(result.treeRoots.directoryPathsRecursively())
        }
    }
}

private struct RootPathBannerView: View {
    let result: CompareResult

    var body: some View {
        HStack(spacing: 12) {
            PathSummaryCard(title: "左侧目录", path: result.leftRootPath, tint: .blue)
            PathSummaryCard(title: "右侧目录", path: result.rightRootPath, tint: .indigo)
        }
    }
}

private struct PathSummaryCard: View {
    let title: String
    let path: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)

            Text(path)
                .font(AppTypography.mono)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TreeTableHeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("名称与层级")
                .font(AppTypography.smallStrong)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("状态")
                .font(AppTypography.smallStrong)
                .frame(width: 120, alignment: .leading)

            Text("左侧大小")
                .font(AppTypography.smallStrong)
                .frame(width: 110, alignment: .trailing)

            Text("右侧大小")
                .font(AppTypography.smallStrong)
                .frame(width: 110, alignment: .trailing)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
    }
}

private struct TreeNodeBranchView: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var expandedNodes: Set<String>

    private var isExpanded: Bool {
        expandedNodes.contains(node.fullPath)
    }

    var body: some View {
        VStack(spacing: 6) {
            TreeRowView(node: node, depth: depth, isExpanded: isExpanded) {
                toggleExpanded()
            }

            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    TreeNodeBranchView(node: child, depth: depth + 1, expandedNodes: $expandedNodes)
                }
            }
        }
    }

    private func toggleExpanded() {
        guard node.isDirectory else {
            return
        }

        if expandedNodes.contains(node.fullPath) {
            expandedNodes.remove(node.fullPath)
        } else {
            expandedNodes.insert(node.fullPath)
        }
    }
}

private struct TreeRowView: View {
    let node: FileTreeNode
    let depth: Int
    let isExpanded: Bool
    let toggleAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                DepthGuidesView(depth: depth)

                if node.isDirectory {
                    Button(action: toggleAction) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 18, height: 18)
                }

                Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(node.isDirectory ? Color(nsColor: .systemYellow) : .secondary)
                    .frame(width: 20)

                Text(node.name)
                    .font(AppTypography.nodeName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(status: node.status)
                .frame(width: 120, alignment: .leading)

            Text(SizeFormatter.string(from: node.leftSize))
                .font(AppTypography.mono)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Text(SizeFormatter.string(from: node.rightSize))
                .font(AppTypography.mono)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(node.status.color.opacity(node.isDirectory ? 0.05 : 0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(node.status.color.opacity(0.10), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DepthGuidesView: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<depth, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 2, height: 22)
                    .padding(.vertical, 1)
            }
        }
        .frame(width: CGFloat(depth) * 10, alignment: .leading)
        .padding(.trailing, depth > 0 ? 10 : 0)
    }
}

private struct EmptyResultPlaceholderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text("暂无对比结果")
                .font(AppTypography.section)

            Text("完成一次对比后，这里会按 macOS 桌面工具的阅读节奏展示层级和差异。")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FlatResultView: View {
    let result: CompareResult

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PairSectionView(title: "路径和大小一致", pairs: result.identicalFiles, tint: .green, showBothSizes: false)
                PairSectionView(title: "路径一致大小不同", pairs: result.samePathDifferentSizeFiles, tint: .orange, showBothSizes: true)
                SameSizeDifferentPathSectionView(groups: result.sameSizeDifferentPathGroups)
                SideOnlySectionView(title: "仅左侧存在", files: result.leftOnlyFiles, tint: .red)
                SideOnlySectionView(title: "仅右侧存在", files: result.rightOnlyFiles, tint: .pink)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct PairSectionView: View {
    let title: String
    let pairs: [PathPair]
    let tint: Color
    let showBothSizes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, count: pairs.count, tint: tint)

            if pairs.isEmpty {
                EmptySectionView()
            } else {
                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pair.relativePath)
                            .font(AppTypography.nodeName)

                        if showBothSizes {
                            HStack(spacing: 16) {
                                FlatMetaTag(title: "左侧", value: SizeFormatter.string(from: pair.left.size))
                                FlatMetaTag(title: "右侧", value: SizeFormatter.string(from: pair.right.size))
                            }
                        } else {
                            FlatMetaTag(title: "大小", value: SizeFormatter.string(from: pair.left.size))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(tint.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct FlatMetaTag: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppTypography.mono)
                .foregroundStyle(.primary)
        }
    }
}

private struct SameSizeDifferentPathSectionView: View {
    let groups: [SizeMatchGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "大小一致路径不同", count: groups.count, tint: .mint)

            if groups.isEmpty {
                EmptySectionView()
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("文件大小：\(SizeFormatter.string(from: group.size))")
                            .font(AppTypography.smallStrong)

                        HStack(alignment: .top, spacing: 16) {
                            FlatPathColumn(title: "左侧路径", files: group.leftFiles, tint: .blue)
                            FlatPathColumn(title: "右侧路径", files: group.rightFiles, tint: .indigo)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mint.opacity(0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mint.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct FlatPathColumn: View {
    let title: String
    let files: [FileRecord]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.smallStrong)
                .foregroundStyle(tint)

            ForEach(files) { file in
                Text(file.relativePath)
                    .font(AppTypography.mono)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SideOnlySectionView: View {
    let title: String
    let files: [FileRecord]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, count: files.count, tint: tint)

            if files.isEmpty {
                EmptySectionView()
            } else {
                ForEach(files) { file in
                    HStack(spacing: 12) {
                        Text(file.relativePath)
                            .font(AppTypography.nodeName)
                            .lineLimit(2)

                        Spacer(minLength: 12)

                        Text(SizeFormatter.string(from: file.size))
                            .font(AppTypography.mono)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(tint.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTypography.section)

            Text("\(count)")
                .font(AppTypography.smallStrong)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.14))
                .clipShape(Capsule())
        }
    }
}

private struct EmptySectionView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
            .frame(height: 56)
            .overlay {
                Text("当前分类没有数据")
                    .font(AppTypography.small)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct StatusBadge: View {
    let status: DiffStatus

    var body: some View {
        Text(status.displayName)
            .font(AppTypography.smallStrong)
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private enum AppTypography {
    static let hero = Font.system(size: 32, weight: .semibold)
    static let section = Font.system(size: 18, weight: .semibold)
    static let metric = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular)
    static let nodeName = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let small = Font.system(size: 14, weight: .regular)
    static let smallStrong = Font.system(size: 14, weight: .semibold)
}

private struct PanelSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
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

private extension [FileTreeNode] {
    func directoryPathsRecursively() -> [String] {
        flatMap { node in
            let childPaths = node.children.directoryPathsRecursively()
            return node.isDirectory ? [node.fullPath] + childPaths : childPaths
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
