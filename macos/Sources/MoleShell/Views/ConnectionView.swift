import SwiftUI

struct ConnectionView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: model.selection?.version ?? "未连接")
                LabeledContent("来源", value: model.selection.map { $0.origin == .installed ? "本机安装" : "App 内置" } ?? "—")
                if let selection = model.selection {
                    LabeledContent("路径") {
                        Text(selection.executable.path).font(.callout.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).help(selection.executable.path)
                    }
                }
            } header: {
                Text("CLI")
            } footer: {
                if let selection = model.selection, selection.origin == .bundled {
                    Text(selection.explanation).foregroundStyle(.secondary)
                }
            }
            Section("适配") {
                LabeledContent("适配版本", value: model.compatibility?.version ?? "—")
                LabeledContent("源码基线") {
                    Text(model.compatibility.map { String($0.sourceCommit.prefix(12)) } ?? "—")
                        .font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("重新检测", systemImage: "arrow.clockwise") { model.connect() }
                        .disabled(model.busy)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
