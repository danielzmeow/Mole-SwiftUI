import Foundation
import Testing
@testable import MoleAdapter

@Test(.enabled(if: ProcessInfo.processInfo.environment["MOLE_SHELL_SMOKE_CLI"] != nil))
func bundledReadOnlyInterfaces() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["MOLE_SHELL_SMOKE_CLI"])
    let executable = URL(fileURLWithPath: path)
    let contract = CLICompatibility(version: "1.62.0", sourceCommit: "smoke")
    let runner = ProcessRunner()
    let version = try await runner.run(executable: executable, request: .version)
    #expect(contract.accepts(version.text))

    let status = try await runner.run(executable: executable, request: .status)
    let metrics = try JSONDecoder().decode(JSONValue.self, from: status.data)
    #expect(metrics["health_score"].number != nil)
    #expect(metrics["host"].string != nil)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("test".utf8).write(to: directory.appendingPathComponent("sample.txt"))
    let scan = try await runner.run(executable: executable, request: .analyze(path: directory.path))
    let analysis = try CLIResponses.decode(Analysis.self, from: scan.data)
    #expect(analysis.scanStatus == .complete)
    #expect(analysis.entries?.contains(where: { $0.name == "sample.txt" }) == true)

    let log = try await runner.run(executable: executable, request: .history)
    let history = try CLIResponses.decode(OperationHistory.self, from: log.data)
    #expect(history.sessions.count <= 200)
    #expect(history.logs["operations"] != nil)

    let inventory = try await runner.run(executable: executable, request: .applications)
    let applications = try CLIResponses.decode([InstalledApplication].self, from: inventory.data)
    #expect(applications.allSatisfy { $0.path.hasPrefix("/") })

    // On this developer machine, the old installed release should be rejected.
    let resolved = try await CLIResolver().resolve(compatibility: contract, bundled: executable,
        candidates: CLIResolver.installedCandidates())
    #expect(contract.accepts(try await runner.run(executable: resolved.executable, request: .version).text))
}
