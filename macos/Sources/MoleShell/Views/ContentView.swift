import SwiftUI
import MoleAdapter

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var feature: Feature? = .status
    @State private var connectionPresented = false
    @State private var diagnosticsPresented = false

    var body: some View {
        NavigationSplitView {
            List(selection: $feature) {
                Section("我的 Mac") { rows([.status, .analyze, .uninstall, .history]) }
                Section("维护工具") { rows([.clean, .purge, .installer, .optimize, .slim]) }
                Section("更多") { rows([.touchid, .completion, .update, .remove]) }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) { errorBanner }
                .safeAreaInset(edge: .bottom, spacing: 0) { activityBar }
                .navigationTitle(feature?.title ?? "Mole")
                // Each page draws its own large title; the toolbar copy would repeat it.
                .toolbar(removing: .title)
                .toolbar { toolbar }
        }
        .task { if model.selection == nil { model.connect() } }
        .sheet(isPresented: $connectionPresented) {
            VStack(spacing: 0) {
                ConnectionView(model: model)
                HStack {
                    Spacer()
                    Button("完成") { connectionPresented = false }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding([.horizontal, .bottom], 20)
            }
            .frame(width: 520)
        }
        .sheet(isPresented: $diagnosticsPresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("CLI 诊断").font(.title2.weight(.semibold))
                ScrollView {
                    Text(model.diagnostics).font(.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("完成") { diagnosticsPresented = false }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 580, height: 380)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let request = feature?.request {
                Button {
                    if feature == .analyze { model.load(.analyze(path: model.analysis?.overview == false ? model.analysis?.path : nil)) }
                    else { model.load(request) }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .help("刷新 (⌘R)")
                .disabled(model.busy || model.selection == nil)
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            if !model.diagnostics.isEmpty {
                Button { diagnosticsPresented = true } label: { Label("诊断", systemImage: "stethoscope") }
                    .help("CLI 诊断输出")
            }
            Button { connectionPresented = true } label: {
                Label(model.selection.map { "Mole \($0.version)" } ?? "未连接", systemImage: "terminal")
                    .labelStyle(.titleAndIcon)
            }
            .help("CLI 版本与连接详情")
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = model.error {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.error = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("关闭错误")
            }
            .padding(.horizontal, Metrics.pagePadding).padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    @ViewBuilder private var activityBar: some View {
        if model.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.activity).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { model.cancel() }
                    .buttonStyle(.borderless)
                    .help("取消读取 (⌘.)")
            }
            .font(.callout)
            .padding(.horizontal, Metrics.pagePadding).padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func rows(_ features: [Feature]) -> some View {
        ForEach(features) { item in
            Label(item.title, systemImage: item.symbol).tag(item)
        }
    }

    @ViewBuilder private var detail: some View {
        if model.selection == nil {
            EmptyAction(title: "未连接 Mole", symbol: "terminal", actionTitle: "重新连接", disabled: model.busy) {
                model.connect()
            }
        } else {
            switch feature ?? .status {
            case .status: StatusView(model: model)
            case .analyze: AnalysisView(model: model)
            case .uninstall: ApplicationsView(model: model)
            case .history: HistoryView(model: model)
            case let pending: PendingFeatureView(feature: pending)
            }
        }
    }
}
