import Foundation

/// The course copied into the app, plus the units named in `release-units.json`.
public struct BundledCourse: Equatable, Sendable {
    public let bundle: ContentBundle
    public let releasedUnitIDs: [UnitID]

    public init(bundle: ContentBundle, releasedUnitIDs: [UnitID]) {
        self.bundle = bundle
        self.releasedUnitIDs = releasedUnitIDs
    }

    /// The version a new progress file stores.
    ///
    /// This is `bundle.contentVersion`, the `contentVersion` field of the
    /// course that decoded. `BundledCourse` is built only after that decode,
    /// so this property is always that version.
    public var installedContentVersion: String {
        bundle.contentVersion
    }
}

/// What reading the two bundled course files produced.
public enum BundledCourseLoad: Equatable, Sendable {
    /// Both files decoded. `releasedUnitIDs` may be empty: an empty release list is allowed.
    case ready(BundledCourse)
    /// `content.json` or `release-units.json` was missing, or either file did not decode.
    case unavailable

    /// The screen that blocks launch when the course cannot be read.
    ///
    /// The storage error is the existing screen for a file the app cannot
    /// open, so a missing course reuses that copy. A course that decoded
    /// does not block launch.
    public var blockingScreen: ProgressScreen? {
        switch self {
        case .unavailable:
            .storageError
        case .ready:
            nil
        }
    }
}

/// Decodes `content.json` and `release-units.json` from bytes the caller already read.
///
/// Nil data is a missing file. This type does not touch the bundle or the disk.
public enum BundledCourseLoader {
    public static let contentFileName = "content.json"
    public static let releaseUnitsFileName = "release-units.json"

    public static func load(content: Data?, releaseUnits: Data?) -> BundledCourseLoad {
        guard
            let content,
            let releaseUnits,
            let bundle = try? JSONDecoder().decode(ContentBundle.self, from: content),
            let list = try? JSONDecoder().decode(ReleaseUnitsFile.self, from: releaseUnits)
        else {
            return .unavailable
        }
        let unitIDs = list.units.compactMap(UnitID.init(rawValue:))
        return .ready(BundledCourse(bundle: bundle, releasedUnitIDs: unitIDs))
    }
}

/// `release-units.json`. A `note` and any other extra key are ignored.
/// The file the app ships uses `note` for authors and `units` for the list.
private struct ReleaseUnitsFile: Decodable {
    var units: [String]
}

/// One decode of the two bundled course files.
///
/// `replacing` returns this value when the bytes are unchanged, so the same
/// `content.json` is not decoded again. A failed decode has no version: that
/// is `installedContentVersion` here, which is nil, not a missing field on
/// `BundledCourse`.
public struct BundledCourseDecode: Equatable, Sendable {
    public let content: Data?
    public let releaseUnits: Data?
    public let load: BundledCourseLoad
    /// How many times a new pair of files has been decoded, including this value.
    public let decodeCount: Int

    public init(content: Data?, releaseUnits: Data?) {
        self.init(content: content, releaseUnits: releaseUnits, decodeCount: 1)
    }

    private init(content: Data?, releaseUnits: Data?, decodeCount: Int) {
        self.content = content
        self.releaseUnits = releaseUnits
        self.load = BundledCourseLoader.load(content: content, releaseUnits: releaseUnits)
        self.decodeCount = decodeCount
    }

    /// The version a new progress file stores, or nil when the course did not decode.
    public var installedContentVersion: String? {
        switch load {
        case .ready(let course):
            course.installedContentVersion
        case .unavailable:
            nil
        }
    }

    /// Decodes `content` and `releaseUnits` only when either value differs.
    public func replacing(content: Data?, releaseUnits: Data?) -> BundledCourseDecode {
        if content == self.content, releaseUnits == self.releaseUnits {
            return self
        }
        return BundledCourseDecode(
            content: content,
            releaseUnits: releaseUnits,
            decodeCount: decodeCount + 1
        )
    }
}
