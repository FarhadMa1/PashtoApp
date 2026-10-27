import Foundation
import Testing

/// Same rules as `scripts/linux-guard.sh`. Keep the two patterns together.
struct LinuxGuardTests {
    @Test func patternsMatchTheBannedCallsOnly() {
        #expect(matches(in: "import Foundation\n").isEmpty)
        #expect(matches(in: "import SwiftUI\n") == ["import SwiftUI"])
        #expect(matches(in: "import SwiftData\n") == ["import SwiftData"])
        #expect(matches(in: "import UIKit\n") == ["import UIKit"])
        #expect(matches(in: "let now = Date()\n") == ["Date()"])
        #expect(matches(in: "let formatter = DateFormatter()\n").isEmpty)
        #expect(matches(in: "Calendar.current\n") == ["Calendar.current"])
        #expect(matches(in: "Calendar(identifier: .gregorian)\n").isEmpty)
        #expect(matches(in: "TimeZone.current\n") == ["TimeZone.current"])
        #expect(matches(in: "TimeZone(identifier: \"Asia/Kabul\")\n").isEmpty)
        #expect(matches(in: "Locale.current\n") == ["Locale.current"])
        #expect(matches(in: "Locale(identifier: \"en_US_POSIX\")\n").isEmpty)
        #expect(matches(in: "text.lowercased(with: nil)\n").isEmpty)
    }

    @Test func pashtoCoreSourcesStayFreeOfAppleOnlyAPIs() throws {
        let root = try packageRoot()
        let files = try swiftSources(under: root)
        #expect(!files.isEmpty)

        var violations: [String] = []
        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let hits = matches(in: String(line))
                for hit in hits {
                    violations.append("\(relative):\(index + 1): \(hit)")
                }
            }
        }
        #expect(violations.isEmpty, "Linux guard failed:\n\(violations.joined(separator: "\n"))")
    }

    private func matches(in source: String) -> [String] {
        let pattern = /import\s+UIKit\b|import\s+SwiftUI\b|import\s+SwiftData\b|\bDate\(\)|\bCalendar\.current\b|\bTimeZone\.current\b|\bLocale\.current\b/
        return source.matches(of: pattern).map { String($0.output) }
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while url.path != "/" {
            if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        Issue.record("PashtoCore package root not found from \(#filePath)")
        throw CancellationError()
    }

    private func swiftSources(under root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == "Tests" || name == ".build" {
                enumerator.skipDescendants()
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
