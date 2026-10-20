import SwiftUI

struct MacPaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "water.waves").font(.system(size: 40)).foregroundStyle(.mint).accessibilityHidden(true)
            Text("UnderBlue Pro").font(.largeTitle.bold())
            Text("One-time purchase. Every dive.").font(.title3).foregroundStyle(.secondary)
            if let reason { Text(reason).font(.callout).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 12) {
                Label("Batch: many photos and videos in one run", systemImage: "square.grid.2x2")
                Label("Unlimited photo exports", systemImage: "photo")
                Label("Full-length video exports", systemImage: "video")
                Label("4K export", systemImage: "4k.tv")
                Label("HDR export where supported", systemImage: "sun.max")
            }
            if purchases.isPro {
                Label("Pro is unlocked", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
            } else if let product = purchases.product {
                Button(String(localized: "Buy Pro · \(product.displayPrice)")) { Task { await purchases.purchase() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Text("Purchase is currently unavailable.").foregroundStyle(.secondary)
                Button("Retry") { Task { await purchases.load() } }
            }
            Button("Restore Purchase") { Task { await purchases.restore() } }
            if purchases.busy { ProgressView() }
            if let message = purchases.message { Text(message).font(.callout) }
            Text("All processing stays on your Mac. No account or subscription.").font(.footnote).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(28).frame(width: 440).disabled(purchases.busy)
        .task { await purchases.load() }
    }
}
