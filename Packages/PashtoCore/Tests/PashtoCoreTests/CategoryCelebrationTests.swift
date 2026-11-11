import Foundation
import Testing
@testable import PashtoCore

struct CategoryCelebrationTests {
    @Test func praiseReusesTheContentPhrase() throws {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent("content/units/u-greetings.json"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"pashto\": \"ډېره ښه\""))
        #expect(text.contains("\"pronunciation\": \"DE-ra kha\""))
        #expect(CategoryCelebration.praise == .deraKha)
        #expect(CategoryCelebration.praise.pashto == "ډېره ښه")
        #expect(CategoryCelebration.praise.pronunciation == "DE-ra kha")
        #expect(CategoryCelebration.praiseItemID.rawValue == "e-dera-xa")
        let audio = repoRoot().appendingPathComponent("PashtoApp/Audio")
        let clip = try #require(GreetingsAudio.url(for: CategoryCelebration.praiseItemID, in: audio))
        #expect(clip.lastPathComponent == "e-dera-xa.m4a")
    }

    @Test func onlyTheFirstCompletionOfTheLastPracticeLessonIsOffered() {
        let introductions = unit("u-introductions", title: "Introductions", lessons: [
            ("l-introductions-learn-names", .learn),
            ("l-introductions-phrases-name", .phrases),
            ("l-introductions-1", .practice),
            ("l-introductions-2", .practice),
            ("l-introductions-3", .practice),
        ])
        let family = unit("u-family", title: "Family", lessons: [
            ("l-family-learn-members", .learn),
            ("l-family-1", .practice),
            ("l-family-2", .practice),
            ("l-family-3", .practice),
        ])
        let units = [introductions, family]
        let finished: Set<LessonID> = [lessonID("l-introductions-1"), lessonID("l-introductions-2")]

        #expect(CategoryCelebration.offer(
            finishing: lessonID("l-introductions-1"),
            in: units,
            finishedBefore: [],
            celebratedUnits: []
        ) == nil)
        #expect(CategoryCelebration.offer(
            finishing: lessonID("l-introductions-learn-names"),
            in: units,
            finishedBefore: [],
            celebratedUnits: []
        ) == nil)
        #expect(CategoryCelebration.offer(
            finishing: lessonID("l-introductions-phrases-name"),
            in: units,
            finishedBefore: [],
            celebratedUnits: []
        ) == nil)

        let first = CategoryCelebration.offer(
            finishing: lessonID("l-introductions-3"),
            in: units,
            finishedBefore: finished,
            celebratedUnits: []
        )
        #expect(first == CategoryCelebrationOffer(
            unitID: unitID("u-introductions"),
            unitName: "Introduction",
            ringFrom: 2.0 / 3.0,
            ringTo: 1
        ))

        #expect(CategoryCelebration.offer(
            finishing: lessonID("l-introductions-3"),
            in: units,
            finishedBefore: finished.union([lessonID("l-introductions-3")]),
            celebratedUnits: []
        ) == nil)
        #expect(CategoryCelebration.offer(
            finishing: lessonID("l-introductions-3"),
            in: units,
            finishedBefore: finished,
            celebratedUnits: [unitID("u-introductions")]
        ) == nil)

        let other = CategoryCelebration.offer(
            finishing: lessonID("l-family-3"),
            in: units,
            finishedBefore: [],
            celebratedUnits: [unitID("u-introductions")]
        )
        #expect(other?.unitID == unitID("u-family"))
        #expect(other?.unitName == "Family")
        #expect(other?.ringFrom == 0)
        #expect(other?.ringTo == 1.0 / 3.0)
    }

    @Test func aUnitWithoutAMenuLabelUsesItsTitle() {
        let custom = unit("u-custom", title: "Around town", lessons: [
            ("l-custom-1", .practice),
        ])
        let offer = CategoryCelebration.offer(
            finishing: lessonID("l-custom-1"),
            in: [custom],
            finishedBefore: [],
            celebratedUnits: []
        )
        #expect(offer?.unitName == "Around town")
        #expect(offer?.ringFrom == 0)
        #expect(offer?.ringTo == 1)
    }

    @Test func reduceMotionOpensOnTheSettledFrame() {
        #expect(CategoryCelebrationPlayback.ringFill == 0.4)
        #expect(CategoryCelebrationPlayback.unfold == 0.5)
        #expect(CategoryCelebrationPlayback.opening(reduceMotion: false) == .ring)
        #expect(CategoryCelebrationPlayback.opening(reduceMotion: true) == .praise)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: true, elapsed: 0) == .praise)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: true, elapsed: 2) == .praise)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: false, elapsed: 0) == .ring)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: false, elapsed: 0.39) == .ring)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: false, elapsed: 0.4) == .unfold)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: false, elapsed: 0.89) == .unfold)
        #expect(CategoryCelebrationPlayback.phase(reduceMotion: false, elapsed: 0.9) == .praise)
    }

    @Test func theStarHasSixteenPointsAndUnfoldsFromACircle() {
        #expect(CategoryCelebrationStar.pointCount == 16)
        #expect(CategoryCelebrationStar.layers.map(\.outer) == [104, 80, 42])
        #expect(CategoryCelebrationStar.layers.map(\.inner) == [72, 56, 30])
        let star = CategoryCelebrationStar.points(outer: 104, inner: 72, morph: 1)
        #expect(star.count == 16)
        #expect(abs(star[0].x) < 0.001)
        #expect(abs(star[0].y + 104) < 0.001)
        #expect(abs(distance(star[1]) - 72) < 0.001)
        let circle = CategoryCelebrationStar.points(outer: 104, inner: 72, morph: 0)
        let radius = distance(circle[0])
        #expect(circle.allSatisfy { abs(distance($0) - radius) < 0.001 })
    }

    @Test func theCelebrationRecordRoundTripsAndDropsABadFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("celebration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("progress.store")
        #expect(CategoryCelebrationStore.load(beside: store).isEmpty)

        let ids: Set<UnitID> = [unitID("u-family"), unitID("u-greetings")]
        try CategoryCelebrationStore.save(ids, beside: store)
        #expect(CategoryCelebrationStore.load(beside: store) == ids)

        let file = CategoryCelebrationStore.fileURL(beside: store)
        let saved = try JSONDecoder().decode(StoredIDs.self, from: Data(contentsOf: file))
        #expect(saved.unitIDs == ["u-family", "u-greetings"])

        try Data("[]".utf8).write(to: file)
        #expect(CategoryCelebrationStore.load(beside: store).isEmpty)

        try Data(#"{"unitIDs":["u-family","not-an-id"]}"#.utf8).write(to: file)
        #expect(CategoryCelebrationStore.load(beside: store) == [unitID("u-family")])

        CategoryCelebrationStore.reset(beside: store)
        #expect(CategoryCelebrationStore.load(beside: store).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theScreenPlaysTheClipOnlyFromTheButtonAndSkipsMotionWhenAsked() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("PashtoApp/ContentView.swift"),
            encoding: .utf8
        )
        let lower = try #require(source.range(of: "struct CategoryCelebrationScreen"))
        let upper = try #require(source.range(of: "\n#Preview", range: lower.upperBound..<source.endIndex))
        let screen = String(source[lower.lowerBound..<upper.lowerBound])
        #expect(screen.contains("CategoryCelebration.praise"))
        #expect(screen.contains(#"replacingOccurrences(of: "-", with: "\u{2011}")"#))
        #expect(screen.contains("accessibilityLabel(Text(verbatim: CategoryCelebration.praise.pronunciation))"))
        #expect(screen.contains("GreetingsAudio.url(for: CategoryCelebration.praiseItemID"))
        #expect(screen.contains("accessibilityLabel(Text(verbatim: \"Play\"))"))
        #expect(screen.components(separatedBy: "clipPlayer.play").count == 2)
        #expect(screen.contains("CategoryCelebrationPlayback.opening"))
        #expect(screen.contains("reduceMotion"))
        #expect(screen.contains("quiz.continue.button"))
        #expect(screen.contains("offer.unitName"))
        #expect(!screen.contains("textCase"))
        #expect(!screen.contains(".uppercased()"))
        #expect(!screen.contains(".translit"))
        #expect(!screen.contains("Lesson complete"))
        #expect(!screen.contains("Ringen"))
        #expect(!screen.contains("Mørk"))
        #expect(!screen.contains("stjerne"))
    }

    private func distance(_ vertex: CategoryCelebrationStar.Vertex) -> Double {
        (vertex.x * vertex.x + vertex.y * vertex.y).squareRoot()
    }

    private func unit(_ id: String, title: String, lessons: [(String, LessonKind)]) -> CourseUnit {
        CourseUnit(
            id: unitID(id),
            track: "main",
            title: title,
            lessons: lessons.map { lesson in
                Lesson(id: lessonID(lesson.0), title: lesson.0, items: [], kind: lesson.1)
            }
        )
    }

    private func unitID(_ raw: String) -> UnitID {
        UnitID(rawValue: raw)!
    }

    private func lessonID(_ raw: String) -> LessonID {
        LessonID(rawValue: raw)!
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct StoredIDs: Codable {
    var unitIDs: [String]
}
