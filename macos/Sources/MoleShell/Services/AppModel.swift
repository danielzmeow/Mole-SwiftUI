import Foundation
import Observation
import MoleAdapter

@MainActor @Observable
final class AppModel {
    var selection: CLISelection?
    var compatibility: CLICompatibility?
    var busy = false
    var activity = ""
    var error: String?
    var diagnostics = ""
    var status: JSONValue?
    var analysis: Analysis?
    var applications: [InstalledApplication] = []
    var history: OperationHistory?
    var cleanPreview: CleanPreview?
    var cleanPreviewReadAt: Date?
    var selectedCleanPaths = Set<String>()
    var cleanResult: CleanResult?
    var isCleaning = false
    private var cleanPreviewIdentity: CLIIdentity?
    private var task: Task<Void, Never>?
    private let runner = ProcessRunner()

    func connect() {
        perform("正在选择 CLI…") {
            guard let resources = Bundle.main.resourceURL else {
                throw AdapterError.message("找不到 App 资源，请通过构建脚本启动。")
            }
            let contract = try JSONDecoder().decode(CLICompatibility.self,
                from: Data(contentsOf: resources.appendingPathComponent("Compatibility.json")))
            self.compatibility = contract
            self.selection = nil
            let selection = try await CLIResolver().resolve(compatibility: contract,
                bundled: resources.appendingPathComponent("CLI/mole"),
                candidates: CLIResolver.installedCandidates())
            try Task.checkCancellation()
            self.selection = selection
            if self.status == nil {
                self.activity = "正在读取系统概况…"
                let result = try await self.runner.run(executable: selection.executable, request: .status)
                try Task.checkCancellation()
                self.status = try JSONDecoder().decode(JSONValue.self, from: result.data)
                self.diagnostics = result.diagnostics
            }
        }
    }

    func load(_ request: CLIRequest) {
        guard let selection else { return }
        perform(request == .cleanPreview ? "正在扫描清理候选…" : "正在读取 Mole…") {
            let result = try await self.runner.run(executable: selection.executable, request: request)
            try Task.checkCancellation()
            switch request {
            case .status:
                self.status = try JSONDecoder().decode(JSONValue.self, from: result.data)
            case .analyze:
                self.analysis = try CLIResponses.decode(Analysis.self, from: result.data)
            case .applications:
                self.applications = try CLIResponses.decode([InstalledApplication].self, from: result.data)
            case .history:
                self.history = try CLIResponses.decode(OperationHistory.self, from: result.data)
            case .cleanPreview:
                self.cleanPreview = try CleanPreview.decode(result.data)
                self.cleanPreviewIdentity = selection.identity
                self.selectedCleanPaths.removeAll()
                self.cleanResult = nil
                self.cleanPreviewReadAt = Date()
            case .version, .cleanPreviewHelp, .cleanSelection: break
            }
            self.diagnostics = result.diagnostics
        }
    }

    var selectedCleanEntries: [CleanPreviewEntry] {
        cleanPreview?.entries.filter { selectedCleanPaths.contains($0.path) && $0.selectionToken != nil } ?? []
    }

    func selectCleanPath(_ path: String, selected: Bool) {
        if selected {
            // Selection UI cannot express exclusions inside a selected directory.
            selectedCleanPaths = selectedCleanPaths.filter { !$0.hasPrefix(path + "/") && !path.hasPrefix($0 + "/") }
            selectedCleanPaths.insert(path)
        } else { selectedCleanPaths.remove(path) }
    }

    func selectAllCleanPaths() {
        selectedCleanPaths.removeAll()
        for entry in (cleanPreview?.entries ?? []).filter({ $0.selectionToken != nil }).sorted(by: { $0.path.count < $1.path.count }) {
            if !selectedCleanPaths.contains(where: { entry.path.hasPrefix($0 + "/") }) {
                selectedCleanPaths.insert(entry.path)
            }
        }
    }

    func cleanSelected() {
        guard !busy, let selection, let compatibility, let preview = cleanPreview,
              !selectedCleanEntries.isEmpty else { return }
        let expectedPaths = Set(selectedCleanEntries.map(\.path))
        let plan = CleanSelection(preview: preview, paths: expectedPaths)
        let previewIdentity = cleanPreviewIdentity
        perform("正在重新检查并清理所选路径…") {
            self.isCleaning = true
            self.cleanPreview = nil
            self.selectedCleanPaths.removeAll()
            self.cleanResult = nil
            defer { self.isCleaning = false }
            do {
                guard previewIdentity == selection.identity, previewIdentity != nil else {
                    throw AdapterError.message("CLI 连接已变化，请重新扫描。")
                }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("mole-selection-\(UUID().uuidString).json")
                try plan.encoded().write(to: file, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: file) }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                let result = try await self.runner.clean(selection: selection, file: file, compatibility: compatibility)
                let completed = try CleanResult.decode(result.data)
                try completed.validate(selectedPaths: expectedPaths)
                self.cleanResult = completed
                self.diagnostics = result.diagnostics
            } catch {
                throw AdapterError.message("清理已停止；部分项目可能已移除。请查看操作历史并重新扫描。\n\(error.localizedDescription)")
            }
        }
    }

    func cancel() { task?.cancel() }

    private func perform(_ activity: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        diagnostics = ""
        self.activity = activity
        task = Task {
            defer { busy = false; task = nil }
            do { try await operation() }
            catch is CancellationError { self.activity = "已取消" }
            catch { self.error = error.localizedDescription }
        }
    }
}
