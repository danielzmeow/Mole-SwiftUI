import SwiftUI

struct PendingFeatureView: View {
    let feature: Feature
    var body: some View {
        ContentUnavailableView(feature.title, systemImage: feature.symbol, description: Text("尚未接入"))
    }
}
