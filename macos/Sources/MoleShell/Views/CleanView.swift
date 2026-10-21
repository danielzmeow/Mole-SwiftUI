import SwiftUI
import MoleAdapter

struct CleanView: View {
    @Bindable var model: AppModel
    @State private var expandedSections = Set<String>()
    @State private var confirming = false

    var body: some View {
        Group {
            if let preview = model.cleanPreview {
                previewPage(preview)
            } else if let result = model.cleanResult {
                Page(title: "清理结果") {
                    resultSection(result)
                    Button("重新扫描") { model.load(.cleanPreview) }.disabled(model.busy)
                }
            } else {
                EmptyAction(title: "空间清理", symbol: "sparkles", actionTitle: "扫描清理候选", disabled: model.busy) {
                    model.load(.cleanPreview)
                }
            }
        }
        .sheet(isPresented: $confirming) { confirmation }
    }

    private func previewPage(_ preview: CleanPreview) -> some View {
        Page(title: "空间清理") {
            VStack(alignment: .trailing, spacing: 3) {
                Text((preview.sizePartial ? "≥ " : "") + bytes(preview.totalSizeBytes))
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text("候选空间").font(.callout).foregroundStyle(.secondary)
            }
        } content: {
            PageSection(title: "清理候选", detail: "\(preview.entries.count) 个路径") {
                HStack(spacing: 12) {
                    Button("全选可清理项") { model.selectAllCleanPaths() }
                    Button("取消选择") { model.selectedCleanPaths.removeAll() }
                        .disabled(model.selectedCleanPaths.isEmpty)
                    Spacer()
                    Text("已选 \(model.selectedCleanEntries.count) 项").foregroundStyle(.secondary)
                    Button("清理所选…") { confirming = true }
                        .buttonStyle(.glassProminent)
                        .disabled(model.selectedCleanEntries.isEmpty)
                }
                .disabled(model.busy)
                Text("仅列出路径候选；部分工具动作未包含。只读项目暂不支持选择清理。")
                    .font(.callout).foregroundStyle(.secondary)
                if !preview.systemIncluded {
                    Text("本次未包含管理员范围。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if preview.sizePartial {
                    Text("部分大小未知，总量为已测量值。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let date = model.cleanPreviewReadAt {
                    Text("扫描于 \(date.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if preview.entries.isEmpty {
                Text("本次没有可显示的路径候选。")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                let sections = preview.entries.map(\.section).reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                }
                ForEach(sections, id: \.self) { section in
                    let entries = preview.entries.filter { $0.section == section }
                    PageSection(title: section, detail: "\(entries.count) 个路径") {
                        Button {
                            if expandedSections.contains(section) { expandedSections.remove(section) }
                            else { expandedSections.insert(section) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: expandedSections.contains(section) ? "chevron.down" : "chevron.right")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                                Text(expandedSections.contains(section) ? "收起候选路径" : "查看候选路径")
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(expandedSections.contains(section) ? "已展开" : "已折叠")
                        if expandedSections.contains(section) {
                            LazyVStack(spacing: 0) {
                                ForEach(entries) { entry in candidateRow(entry) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func candidateRow(_ entry: CleanPreviewEntry) -> some View {
        let covered = model.selectedCleanPaths.contains { entry.path.hasPrefix($0 + "/") }
        return Toggle(isOn: Binding(
            get: { model.selectedCleanPaths.contains(entry.path) || covered },
            set: { model.selectCleanPath(entry.path, selected: $0) }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.path).lineLimit(2).truncationMode(.middle)
                    if covered {
                        Text("包含在已选目录中").font(.caption).foregroundStyle(.secondary)
                    } else if entry.selectionToken == nil {
                        Text("只读").font(.caption).foregroundStyle(.secondary)
                    } else if let parent = entry.countedUnder {
                        Text("扫描总量已计入 \(parent)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(entry.sizeBytes.map(bytes) ?? "未知").monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .disabled(model.busy || entry.selectionToken == nil || covered)
        .listRow()
        .help(entry.path)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清理所选的 \(model.selectedCleanEntries.count) 项？").font(.title2.weight(.semibold))
            Text("将永久删除所选路径。所选目录包含其全部内容，无法从废纸篓恢复。")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selectedCleanEntries) { entry in
                        Text(entry.path).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer()
                Button("取消") { confirming = false }.keyboardShortcut(.cancelAction)
                Button("确认清理", role: .destructive) {
                    confirming = false
                    model.cleanSelected()
                }
                .disabled(model.busy || model.selectedCleanEntries.isEmpty)
            }
        }
        .padding(24).frame(width: 600)
    }

    private func resultSection(_ result: CleanResult) -> some View {
        PageSection(title: result.interrupted ? "清理已停止" : (result.results.allSatisfy { $0.status == "removed" } ? "清理完成" : "清理结束"),
                    detail: "已移除 \(result.results.filter { $0.status == "removed" }.count) / \(result.results.count) 项") {
            VStack(spacing: 0) {
                ForEach(result.results) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.path).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            if item.status != "removed" {
                                Text(reason(item.reason)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.status == "removed" ? "已移除" : (item.status == "failed" ? "未完成" : "未执行")).foregroundStyle(.secondary)
                    }
                    .listRow()
                }
            }
        }
    }

    private func reason(_ value: String) -> String {
        switch value {
        case "identity_changed": "路径已变化，请重新扫描"
        case "unsupported_scope": "此路径不在可执行范围内"
        case "guard_refused": "安全检查未通过"
        case "not_eligible": "重新扫描后不再符合清理条件"
        case "interrupted": "操作中断，请查看历史并重新扫描"
        case "sink_refused_or_failed": "未完成清理，部分内容可能已移除；请查看历史并重新扫描"
        default: "未完成清理，请检查访问权限和操作历史"
        }
    }
}
