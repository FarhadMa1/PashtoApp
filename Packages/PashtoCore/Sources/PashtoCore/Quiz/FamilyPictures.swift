import Foundation

/// Pictures for the seven family learn cards.
///
/// The asset name is the item id. The accessibility label is that item's
/// English word, so the catalog does not gain a new string. Practice and
/// phrases return nil: a picture in a quiz would show the answer.
public enum FamilyPictures {
    public struct Picture: Equatable, Sendable {
        public var assetName: String
        public var accessibilityLabel: String

        public init(assetName: String, accessibilityLabel: String) {
            self.assetName = assetName
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public static let itemIDs: [String] = [
        "e-mor",
        "e-plar",
        "e-wror",
        "e-xor",
        "e-zoy",
        "e-lur",
        "e-koraney",
    ]

    /// Nil unless `lessonKind` is learn and `itemID` is one of the seven.
    public static func picture(for itemID: ItemID, english: String?, lessonKind: LessonKind) -> Picture? {
        guard lessonKind == .learn else { return nil }
        guard itemIDs.contains(itemID.rawValue) else { return nil }
        let label = english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !label.isEmpty else { return nil }
        return Picture(assetName: itemID.rawValue, accessibilityLabel: label)
    }
}
