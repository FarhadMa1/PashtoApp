import Foundation

/// Bundled pronunciation clips for Greetings cards.
///
/// The file name is the item id plus `.m4a`. A missing file returns nil, so a
/// card with no clip draws no control. The app plays a returned URL only after
/// a tap.
public enum GreetingsAudio {
    /// Learn and phrases cards in this unit are the only place a clip is offered.
    public static let unitID = "u-greetings"

    /// The clip for `itemID` when that file is in `directory`. Otherwise nil.
    public static func url(for itemID: ItemID, in directory: URL) -> URL? {
        let url = directory
            .appendingPathComponent(itemID.rawValue)
            .appendingPathExtension("m4a")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return url
    }
}
