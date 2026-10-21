import Foundation
import MoleAdapter

enum Feature: String, CaseIterable, Identifiable {
    case status, analyze, clean, uninstall, purge, installer, optimize, slim, history, touchid, completion, update, remove
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "系统状态"
        case .analyze: "磁盘分析"
        case .clean: "空间清理"
        case .uninstall: "应用管理"
        case .purge: "项目清理"
        case .installer: "安装包清理"
        case .optimize: "系统优化"
        case .slim: "应用瘦身"
        case .history: "操作历史"
        case .touchid: "Touch ID"
        case .completion: "Shell 补全"
        case .update: "CLI 更新"
        case .remove: "CLI 移除"
        }
    }
    var symbol: String {
        switch self {
        case .status: "gauge.with.dots.needle.50percent"
        case .analyze: "chart.pie"
        case .clean: "sparkles"
        case .uninstall: "square.grid.2x2"
        case .purge: "hammer"
        case .installer: "shippingbox"
        case .optimize: "slider.horizontal.3"
        case .slim: "arrow.down.right.and.arrow.up.left"
        case .history: "clock.arrow.circlepath"
        case .touchid: "touchid"
        case .completion: "text.append"
        case .update: "arrow.down.circle"
        case .remove: "minus.circle"
        }
    }
    var request: CLIRequest? {
        switch self {
        case .status: .status
        case .analyze: .analyze(path: nil)
        case .uninstall: .applications
        case .history: .history
        default: nil
        }
    }
}
