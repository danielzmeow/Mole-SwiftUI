import Foundation

public struct CleanPreviewCapability: Decodable, Sendable {
    public let schemaVersion: Int
    public let command: String
    public let mode: String
    public let coverage: String
    public let executionSupported: Bool
    public let sourceRoot: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", command, mode, coverage
        case executionSupported = "execution_supported"
        case sourceRoot = "source_root"
    }
}

public struct CleanPreview: Decodable, Sendable {
    public let schemaVersion: Int
    public let command: String
    public let mode: String
    public let coverage: String
    public let executionSupported: Bool
    public let createdAt: Int64
    public let systemIncluded: Bool
    public let sizePartial: Bool
    public let totalSizeBytes: Int64
    public let totalItems: Int64
    public let entries: [CleanPreviewEntry]

    public static func decode(_ data: Data) throws -> Self {
        let preview = try CLIResponses.decode(Self.self, from: data)
        guard preview.schemaVersion == 2, preview.command == "clean", preview.mode == "preview",
              preview.coverage == "path_candidates", preview.executionSupported,
              preview.totalSizeBytes >= 0, preview.totalItems >= 0,
              preview.entries.allSatisfy({ $0.path.hasPrefix("/") && $0.itemCount > 0 && ($0.sizeBytes ?? 0) >= 0 }) else {
            throw AdapterError.message("清理预览格式不受支持，请重新构建 App。")
        }
        return preview
    }
}

public struct CleanPreviewEntry: Decodable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let section: String
    public let sizeBytes: Int64?
    public let itemCount: Int64
    public let countedUnder: String?
    public let selectionToken: String?
}

public struct CleanSelection: Encodable, Sendable {
    public let schemaVersion = 2
    public let createdAt: Int64
    public let selections: [String]

    public init(preview: CleanPreview, paths: Set<String>) {
        createdAt = preview.createdAt
        selections = preview.entries.filter { paths.contains($0.path) }.compactMap(\.selectionToken)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }
}

public struct CleanResult: Decodable, Sendable {
    public let schemaVersion: Int
    public let command: String
    public let mode: String
    public let interrupted: Bool
    public let results: [CleanPathResult]

    public func validate(selectedPaths: Set<String>) throws {
        guard results.count == selectedPaths.count, Set(results.map(\.path)) == selectedPaths else {
            throw AdapterError.message("清理结果未覆盖本次选择；请查看操作历史并重新扫描。")
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        let result = try CLIResponses.decode(Self.self, from: data)
        guard result.schemaVersion == 2, result.command == "clean", result.mode == "selection_result",
              result.results.allSatisfy({ ["removed", "retained", "failed"].contains($0.status) }) else {
            throw AdapterError.message("清理结果格式无效；请查看操作历史并重新扫描。")
        }
        return result
    }
}

public struct CleanPathResult: Decodable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let status: String
    public let reason: String
}
