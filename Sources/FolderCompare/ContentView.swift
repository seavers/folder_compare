import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: FolderCompareViewModel

    var body: some View {
        VStack(spacing: 16) {
            HeaderControlsView(viewModel: viewModel)
            SummaryDashboardView(result: viewModel.compareResult)
            ResultContainerView(result: viewModel.compareResult)
        }
        .padding(20)
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
            }
        }
    }
}

private struct HeaderControlsView: View {
    @ObservedObject var viewModel: FolderCompareViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("文件夹对比工具")
                .font(.system(size: 28, weight: .bold))

            Text("对比两个文件夹中的文件路径与大小，并按树状结构或扁平结构查看结果。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                FolderSelectorField(title: "左侧文件夹", path: $viewModel.leftFolderPath) {
                    viewModel.chooseFolder(for: .left)
                }

                FolderSelectorField(title: "右侧文件夹", path: $viewModel.rightFolderPath) {
                    viewModel.chooseFolder(for: .right)
                }

                Button {
                    viewModel.compareFolders()
                } label: {
                    if viewModel.isComparing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 68)
                    } else {
                        Text("开始对比")
                            .frame(width: 68)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isComparing)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct FolderSelectorField: View {
    let title: String
    @Binding var path: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack(spacing: 8) {
                TextField("请选择文件夹", text: $path)
                    .textFieldStyle(.roundedBorder)

                Button("浏览", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryDashboardView: View {
    let result: CompareResult?

    private let columns = [
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120)),
        GridItem(.flexible(minimum: 120))
    ]

    var body: some View {
        if let result {
            LazyVGrid(columns: columns, spacing: 12) {
                SummaryCard(title: "左侧文件", value: "\(result.summary.leftCount)", tint: .blue)
                SummaryCard(title: "右侧文件", value: "\(result.summary.rightCount)", tint: .indigo)
                SummaryCard(title: "完全一致", value: "\(result.summary.identicalCount)", tint: .green)
                SummaryCard(title: "同路径异大小", value: "\(result.summary.samePathDifferentSizeCount)", tint: .orange)
                SummaryCard(title: "同大小异路径", value: "\(result.summary.sameSizeDifferentPathCount)", tint: .mint)
                SummaryCard(title: "仅左侧存在", value: "\(result.summary.leftOnlyCount)", tint: .red)
                SummaryCard(title: "仅右侧存在", value: "\(result.summary.rightOnlyCount)", tint: .pink)
            }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 96)
                .overlay {
                    Text("选择两个文件夹后开始对比。")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ResultContainerView: View {
    let result: CompareResult?
    @State private var viewMode = ViewMode.tree

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("对比结果")
                    .font(.title3.bold())

                Spacer()

                Picker("视图", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Group {
                if let result {
                    switch viewMode {
                    case .tree:
                        TreeResultView(result: result)
                    case .flat:
                        FlatResultView(result: result)
                    }
                } else {
                    EmptyResultPlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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

private struct TreeResultView: View {
    let result: CompareResult

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("左侧：\(result.leftRootPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("右侧：\(result.rightRootPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                OutlineGroup(result.treeRoots, children: \.childNodes) { node in
                    TreeRowView(node: node)
                }
            }
        }
    }
}

private struct EmptyResultPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("暂无结果")
                .font(.title3.weight(.semibold))

            Text("完成一次对比后，这里会展示树状结构与扁平结构两类结果。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TreeRowView: View {
    let node: FileTreeNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder" : "doc")
                .foregroundStyle(node.isDirectory ? .yellow : .secondary)
                .frame(width: 18)

            Text(node.name)
                .font(.body.monospaced())

            Spacer(minLength: 12)

            StatusBadge(status: node.status)

            if !node.isDirectory {
                Text(SizeFormatter.string(from: node.leftSize))
                    .frame(width: 110, alignment: .trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(SizeFormatter.string(from: node.rightSize))
                    .frame(width: 110, alignment: .trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: pairs.count, tint: tint)

            if pairs.isEmpty {
                EmptySectionView()
            } else {
                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pair.relativePath)
                            .font(.body.monospaced())

                        if showBothSizes {
                            HStack(spacing: 12) {
                                Text("左侧：\(SizeFormatter.string(from: pair.left.size))")
                                Text("右侧：\(SizeFormatter.string(from: pair.right.size))")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        } else {
                            Text("大小：\(SizeFormatter.string(from: pair.left.size))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        Text("文件大小：\(SizeFormatter.string(from: group.size))")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 16) {
                            FlatPathColumn(title: "左侧路径", files: group.leftFiles, tint: .blue)
                            FlatPathColumn(title: "右侧路径", files: group.rightFiles, tint: .indigo)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mint.opacity(0.08))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(files) { file in
                Text(file.relativePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SideOnlySectionView: View {
    let title: String
    let files: [FileRecord]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: files.count, tint: tint)

            if files.isEmpty {
                EmptySectionView()
            } else {
                ForEach(files) { file in
                    HStack {
                        Text(file.relativePath)
                            .font(.body.monospaced())

                        Spacer()

                        Text(SizeFormatter.string(from: file.size))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.07))
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
        HStack {
            Text(title)
                .font(.headline)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.16))
                .clipShape(Capsule())
        }
    }
}

private struct EmptySectionView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.06))
            .frame(height: 52)
            .overlay {
                Text("当前分类没有数据")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct StatusBadge: View {
    let status: DiffStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
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
            .yellow
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
