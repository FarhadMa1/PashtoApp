import Foundation

/// A course category. Card color comes from `colorFamily`, never from a unit id.
public struct CourseCategory: Codable, Hashable, Sendable {
    public let number: Int
    public let level: Int
    public let title: String
    public let colorFamily: String

    public init(number: Int, level: Int, title: String, colorFamily: String) {
        self.number = number
        self.level = level
        self.title = title
        self.colorFamily = colorFamily
    }
}

/// One item's membership in one category. An item can belong to several.
public struct CategoryMembership: Codable, Hashable, Sendable {
    public let category: Int
    public let item: ItemID

    public init(category: Int, item: ItemID) {
        self.category = category
        self.item = item
    }
}
