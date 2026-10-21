import Foundation

public enum ScanStatus: String, Decodable, Sendable {
    case complete, partial, unavailable
    public var label: String {
        switch self { case .complete: "完整"; case .partial: "部分结果 · 至少"; case .unavailable: "无法测量" }
    }
}

public struct Analysis: Decodable, Sendable {
    public let scanStatus: ScanStatus
    public let path: String
    public let overview: Bool
    public let entries: [AnalysisEntry]?
    public let largeFiles: [LargeFile]?
    public let totalSize: Int64
    public let totalFiles: Int64?
}

public struct AnalysisEntry: Decodable, Identifiable, Sendable {
    public var id: String { path }
    public let scanStatus: ScanStatus
    public let name: String
    public let path: String
    public let size: Int64
    public let isDir: Bool
    public let cleanable: Bool?
    public let insight: Bool?
    public let lastAccess: String?
}

public struct LargeFile: Decodable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
}

public struct InstalledApplication: Decodable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let bundleId: String
    public let source: String
    public let uninstallName: String
    public let path: String
    public let size: String
}

public struct OperationHistory: Decodable, Sendable {
    public let sessions: [HistorySession]
    public let deletions: [HistoryDeletion]
    public let logs: [String: String]
}

public struct HistorySession: Decodable, Sendable {
    public let command: String
    public let runId: String
    public let attribution: String
    public let startedAt: String
    public let endedAt: String
    public let items: Int
    public let size: String
    public let operationCount: Int
    public let failedTasks: Int
    public let actions: [String: Int]
}

public struct HistoryDeletion: Decodable, Sendable {
    public let timestamp: String
    public let mode: String
    public let status: String
    public let sizeKb: Int64?
    public let path: String
}

/// Retains every metric from the CLI, including fields without a summary card.
public indirect enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public subscript(key: String) -> JSONValue {
        if case .object(let values) = self { return values[key] ?? .null }
        return .null
    }
    public var number: Double? { if case .number(let value) = self { return value }; return nil }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var display: String {
        switch self {
        case .string(let value): value.isEmpty ? "—" : value
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let value): value ? "是" : "否"
        case .null: "未提供"
        case .array(let values): "\(values.count) 项"
        case .object(let values): "\(values.count) 项"
        }
    }
}

public enum CLIResponses {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(type, from: data) }
        catch { throw AdapterError.message("CLI 返回的数据与当前接口不匹配。\n\(error.localizedDescription)") }
    }
}
