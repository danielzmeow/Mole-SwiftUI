import SwiftUI
import MoleAdapter

struct AnalysisView: View {
    @Bindable var model: AppModel
    @State private var search = ""

    var body: some View {
        Group {
            if let analysis = model.analysis {
                Page(title: analysis.overview ? "磁盘分析" : URL(fileURLWithPath: analysis.path).lastPathComponent,
                     subtitle: analysis.path) {
                    totalSize(analysis)
                } content: {
                    analysisContent(analysis)
                }
            } else {
                EmptyAction(title: "磁盘分析", symbol: "internaldrive", actionTitle: "分析空间概览", disabled: model.busy) {
                    model.load(.analyze(path: nil))
                }
            }
        }
        .searchable(text: $search, prompt: "筛选名称或路径")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("上一级", systemImage: "chevron.left") { goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.busy || model.analysis?.overview != false)
                    .help("上一级 (⌘↑)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("空间概览", systemImage: "internaldrive") { model.load(.analyze(path: nil)) }
                    .disabled(model.busy)
                    .help("空间概览")
                Button("选择文件夹", systemImage: "folder.badge.plus") { chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.busy)
                    .help("选择文件夹 (⌘O)")
            }
        }
    }

    private func totalSize(_ analysis: Analysis) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(analysis.scanStatus == .unavailable ? "未知" : (analysis.scanStatus == .partial ? "≥ " : "") + bytes(analysis.totalSize))
                .font(.system(size: 28, weight: .semibold)).monospacedDigit()
            if analysis.scanStatus != .complete {
                Text(analysis.scanStatus.label).font(.callout).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func analysisContent(_ analysis: Analysis) -> some View {
        let filtered = entries(analysis)
        PageSection(title: "目录与文件", detail: "\(filtered.count) 项") {
            if filtered.isEmpty {
                Text(search.isEmpty ? "此位置没有可显示的项目" : "没有符合筛选条件的项目")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        DirectoryRow(entry: entry, total: analysis.totalSize, disabled: model.busy) {
                            model.load(.analyze(path: entry.path))
                        }
                    }
                }
            }
        }
        if let files = analysis.largeFiles, !files.isEmpty {
            PageSection(title: "大文件", detail: "\(files.count) 项") {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        HStack(spacing: 10) {
                            FileIcon(path: file.path)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).lineLimit(1)
                                Text(file.path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 24)
                            Text(bytes(file.size)).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                        .listRow()
                        .help(file.path)
                    }
                }
            }
        }
    }

    private func entries(_ analysis: Analysis) -> [AnalysisEntry] {
        (analysis.entries ?? []).filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    private func goUp() {
        guard let analysis = model.analysis else { return }
        model.load(.analyze(path: URL(fileURLWithPath: analysis.path).deletingLastPathComponent().path))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { model.load(.analyze(path: url.path)) }
        }
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 20
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct DirectoryRow: View {
    let entry: AnalysisEntry
    let total: Int64
    let disabled: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                FileIcon(path: entry.path)
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 24)
                if entry.scanStatus != .unavailable {
                    UsageBar(fraction: total > 0 ? Double(entry.size) / Double(total) : 0, height: 3)
                        .frame(width: 96)
                }
                Text(entry.scanStatus == .unavailable ? "未知" : (entry.scanStatus == .partial ? "≥ " : "") + bytes(entry.size))
                    .monospacedDigit()
                    .foregroundStyle(entry.scanStatus == .complete ? .primary : .secondary)
                    .frame(width: 84, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .opacity(entry.isDir ? 1 : 0)
            }
            .listRow(interactive: entry.isDir && !disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled || !entry.isDir)
        .help(entry.path)
    }
}
