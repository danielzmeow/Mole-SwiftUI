import SwiftUI
import MoleAdapter

struct JSONFieldsView: View {
    let value: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch value {
            case .object(let values):
                ForEach(values.keys.sorted(), id: \.self) { key in
                    JSONFieldRow(title: key.replacingOccurrences(of: "_", with: " "), value: values[key]!)
                }
            case .array(let values):
                ForEach(values.indices, id: \.self) { index in JSONFieldRow(title: "\(index + 1)", value: values[index]) }
            default: Text(value.display).textSelection(.enabled)
            }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JSONFieldRow: View {
    let title: String
    let value: JSONValue
    var body: some View {
        switch value {
        case .object, .array:
            DisclosureGroup(title) { JSONFieldsView(value: value).padding(.leading, 12) }
        default:
            LabeledContent(title) { Text(value.display).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}
