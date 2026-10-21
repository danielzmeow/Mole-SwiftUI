import SwiftUI
import MoleAdapter

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var tab = 0

    var body: some View {
        if let history = model.history {
            Page(title: "操作历史") {
                Picker("记录类型", selection: $tab) {
                    Text("会话 \(history.sessions.count)").tag(0)
                    Text("删除 \(history.deletions.count)").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            } content: {
                PageSection(title: tab == 0 ? "操作会话" : "删除记录", detail: "最近 200 条") {
                    if tab == 0 {
                        if history.sessions.isEmpty { emptyRecords }
                        VStack(spacing: 0) {
                            ForEach(history.sessions.indices, id: \.self) { index in
                                HistorySessionRow(session: history.sessions[index])
                                if index < history.sessions.count - 1 { Divider() }
                            }
                        }
                    } else {
                        if history.deletions.isEmpty { emptyRecords }
                        LazyVStack(spacing: 0) {
                            ForEach(history.deletions.indices, id: \.self) { index in
                                deletionRow(history.deletions[index])
                            }
                        }
                    }
                }

                if !history.logs.isEmpty {
                    PageSection(title: "日志文件") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            ForEach(history.logs.keys.sorted(), id: \.self) { key in
                                GridRow {
                                    Text(key).foregroundStyle(.secondary)
                                    Text(history.logs[key] ?? "")
                                        .font(.callout.monospaced())
                                        .lineLimit(1).truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.top, 4)
                    }
                }
            }
        } else {
            EmptyAction(title: "操作历史", symbol: "clock.arrow.circlepath", actionTitle: "读取历史记录", disabled: model.busy) {
                model.load(.history)
            }
        }
    }

    private var emptyRecords: some View {
        Text("暂无此类记录").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func deletionRow(_ row: HistoryDeletion) -> some View {
        let failed = !(row.status == "ok" || row.status == "dry-run")
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(row.path)
                Text(row.timestamp + " · " + row.mode).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 24)
            Text(row.status).foregroundStyle(failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 72, alignment: .trailing)
            Text(row.sizeKb.map { "\($0.formatted()) KB" } ?? "—")
                .foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .listRow()
    }
}

private struct HistorySessionRow: View {
    let session: HistorySession
    @State private var expanded = false

    private var actionSummary: String {
        session.actions.keys.sorted()
            .filter { (session.actions[$0] ?? 0) > 0 }
            .map { "\($0) \(session.actions[$0] ?? 0)" }
            .joined(separator: " · ")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                detail("结束时间", session.endedAt.isEmpty ? "未记录" : session.endedAt)
                detail("操作 / 失败任务", "\(session.operationCount) / \(session.failedTasks)")
                detail("日志归属", session.attribution)
                detail("Run ID", session.runId.isEmpty ? "未记录" : session.runId)
            }
            .font(.callout)
            .textSelection(.enabled)
            .padding(.vertical, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.command).font(.body.weight(.medium))
                    Text([session.startedAt, actionSummary].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 24)
                Text("\(session.items) 项").foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
                Text(session.size.isEmpty ? "—" : session.size).font(.body.weight(.medium)).monospacedDigit()
                    .frame(width: 96, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
