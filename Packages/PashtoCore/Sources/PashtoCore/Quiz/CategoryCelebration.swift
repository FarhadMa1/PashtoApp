import Foundation

/// The lesson-complete celebration. It is offered once per category.
///
/// The offer is the first completion of that category's last Practice lesson.
/// A later finish of the same lesson is a repeat and is not offered. Learn and
/// phrases are not offered. `celebratedUnits` is the set already stored, so a
/// category is not offered again after the celebration has been recorded.
public enum CategoryCelebration {
    /// The praise on the settled frame. The same phrase the content file uses.
    public static let praise = LessonPraise.deraKha

    /// Item id of the bundled clip for `praise`. The app plays it only after a tap.
    public static let praiseItemID: ItemID = {
        guard let id = ItemID(rawValue: "e-dera-xa") else {
            preconditionFailure("e-dera-xa is the bundled phrase id")
        }
        return id
    }()

    public static func offer(
        finishing lessonID: LessonID,
        in units: [CourseUnit],
        finishedBefore: Set<LessonID>,
        celebratedUnits: Set<UnitID>
    ) -> CategoryCelebrationOffer? {
        guard let unit = units.first(where: { $0.lessons.contains { $0.id == lessonID } }) else {
            return nil
        }
        let practice = unit.lessons.filter { $0.kind == .practice }
        guard let last = practice.last, last.id == lessonID else { return nil }
        guard !finishedBefore.contains(lessonID) else { return nil }
        guard !celebratedUnits.contains(unit.id) else { return nil }
        let total = practice.count
        let before = practice.filter { finishedBefore.contains($0.id) }.count
        return CategoryCelebrationOffer(
            unitID: unit.id,
            unitName: MainMenuLabels.word(for: unit.id, title: unit.title),
            ringFrom: Double(before) / Double(total),
            ringTo: min(1, Double(before + 1) / Double(total))
        )
    }
}

/// What the celebration draws for one category.
public struct CategoryCelebrationOffer: Equatable, Sendable {
    public var unitID: UnitID
    /// Stored unit word. The screen uppercases it when it draws.
    public var unitName: String
    /// Progress ring before this lesson, from 0 to 1.
    public var ringFrom: Double
    /// Progress ring after this lesson, from 0 to 1.
    public var ringTo: Double

    public init(unitID: UnitID, unitName: String, ringFrom: Double, ringTo: Double) {
        self.unitID = unitID
        self.unitName = unitName
        self.ringFrom = ringFrom
        self.ringTo = ringTo
    }
}

/// Frames of the celebration.
///
/// `ring` fills the unit ring. `unfold` turns that ring into the girih star.
/// `praise` is the frame that stays. Reduce Motion opens on `praise`.
public enum CategoryCelebrationPhase: Equatable, Sendable {
    case ring
    case unfold
    case praise
}

/// Timings from the approved sketch. The pieces play in order.
public enum CategoryCelebrationPlayback {
    /// The unit ring fills.
    public static let ringFill: TimeInterval = 0.4
    /// The ring unfolds into the 16-point star.
    public static let unfold: TimeInterval = 0.5

    public static func opening(reduceMotion: Bool) -> CategoryCelebrationPhase {
        reduceMotion ? .praise : .ring
    }

    /// The frame at `elapsed` seconds from the start.
    ///
    /// Reduce Motion is the settled frame at every time, including zero.
    public static func phase(reduceMotion: Bool, elapsed: TimeInterval) -> CategoryCelebrationPhase {
        if reduceMotion { return .praise }
        if elapsed < ringFill { return .ring }
        if elapsed < ringFill + unfold { return .unfold }
        return .praise
    }
}

/// One 16-point girih star, in the sketch's coordinate space.
///
/// The view box is 220 units across, centered on the origin. Even vertices use
/// the outer radius and odd vertices use the inner radius. `morph` 0 is a
/// circle. `morph` 1 is the star.
public enum CategoryCelebrationStar {
    public static let pointCount = 16
    public static let viewBox: Double = 220
    public static let ringSide: Double = 44
    public static let unfoldSide: Double = 220
    public static let praiseSide: Double = 180

    public struct Layer: Equatable, Sendable {
        public var outer: Double
        public var inner: Double

        public init(outer: Double, inner: Double) {
            self.outer = outer
            self.inner = inner
        }
    }

    /// Outer, middle, then the saffron center. Radii are the sketch's.
    public static let layers: [Layer] = [
        Layer(outer: 104, inner: 72),
        Layer(outer: 80, inner: 56),
        Layer(outer: 42, inner: 30),
    ]

    public struct Vertex: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public static func points(outer: Double, inner: Double, morph: Double) -> [Vertex] {
        let blend = min(1, max(0, morph))
        let circle = (outer + inner) / 2
        var vertices: [Vertex] = []
        vertices.reserveCapacity(pointCount)
        for index in 0..<pointCount {
            let angle = Double.pi * Double(index) / Double(pointCount / 2)
            let starRadius = index.isMultiple(of: 2) ? outer : inner
            let radius = circle + (starRadius - circle) * blend
            vertices.append(Vertex(x: radius * sin(angle), y: -radius * cos(angle)))
        }
        return vertices
    }
}

/// The categories whose celebration has already been shown.
///
/// The file sits next to the progress store. A missing or unreadable file is
/// an empty set, so the first completion can still be offered.
public enum CategoryCelebrationStore {
    public static let fileName = "category-celebrations.json"

    public static func fileURL(beside storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    public static func load(beside storeURL: URL) -> Set<UnitID> {
        let url = fileURL(beside: storeURL)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let stored = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        var ids: Set<UnitID> = []
        for raw in stored.unitIDs {
            if let id = UnitID(rawValue: raw) {
                ids.insert(id)
            }
        }
        return ids
    }

    public static func save(_ ids: Set<UnitID>, beside storeURL: URL) throws {
        let url = fileURL(beside: storeURL)
        let stored = File(unitIDs: ids.map(\.rawValue).sorted())
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the file. A missing file is already empty.
    public static func reset(beside storeURL: URL) {
        try? FileManager.default.removeItem(at: fileURL(beside: storeURL))
    }

    private struct File: Codable {
        var unitIDs: [String]
    }
}
