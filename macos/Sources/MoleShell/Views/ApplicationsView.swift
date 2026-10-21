import SwiftUI
import MoleAdapter

struct ApplicationsView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\InstalledApplication.name, comparator: .localizedStandard)]

    private var filtered: [InstalledApplication] {
        model.applications
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleId.localizedCaseInsensitiveContains(search) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if model.applications.isEmpty {
                EmptyAction(title: "应用管理", symbol: "square.grid.2x2", actionTitle: "读取应用清单", disabled: model.busy) {
                    model.load(.applications)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("应用管理").font(.largeTitle.weight(.semibold))
                        Spacer()
                        Text(search.isEmpty ? "\(model.applications.count) 个应用" : "\(filtered.count) / \(model.applications.count)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, Metrics.pagePadding)

                    Table(filtered, sortOrder: $sortOrder) {
                        TableColumn("名称", value: \.name, comparator: .localizedStandard) { app in
                            HStack(spacing: 10) {
                                FileIcon(path: app.path, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name).lineLimit(1)
                                    Text(app.bundleId.isEmpty ? app.uninstallName : app.bundleId)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 3)
                            .help(app.path)
                        }
                        .width(min: 220, ideal: 300)
                        TableColumn("大小") { Text($0.size).monospacedDigit() }
                            .width(min: 70, ideal: 90)
                            .alignment(.trailing)
                        TableColumn("来源", value: \.source) { Text($0.source).foregroundStyle(.secondary) }
                            .width(min: 70, ideal: 90)
                        TableColumn("位置", value: \.path) { app in
                            Text(app.path).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).help(app.path)
                        }
                    }
                    .tableStyle(.inset)
                    .alternatingRowBackgrounds()
                    .scrollEdgeEffectStyle(.soft, for: .top)
                }
            }
        }
        .searchable(text: $search, prompt: "搜索名称或 Bundle ID")
    }
}
