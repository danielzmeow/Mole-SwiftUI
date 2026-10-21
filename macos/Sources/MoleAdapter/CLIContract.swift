import Foundation

public struct CLICompatibility: Codable, Sendable {
    public let version: String
    public let sourceCommit: String
    public let cleanPreviewSchema: Int?
    public init(version: String, sourceCommit: String, cleanPreviewSchema: Int? = nil) {
        self.version = version
        self.sourceCommit = sourceCommit
        self.cleanPreviewSchema = cleanPreviewSchema
    }

    public func accepts(_ output: String) -> Bool {
        let lines = output.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return lines.first(where: { !$0.isEmpty }) == "Mole version \(version)"
            && !output.localizedCaseInsensitiveContains("nightly")
            && !output.localizedCaseInsensitiveContains("HEAD")
    }
}

/// Public structured requests. Destructive selection requires an additional identity gate.
public enum CLIRequest: Sendable, Equatable {
    case version, status, analyze(path: String?), applications, history, cleanPreview, cleanPreviewHelp
    case cleanSelection(file: String)

    public var arguments: [String] {
        switch self {
        case .version: ["--version"]
        case .status: ["status", "--json"]
        case .analyze(let path): ["analyze", "--json"] + (path.map { [$0] } ?? [])
        case .applications: ["uninstall", "--list"]
        case .history: ["history", "--json", "--limit", "200"]
        case .cleanPreview: ["clean", "--dry-run", "--json"]
        case .cleanPreviewHelp: ["clean", "--json", "--help"]
        case .cleanSelection(let file): ["clean", "--json", "--apply-selection", file]
        }
    }

    public var timeout: TimeInterval {
        switch self {
        case .version, .cleanPreviewHelp: 10
        case .status: 45
        case .analyze, .applications: 180
        case .history: 30
        case .cleanPreview, .cleanSelection: 600
        }
    }
}

public struct CLISelection: Sendable, Equatable {
    public enum Origin: String, Sendable { case installed, bundled }
    public let executable: URL
    public let origin: Origin
    public let version: String
    public let explanation: String
    public let identity: CLIIdentity?
}

public struct CLIResolver: Sendable {
    public let runner: ProcessRunner
    public init(runner: ProcessRunner = ProcessRunner()) { self.runner = runner }

    public static func installedCandidates(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        var seen = Set<String>()
        return directories.filter { $0.hasPrefix("/") }.flatMap { directory in
            ["mo", "mole"].map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
        }.filter { url in
            FileManager.default.isExecutableFile(atPath: url.path)
                && seen.insert(url.resolvingSymlinksInPath().path).inserted
        }
    }

    public func resolve(compatibility: CLICompatibility, bundled: URL, candidates: [URL]) async throws -> CLISelection {
        var rejected = [String]()
        for executable in candidates {
            try Task.checkCancellation()
            do {
                let result = try await runner.run(executable: executable, request: .version)
                if compatibility.accepts(result.text) {
                    let identity = try await verifyPreviewInterface(executable, compatibility: compatibility)
                    return CLISelection(executable: executable, origin: .installed,
                        version: compatibility.version, explanation: "使用已安装且版本匹配的 Mole。", identity: identity)
                }
                rejected.append("\(executable.path)：版本不匹配")
            } catch is CancellationError { throw CancellationError() }
            catch { rejected.append("\(executable.path)：无法验证版本或清理预览接口") }
        }
        let result = try await runner.run(executable: bundled, request: .version)
        guard compatibility.accepts(result.text) else {
            throw AdapterError.message("内置 CLI 与适配版本不一致，请重新构建 App。")
        }
        let identity = try await verifyPreviewInterface(bundled, compatibility: compatibility)
        return CLISelection(executable: bundled, origin: .bundled, version: compatibility.version,
            explanation: rejected.isEmpty ? "未找到已安装的 Mole，使用内置版本。" : rejected.joined(separator: "\n") + "\n已回退到内置版本。", identity: identity)
    }

    private func verifyPreviewInterface(_ executable: URL, compatibility: CLICompatibility) async throws -> CLIIdentity? {
        guard let schema = compatibility.cleanPreviewSchema else { return nil }
        let result = try await runner.run(executable: executable, request: .cleanPreviewHelp)
        let capability = try JSONDecoder().decode(CleanPreviewCapability.self, from: result.data)
        guard capability.schemaVersion == schema, capability.command == "clean",
              capability.mode == "preview", capability.coverage == "path_candidates",
              (schema < 2 || capability.executionSupported) else {
            throw AdapterError.message("CLI 不支持已验证的清理预览接口，请重新构建 App。")
        }
        guard schema >= 2 else { return nil }
        guard let root = capability.sourceRoot, root.hasPrefix("/") else {
            throw AdapterError.message("CLI 没有返回可验证的源目录。")
        }
        return try CLIIdentity.capture(executable: executable, sourceRoot: URL(fileURLWithPath: root))
    }

}
