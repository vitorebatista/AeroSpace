import SwiftUI

/// The strip above the cluster lists: one chip per item, in three drop zones laid out the way
/// the bar is.
///
/// Schematic on purpose. It says *what is where*, not what sketchybar will draw — the bar at the
/// top of the screen is the preview, and a second implementation of sketchybar's fonts, padding
/// and metrics here would only drift out of sync with the one already running.
///
/// A drop mutates the same ordered `draft.items` the lists below edit, so the two views cannot
/// disagree about an order.
@MainActor
struct BarChipStrip: View {
    @Binding var draft: BarDraft
    let onEdit: () -> Void
    /// Catalog tools this machine does not have. A chip needing one is drawn as not rendering,
    /// which is the same thing the generated config will say about it.
    var missingTools: [BarExternalTool] = []

    /// The zone the drag is currently over, so it can say it will take the drop. Positions in
    /// `items` are the chips' identity, so nothing finer than the zone is worth highlighting.
    @State private var targetedCluster: BarCluster?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                zone(.left, alignment: .leading)
                divider
                zone(.center, alignment: .center)
                divider
                zone(.right, alignment: .trailing)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 0) {
                caption("Left", .leading)
                caption("Centre", .center)
                caption("Right", .trailing)
            }
        }
    }

    private var divider: some View {
        Divider().frame(height: 22).padding(.horizontal, 4)
    }

    private func caption(_ title: String, _ alignment: Alignment) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private func zone(_ cluster: BarCluster, alignment: Alignment) -> some View {
        let positions = draft.positions(in: cluster)
        HStack(spacing: 4) {
            if positions.isEmpty {
                Text("Drop here").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(positions, id: \.self) { chip($0) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: alignment)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(targetedCluster == cluster ? Color.accentColor : .clear, style: StrokeStyle(lineWidth: 1, dash: [3])),
        )
        // The zone takes what the chips don't: a drop on empty space appends to this cluster.
        .dropDestination(for: String.self) { payload, _ in
            drop(payload, to: cluster, before: nil)
        } isTargeted: { isTargeted in
            targetedCluster = isTargeted ? cluster : (targetedCluster == cluster ? nil : targetedCluster)
        }
    }

    @ViewBuilder
    private func chip(_ position: Int) -> some View {
        let item = draft.items.getOrNil(atIndex: position)
        let catalogItem = item.flatMap { BarCatalog.item(id: $0.id) }
        // An item this release does not know, or one whose tool is not installed. Drawn
        // distinctly rather than hidden, so its place in the bar is visible before it renders.
        let isPending = catalogItem.map { $0.externalTool.map(missingTools.contains) ?? false } ?? true
        let name = catalogItem?.displayName ?? item?.id ?? ""
        HStack(spacing: 4) {
            if let symbol = catalogItem?.icons.first(where: { $0.font == .sfSymbols })?.name {
                Image(systemName: symbol)
            }
            Text(name).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(isPending ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isPending ? 0.04 : 0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isPending ? Color.orange.opacity(0.7) : .clear,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2]),
                ),
        )
        .help(Self.chipHelp(catalogItem, item?.id ?? ""))
        .accessibilityLabel(name)
        .draggable(String(position))
        // Dropping onto a chip inserts before it; the innermost target wins, so this and the
        // zone's own append are the two placements a drag can make.
        .dropDestination(for: String.self) { payload, _ in
            drop(payload, to: draft.items.getOrNil(atIndex: position)?.cluster ?? .left, before: position)
        }
    }

    private func drop(_ payload: [String], to cluster: BarCluster, before: Int?) -> Bool {
        targetedCluster = nil
        // The payload is a position in `items`; anything else dragged in from outside is not ours.
        guard let position = payload.first.flatMap(Int.init), draft.items.indices.contains(position) else { return false }
        draft.moveItem(at: position, to: cluster, before: before)
        onEdit()
        return true
    }

    private static func chipHelp(_ catalogItem: BarCatalogItem?, _ id: String) -> String {
        guard let catalogItem else {
            return "\(id) isn't in this release's catalog. It is kept exactly as written."
        }
        guard let tool = catalogItem.externalTool else { return catalogItem.summary }
        return "\(catalogItem.summary)\n\nNeeds the \(tool.rawValue) command: \(tool.installHint)"
    }
}
