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
        perform("正在读取 Mole…") {
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
            case .version: break
            }
            self.diagnostics = result.diagnostics
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
