import SwiftUI

/// Placeholder root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. The review quiz
/// itself is a later screen. This view does not add copy for it.
struct ContentView: View {
    var reviewStarted: Bool = false

    var body: some View {
        Text("Pashto")
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Lapis.background.ignoresSafeArea())
            .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
    }
}

#Preview {
    ContentView()
}
