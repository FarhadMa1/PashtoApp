import Foundation

/// The App Store id to show a button for, or nil while there is nothing to open.
///
/// The id is a configuration value. An empty value, whitespace, and anything
/// that is not a decimal id all mean the app is not listed yet. This function
/// does not build a store URL.
public func appStoreIDForListing(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
        return nil
    }
    return trimmed
}

/// Whether Update needed shows Open App Store.
///
/// Hidden while `appStoreIDForListing` is nil.
public func showsAppStoreButton(appStoreID: String) -> Bool {
    appStoreIDForListing(appStoreID) != nil
}
