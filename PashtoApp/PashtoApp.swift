import SwiftUI
import PashtoCore

@main
struct PashtoApp: App {
    init() {
        // Keeps the PashtoCore product linked. Not product behavior.
        _ = PashtoCore.moduleName
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
