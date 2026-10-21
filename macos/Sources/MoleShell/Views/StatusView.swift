import SwiftUI
import MoleAdapter

struct StatusView: View {
    @Bindable var model: AppModel
    private var snapshot: JSONValue { model.status ?? .null }
    private var disk: JSONValue {
        snapshot["disks"].values.first(where: { $0["mount"].string == "/" }) ?? snapshot["disks"].values.first ?? .null
    }
    private var hardwareLine: String {
        [snapshot["hardware"]["cpu_model"].string, snapshot["hardware"]["total_ram"].string,
         snapshot["hardware"]["os_version"].string].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Page(title: snapshot["hardware"]["model"].string ?? "系统状态", subtitle: hardwareLine) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot["health_score"].number.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text("健康评分").font(.callout).foregroundStyle(.secondary)
            }
        } content: {
            Grid(alignment: .topLeading, horizontalSpacing: 40, verticalSpacing: 28) {
                GridRow {
                    resource("处理器", value: snapshot["cpu"]["usage"].percent,
                        fraction: (snapshot["cpu"]["usage"].number ?? 0) / 100,
                        detail: snapshot["cpu"]["logical_cpu"].number.map { "\(Int($0)) 核" } ?? "—")
                    resource("内存", value: snapshot["memory"]["used_percent"].percent,
                        fraction: (snapshot["memory"]["used_percent"].number ?? 0) / 100,
                        detail: snapshot["memory"]["used"].byteLabel + " / " + snapshot["memory"]["total"].byteLabel)
                    resource("磁盘", value: disk["used"].byteLabel,
                        fraction: (disk["used_percent"].number ?? 0) / 100,
                        detail: "共 " + disk["total"].byteLabel)
                }
                GridRow {
                    Divider().gridCellColumns(3)
                }
                GridRow {
                    battery
                    rate("下载", snapshot["network"].values.first?["rx_rate_mbs"] ?? .null)
                    rate("上传", snapshot["network"].values.first?["tx_rate_mbs"] ?? .null)
                }
            }

            PageSection(title: "进程") {
                processHeader
                let processes = Array(snapshot["top_processes"].values.prefix(6))
                if processes.isEmpty {
                    Text("—").foregroundStyle(.secondary).listRow()
                }
                VStack(spacing: 0) {
                    ForEach(processes.indices, id: \.self) { index in
                        processRow(processes[index])
                    }
                }
            }

            DisclosureGroup("全部指标") {
                JSONFieldsView(value: snapshot).padding(.top, 12)
            }
            .foregroundStyle(.secondary)
            .disabled(model.status == nil)
        }
    }

    private func resource(_ title: String, value: String, fraction: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Metric(label: title, value: value)
            UsageBar(fraction: fraction)
            Text(detail).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var battery: some View {
        let battery = snapshot["batteries"].values.first
        VStack(alignment: .leading, spacing: 10) {
            Metric(label: "电池", value: battery?["percent"].percent ?? "—")
            if let battery { Text(battery["status"].display).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rate(_ title: String, _ value: JSONValue) -> some View {
        Metric(label: title,
               value: value.number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—",
               unit: value.number == nil ? "" : "MB/s")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processHeader: some View {
        HStack {
            Text("名称")
            Spacer()
            Text("CPU").frame(width: 72, alignment: .trailing)
            Text("内存").frame(width: 96, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func processRow(_ process: JSONValue) -> some View {
        HStack {
            Text(process["name"].display).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 16)
            Text(process["cpu"].percent).frame(width: 72, alignment: .trailing)
            Text(process["memory_bytes"].number == nil ? process["memory"].percent : process["memory_bytes"].byteLabel)
                .foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
        }
        .monospacedDigit()
        .listRow()
    }
}
