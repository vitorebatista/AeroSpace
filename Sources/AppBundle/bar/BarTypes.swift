/// Where an item sits in the bar. These are sketchybar's own three positions, and the
/// order of a cluster's items in `bar.toml` is the order they are drawn in.
///
/// Kept separate from both the model and the catalog because both need it and neither
/// should own it.
enum BarCluster: String, CaseIterable, Codable, Sendable {
    case left
    case center
    case right
}
