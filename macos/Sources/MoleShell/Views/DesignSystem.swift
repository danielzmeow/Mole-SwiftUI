import SwiftUI
import MoleAdapter

/// One spacing and type scale for every page, so sections line up across navigation.
enum Metrics {
    static let pagePadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 32
    static let contentWidth: CGFloat = 1040
    static let rowHeight: CGFloat = 36
}

/// Scrolling page: large title, optional trailing accessory, then aligned sections.
struct Page<Accessory: View, Content: View>: View {
    let title: String
    /// Data only (a path, a hardware line); never explanatory copy.
    var subtitle: String = ""
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.largeTitle.weight(.semibold)).lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled).help(subtitle)
                        }
                    }
                    Spacer(minLength: 16)
                    accessory
                }
                content
            }
            .padding(Metrics.pagePadding)
            .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

extension Page where Accessory == EmptyView {
    init(title: String, subtitle: String = "", @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// Section label with an optional trailing count; content follows with a hairline above.
struct PageSection<Content: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if !detail.isEmpty {
                    Text(detail).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Large figure with a small label, used for headline numbers.
struct Metric: View {
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Thin capacity bar. Turns orange only when nearly full, which is the one state worth noticing.
struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 4

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(clamped >= 0.9 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .frame(width: max(clamped > 0 ? height : 0, geometry.size.width * clamped))
                }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(clamped.formatted(.percent.precision(.fractionLength(0)))))
    }
}

/// Native empty state with a single action.
struct EmptyAction: View {
    let title: String
    let symbol: String
    let actionTitle: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(disabled)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// Full-width list row: hover highlight on interactive rows, hairline between rows.
struct RowBackground: ViewModifier {
    var interactive: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(minHeight: Metrics.rowHeight)
            .background {
                if interactive && hovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quinary)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

extension View {
    func listRow(interactive: Bool = false) -> some View { modifier(RowBackground(interactive: interactive)) }
}

func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

extension JSONValue {
    var values: [JSONValue] {
        if case .array(let array) = self { return array }; return []
    }
    var percent: String { number.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—" }
    var byteLabel: String { number.map { bytes(Int64($0)) } ?? "—" }
}
