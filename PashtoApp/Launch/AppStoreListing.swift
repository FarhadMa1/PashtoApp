import Foundation
import PashtoCore

/// The App Store listing id, from Info.plist key `AppStoreID`.
///
/// The value is empty until the app is listed. No id and no store URL are
/// written in source. The Open App Store button stays hidden while the value
/// does not yield a decimal id.
enum AppStoreListing {
    static let infoDictionaryKey = "AppStoreID"

    static func identifier(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String ?? ""
    }

    /// A listing URL only when `appStoreID` is a decimal id. Otherwise nil.
    static func listingURL(appStoreID: String) -> URL? {
        guard let id = appStoreIDForListing(appStoreID) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}
