import Foundation
import Testing
@testable import MoleAdapter

private struct Fixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func executable(_ name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ("#!/bin/bash\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let contract = CLICompatibility(version: "1.62.0", sourceCommit: "fixture")

@Test func onlyExactStableVersionIsCompatible() {
    #expect(contract.accepts("\nMole version 1.62.0\nmacOS: 27.0\n"))
    for value in ["1.61.0", "1.63.0", "1.62.00", "1.62.0-windows"] {
        #expect(!contract.accepts("Mole version \(value)"))
    }
    #expect(!contract.accepts("Mole version 1.62.0\nChannel: Nightly (abc)"))
    #expect(!contract.accepts("Mole version 1.62.0\nInstall: Homebrew (HEAD abc)"))
    #expect(!contract.accepts("unrelated 1.62.0"))
}

@Test func resolverPrefersMatchingInstallationAndFallsBackForOldOrFailedCandidates() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let old = try fixture.executable("old", body: "echo 'Mole version 1.59.1'")
    let failed = try fixture.executable("failed", body: "echo 'Mole version 1.62.0'; exit 3")
    let matching = try fixture.executable("matching", body: "echo 'Mole version 1.62.0'")
    let bundled = try fixture.executable("bundled", body: "echo 'Mole version 1.62.0'")
    let resolver = CLIResolver()
    let installed = try await resolver.resolve(compatibility: contract, bundled: bundled, candidates: [old, failed, matching])
    #expect(installed.origin == .installed)
    #expect(installed.executable == matching)
    let fallback = try await resolver.resolve(compatibility: contract, bundled: bundled, candidates: [old, failed])
    #expect(fallback.origin == .bundled)
    #expect(fallback.executable == bundled)
    let absent = try await resolver.resolve(compatibility: contract, bundled: bundled, candidates: [])
    #expect(absent.origin == .bundled)
}

@Test func invalidBundleFailsClosed() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let bundled = try fixture.executable("bundled", body: "echo 'Mole version 1.61.0'")
    await #expect(throws: AdapterError.self) {
        try await CLIResolver().resolve(compatibility: contract, bundled: bundled, candidates: [])
    }
}

@Test func commandArgumentsDoNotBecomeShellCode() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let script = try fixture.executable("echoargs", body: "printf '%s\\n' \"$@\"")
    let path = "/tmp/quotes ' $(touch SHOULD_NOT_EXIST); space"
    let result = try await ProcessRunner().run(executable: script, request: .analyze(path: path))
    #expect(result.text == "analyze\n--json\n\(path)\n")
    #expect(CLIRequest.applications.arguments == ["uninstall", "--list"])
}

@Test func drainsBothPipesAndPreservesExitFailures() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let noisy = try fixture.executable("noisy", body: "for ((i=0;i<10000;i++)); do echo output; echo diagnostic >&2; done")
    let result = try await ProcessRunner().run(executable: noisy, request: .history)
    #expect(result.data.count == 70000)
    #expect(result.diagnostics.hasSuffix("diagnostic"))
    let failed = try fixture.executable("failed", body: "echo permission-denied >&2; exit 7")
    do {
        _ = try await ProcessRunner().run(executable: failed, request: .history)
        Issue.record("Nonzero exit must fail")
    } catch {
        #expect(error.localizedDescription.contains("7"))
        #expect(error.localizedDescription.contains("permission-denied"))
    }
}

@Test func outputLimitRejectsPartialData() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let script = try fixture.executable("large", body: "printf '1234567890'")
    await #expect(throws: AdapterError.self) {
        try await ProcessRunner(outputLimit: 5).run(executable: script, request: .history)
    }
}

@Test func timeoutAndCancellationStopOwnedChildren() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    // A delayed marker would prove a child escaped the owned process group.
    let marker = fixture.directory.appendingPathComponent("escaped")
    let script = try fixture.executable("slow", body: "(/bin/sleep 1; /usr/bin/touch '\(marker.path)') &\nwait")
    await #expect(throws: AdapterError.self) {
        try await ProcessRunner().execute(executable: script, arguments: [], timeout: 0.05)
    }
    let task = Task { try await ProcessRunner().execute(executable: script, arguments: [], timeout: 10) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancellation must throw") }
    catch { #expect(error is CancellationError) }
    try await Task.sleep(for: .milliseconds(1100))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func decodesPartialUnknownAndNullCollections() throws {
    let data = Data(#"{"scan_status":"partial","path":"/tmp","overview":false,"entries":[{"scan_status":"unavailable","name":"blocked","path":"/tmp/blocked","size":-1,"is_dir":true}],"large_files":null,"total_size":42}"#.utf8)
    let result = try CLIResponses.decode(Analysis.self, from: data)
    #expect(result.scanStatus == .partial)
    #expect(result.entries?.first?.scanStatus == .unavailable)
    #expect(result.entries?.first?.size == -1)
    #expect(result.largeFiles == nil)
    let empty = Data(#"{"scan_status":"complete","path":"/tmp","overview":true,"entries":null,"total_size":0}"#.utf8)
    #expect(try CLIResponses.decode(Analysis.self, from: empty).entries == nil)
}

@Test func decodesCLIInventoryAndHistoryShapes() throws {
    let apps = Data(#"[{"name":"App","bundle_id":"org.example.app","source":"App","uninstall_name":"App","path":"/Applications/App.app","size":"20MB"}]"#.utf8)
    #expect(try CLIResponses.decode([InstalledApplication].self, from: apps).first?.bundleId == "org.example.app")
    let history = Data(#"{"logs":{"operations":"/tmp/log"},"sessions":[{"command":"clean-dry-run","run_id":"1","attribution":"ambiguous","started_at":"today","ended_at":"","items":0,"size":"0B","operation_count":1,"failed_tasks":1,"actions":{"failed":1}}],"deletions":[{"timestamp":"today","mode":"trash","status":"denied","size_kb":null,"path":"/tmp/kept"}]}"#.utf8)
    let result = try CLIResponses.decode(OperationHistory.self, from: history)
    #expect(result.sessions.first?.attribution == "ambiguous")
    #expect(result.sessions.first?.actions["failed"] == 1)
    #expect(result.deletions.first?.status == "denied")
    #expect(result.deletions.first?.sizeKb == nil)
}

@Test func malformedJSONIsNotSalvagedFromTerminalProse() {
    #expect(throws: AdapterError.self) {
        try CLIResponses.decode(Analysis.self, from: Data("Progress... {}".utf8))
    }
}
