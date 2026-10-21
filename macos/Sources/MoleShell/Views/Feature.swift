import Foundation
import MoleAdapter

enum Feature: String, CaseIterable, Identifiable {
    case clean, uninstall, optimize, analyze, status, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "系统状态"
        case .analyze: "磁盘分析"
        case .clean: "空间清理"
        case .uninstall: "应用管理"
        case .optimize: "系统优化"
        case .history: "操作历史"
        }
    }
    var symbol: String {
        switch self {
        case .status: "gauge.with.dots.needle.50percent"
        case .analyze: "chart.pie"
        case .clean: "sparkles"
        case .uninstall: "square.grid.2x2"
        case .optimize: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        }
    }
    var request: CLIRequest? {
        switch self {
        case .clean: .cleanPreview
        case .status: .status
        case .analyze: .analyze(path: nil)
        case .uninstall: .applications
        case .history: .history
        default: nil
        }
    }
}
