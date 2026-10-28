import Foundation
import PashtoCore

struct ContentRoot {
    var url: URL

    var contentDirectory: URL { url.appendingPathComponent("content") }
    var courseFile: URL { contentDirectory.appendingPathComponent("course.json") }
    var unitsDirectory: URL { contentDirectory.appendingPathComponent("units") }
    var difficultCharactersFile: URL { contentDirectory.appendingPathComponent("difficult-characters.json") }
    var releaseUnitsFile: URL { contentDirectory.appendingPathComponent("release-units.json") }
    var registryFile: URL { contentDirectory.appendingPathComponent("id-registry.json") }
    var bundleFile: URL { contentDirectory.appendingPathComponent("content.json") }

    func unitFile(named name: String) -> URL {
        unitsDirectory.appendingPathComponent("\(name).json")
    }

    func relative(_ url: URL) -> String {
        let root = self.url.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }
}

struct CourseFile: Decodable {
    let units: [String]
    let nonDistractorGroups: [[String]]
    let note: String?
}

struct ReleaseUnitsFile: Decodable {
    let units: [String]
    let note: String?
}

struct RegistryFile: Decodable {
    struct Entry: Decodable {
        let id: String
        let retired: Bool?
    }

    let entries: [Entry]
    let note: String?
}

struct UnitFile: Decodable {
    let id: String
    let track: String
    let title: String
    let items: [ContentItem]
    let lessons: [Lesson]
}

enum SourceDecode {
    static func data(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    static func unknownKeys(in data: Data, allowed: Set<String>) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            return ["(not an object)"]
        }
        return dictionary.keys.filter { !allowed.contains($0) }.sorted()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
