import Foundation
import CryptoKit

/// Pin the launcher and all shell policy sources at connection and again at execution.
/// A command failure never causes resolution or fallback to another executable.
public struct CLIIdentity: Equatable, Sendable {
    public let sourceRoot: URL
    public let digest: String

    static func capture(executable: URL, sourceRoot: URL) throws -> Self {
        let manager = FileManager.default
        let root = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        var sources = [executable.resolvingSymlinksInPath()]
        for directory in ["bin", "lib"] {
            let base = root.appendingPathComponent(directory)
            let baseValues = try base.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard baseValues.isSymbolicLink != true, baseValues.isDirectory == true else {
                throw AdapterError.message("CLI 源目录无法验证，请重新构建 App。")
            }
            var enumerationFailed = false
            guard let files = manager.enumerator(at: base, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                                                  options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
                throw AdapterError.message("无法验证 CLI 源文件，请重新连接。")
            }
            for case let file as URL in files {
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true else {
                    throw AdapterError.message("CLI 源目录包含符号链接，无法验证清理执行。")
                }
                if file.pathExtension == "sh", values.isRegularFile == true { sources.append(file.standardizedFileURL) }
                guard sources.count <= 1024 else { throw AdapterError.message("CLI 源文件超出验证范围。") }
            }
            guard !enumerationFailed else { throw AdapterError.message("CLI 源文件不可完整读取，已停止清理验证。") }
        }
        guard sources.contains(where: { $0.path == root.appendingPathComponent("bin/clean.sh").standardizedFileURL.path }) else {
            throw AdapterError.message("找不到可验证的 CLI 清理入口，请重新构建 App。")
        }
        var hasher = SHA256()
        var size = 0
        for file in Set(sources).sorted(by: { $0.path < $1.path }) {
            let attributes = try manager.attributesOfItem(atPath: file.path)
            size += (attributes[.size] as? NSNumber)?.intValue ?? 16 * 1024 * 1024 + 1
            guard size <= 16 * 1024 * 1024 else { throw AdapterError.message("CLI 源文件超出验证大小。") }
            let data = try Data(contentsOf: file)
            let metadata = "\(file.path)\u{0}\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? ""):\(data.count)\u{0}"
            hasher.update(data: Data(metadata.utf8))
            hasher.update(data: data)
        }
        return Self(sourceRoot: root, digest: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    func validate(executable: URL) throws {
        guard try Self.capture(executable: executable, sourceRoot: sourceRoot) == self else {
            throw AdapterError.message("CLI 文件已变化，已停止清理。请重新连接并扫描。")
        }
    }
}
