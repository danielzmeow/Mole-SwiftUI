import Foundation
import Darwin

public enum AdapterError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

public struct CLIResult: Sendable {
    public let data: Data
    public let diagnostics: String
    public var text: String { String(decoding: data, as: UTF8.self) }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var cancelled: Bool { lock.withLock { value } }
}

public struct ProcessRunner: Sendable {
    public let outputLimit: Int
    public init(outputLimit: Int = 32 * 1024 * 1024) { self.outputLimit = outputLimit }

    public func run(executable: URL, request: CLIRequest) async throws -> CLIResult {
        if case .cleanSelection = request {
            throw AdapterError.message("清理执行必须先验证 CLI 身份。")
        }
        return try await execute(executable: executable, arguments: request.arguments, timeout: request.timeout)
    }

    public func clean(selection: CLISelection, file: URL, compatibility: CLICompatibility) async throws -> CLIResult {
        guard let identity = selection.identity else { throw AdapterError.message("CLI 未通过清理身份验证，请重新连接。") }
        try identity.validate(executable: selection.executable)
        let version = try await run(executable: selection.executable, request: .version)
        guard compatibility.accepts(version.text) else { throw AdapterError.message("CLI 版本已变化，请重新连接并扫描。") }
        let capability = try await run(executable: selection.executable, request: .cleanPreviewHelp)
        let contract = try JSONDecoder().decode(CleanPreviewCapability.self, from: capability.data)
        guard contract.schemaVersion == 2, contract.executionSupported else {
            throw AdapterError.message("CLI 清理接口已变化，请重新连接并扫描。")
        }
        try Task.checkCancellation()
        try identity.validate(executable: selection.executable)
        let request = CLIRequest.cleanSelection(file: file.path)
        return try await execute(executable: selection.executable, arguments: request.arguments, timeout: request.timeout, mutation: true)
    }

    // Internal so tests can exercise timeout/cancellation with harmless fixtures.
    func execute(executable: URL, arguments: [String], timeout: TimeInterval, mutation: Bool = false) async throws -> CLIResult {
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .userInitiated) {
                try collect(executable: executable, arguments: arguments, timeout: timeout, mutation: mutation, flag: flag)
            }.value
        } onCancel: { flag.cancel() }
    }

    private func collect(executable: URL, arguments: [String], timeout: TimeInterval,
                         mutation: Bool, flag: CancellationFlag) throws -> CLIResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AdapterError.message("CLI 不存在或不可执行：\(executable.path)")
        }
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { throw AdapterError.message("无法创建输出通道。") }
        guard pipe(&err) == 0 else {
            close(out[0]); close(out[1])
            throw AdapterError.message("无法创建诊断通道。")
        }
        defer { close(out[0]); close(err[0]) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO)
        for fd in out + err { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawn_file_actions_addchdir(&actions, NSHomeDirectory())
        // An owned process group lets cancellation also stop CLI probe children.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        var environment = ProcessInfo.processInfo.environment
        // Never inherit test bypasses, alternate log/config roots, or debug output.
        for key in environment.keys where key.hasPrefix("MOLE_") || key.hasPrefix("MO_") {
            environment.removeValue(forKey: key)
        }
        for key in ["BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "CDPATH"] {
            environment.removeValue(forKey: key)
        }
        for key in environment.keys where key.hasPrefix("BASH_FUNC_") { environment.removeValue(forKey: key) }
        environment["PATH"] = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawnError = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        close(out[1]); close(err[1])
        guard spawnError == 0 else { throw AdapterError.message("无法启动 CLI：\(String(cString: strerror(spawnError)))") }
        for fd in [out[0], err[0]] { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var stdout = Data(), stderr = Data(), status: Int32 = 0
        var reaped = false
        defer {
            if !reaped {
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            }
        }
        while true {
            if flag.cancelled { throw CancellationError() }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                throw AdapterError.message(mutation ? "清理执行超时，请查看操作历史并重新扫描，勿重复执行原选择。" : "CLI 读取超时，未取得完整结果。可以重试此只读操作。")
            }
            try drain(out[0], into: &stdout)
            try drain(err[0], into: &stderr)
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                reaped = true
                // Also close any children still holding pipes after their parent exits.
                kill(-pid, SIGKILL)
                try drain(out[0], into: &stdout)
                try drain(err[0], into: &stderr)
                break
            }
            if waited < 0 && errno != EINTR { throw AdapterError.message("无法读取 CLI 退出状态。") }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let diagnostics = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            throw AdapterError.message("CLI 退出码 \(code)。\n\(String(diagnostics.prefix(2000)))")
        }
        return CLIResult(data: stdout, diagnostics: diagnostics)
    }

    private func drain(_ fd: Int32, into data: inout Data) throws {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound every pass so a continuously writing child cannot starve cancellation.
        for _ in 0..<128 {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 {
                if count < 0 && errno != EAGAIN && errno != EINTR {
                    throw AdapterError.message("读取 CLI 输出失败。")
                }
                return
            }
            guard data.count + count <= outputLimit else {
                throw AdapterError.message("CLI 输出超过读取上限，未显示不完整结果。")
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
