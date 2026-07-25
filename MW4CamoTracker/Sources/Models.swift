import Foundation

/// One JSON file per mode (multiplayer/campaign/dmz/...), all sharing this shape.
/// Adding a mode is adding a file + a manifest entry — never a new Swift type.
struct ModeFile: Codable {
    let version: String
    let mode: String
    let categories: [Category]
}

struct Category: Codable, Identifiable {
    let categoryId: Int
    let nameKey: String
    var items: [ChallengeItem]
    var id: Int { categoryId }
}

/// A weapon, a camo tier, a DMZ objective, a campaign mission — all the same node.
/// Weapons carry their camos as `children`; a leaf item has an empty `children` array.
struct ChallengeItem: Codable, Identifiable {
    let itemId: Int
    let nameKey: String
    let imageRef: String?
    let tier: Int?
    let requirement: Requirement?
    var children: [ChallengeItem]
    var id: Int { itemId }

    var isLeaf: Bool { children.isEmpty }
}

struct Requirement: Codable {
    let amount: Int
    let unit: String
    let descriptionKey: String
}
