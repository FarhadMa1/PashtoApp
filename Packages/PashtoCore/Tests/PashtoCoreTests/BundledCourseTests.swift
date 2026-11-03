import Foundation
import Testing
@testable import PashtoCore

struct BundledCourseTests {
    @Test func installedContentVersionIsTheVersionInContentJson() throws {
        let content = try Data(contentsOf: courseFile("content.json"))
        let release = try Data(contentsOf: courseFile("release-units.json"))
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("The bundled course did not decode")
            return
        }
        let decoded = try JSONDecoder().decode(ContentBundle.self, from: content)
        #expect(course.installedContentVersion == decoded.contentVersion)
        #expect(!course.installedContentVersion.isEmpty)
        #expect(course.installedContentVersion != "unbundled")
        #expect(loaded.blockingScreen == nil)
        #expect(course.releasedUnitIDs.isEmpty)
    }

    @Test func missingOrUndecodableFilesUseTheStorageError() throws {
        let content = try JSONEncoder().encode(sampleBundle())
        let release = Data(#"{"units":[],"note":"An empty list is allowed."}"#.utf8)
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("A decoded course should load")
            return
        }
        #expect(course.installedContentVersion == "test")
        #expect(loaded.blockingScreen == nil)

        let cases: [(Data?, Data?)] = [
            (nil, release),
            (content, nil),
            (nil, nil),
            (Data("[]".utf8), release),
            (Data(#"{"schemaVersion":99}"#.utf8), release),
            (content, Data("[]".utf8)),
            (content, Data(#"{"note":"no units key"}"#.utf8)),
            (content, Data(#"{"units":"u-sounds"}"#.utf8)),
        ]
        for pair in cases {
            let failed = BundledCourseLoader.load(content: pair.0, releaseUnits: pair.1)
            #expect(failed == .unavailable)
            #expect(failed.blockingScreen == .storageError)
        }
    }

    @Test func aDecodedReleaseListDropsIdsThatAreNotUnits() throws {
        let content = try JSONEncoder().encode(sampleBundle())
        let release = Data(#"{"units":["nope","u-sounds","also-bad"],"note":"authors","extra":true}"#.utf8)
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("A release list with a note should decode")
            return
        }
        #expect(course.releasedUnitIDs == [unitID("u-sounds")])
        #expect(loaded.blockingScreen == nil)
    }

    @Test func buildCheckFailsWhenACourseFileIsMissingFromTheApp() throws {
        let script = repositoryRoot().appendingPathComponent("scripts/verify-bundled-course.sh")
        let source = try String(contentsOf: script, encoding: .utf8)
        #expect(source.contains(BundledCourseLoader.contentFileName))
        #expect(source.contains(BundledCourseLoader.releaseUnitsFileName))
        #expect(source.contains("UNLOCALIZED_RESOURCES_FOLDER_PATH"))
        #expect(source.contains("course-files-check.stamp"))
        #expect(source.contains("error:"))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-bundle-check-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("PashtoApp.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bothMissing = try runBundleCheck(script: script, app: app)
        #expect(bothMissing.status != 0)
        #expect(bothMissing.output.contains("error: content.json is missing"))
        #expect(bothMissing.output.contains("error: release-units.json is missing"))
        #expect(!FileManager.default.fileExists(atPath: bothMissing.stamp.path))

        try Data("{}".utf8).write(to: app.appendingPathComponent("release-units.json"))
        let contentMissing = try runBundleCheck(script: script, app: app)
        #expect(contentMissing.status != 0)
        #expect(contentMissing.output.contains("error: content.json is missing"))
        #expect(!contentMissing.output.contains("release-units.json is missing"))
        #expect(!FileManager.default.fileExists(atPath: contentMissing.stamp.path))

        try Data("{}".utf8).write(to: app.appendingPathComponent("content.json"))
        let present = try runBundleCheck(script: script, app: app)
        #expect(present.status == 0)
        #expect(present.output.isEmpty)
        #expect(FileManager.default.fileExists(atPath: present.stamp.path))
    }
}

private func sampleBundle() -> ContentBundle {
    makeBundle(
        items: [makeItem()],
        units: [
            CourseUnit(
                id: unitID("u-sounds"),
                track: "main",
                title: "Sounds",
                lessons: [Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [])]
            ),
        ]
    )
}

private func courseFile(_ name: String) -> URL {
    repositoryRoot().appendingPathComponent("content").appendingPathComponent(name)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func runBundleCheck(script: URL, app: URL) throws -> (status: Int32, output: String, stamp: URL) {
    let derived = app.deletingLastPathComponent().appendingPathComponent("Derived", isDirectory: true)
    try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
    let stamp = derived.appendingPathComponent("course-files-check.stamp")
    if FileManager.default.fileExists(atPath: stamp.path) {
        try FileManager.default.removeItem(at: stamp)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path]
    var environment = ProcessInfo.processInfo.environment
    environment["TARGET_BUILD_DIR"] = app.deletingLastPathComponent().path
    environment["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = app.lastPathComponent
    environment["DERIVED_FILE_DIR"] = derived.path
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self), stamp)
}
