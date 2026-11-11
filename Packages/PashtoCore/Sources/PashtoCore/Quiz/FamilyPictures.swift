import Foundation

/// Pictures for the learn cards that have one.
///
/// Family, Travel, Time, and the taxi on Town. The asset name is the item id.
/// The accessibility label is that item's English word, so the catalog does
/// not gain a new string. Practice and phrases return nil: a picture in a
/// quiz would show the answer. The taxi picture is Town only, so the same
/// item on Travel's Getting around card has no image.
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
        "e-ha-waa-yee-da-gar",
        "e-ho-tal",
        "e-ti-kat",
        "e-tash-naab",
        "e-tak-see",
        "e-pay-se",
        "e-wradz",
        "e-sa-haar",
        "e-maa-khaam",
        "e-shpa",
    ]

    /// Item ids whose picture is shown only inside this unit.
    /// The taxi asset stays shared; Travel does not use it.
    public static let limitedToUnit: [String: String] = [
        "e-tak-see": "u-town",
    ]

    /// Nil unless `lessonKind` is learn and `itemID` is pictured.
    /// A unit-limited item also needs that unit.
    public static func picture(
        for itemID: ItemID,
        english: String?,
        lessonKind: LessonKind,
        unitID: UnitID? = nil
    ) -> Picture? {
        guard lessonKind == .learn else { return nil }
        guard itemIDs.contains(itemID.rawValue) else { return nil }
        if let onlyUnit = limitedToUnit[itemID.rawValue], unitID?.rawValue != onlyUnit {
            return nil
        }
        let label = english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !label.isEmpty else { return nil }
        return Picture(assetName: itemID.rawValue, accessibilityLabel: label)
    }
}
