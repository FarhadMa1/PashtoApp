import PashtoCore
import SwiftUI

/// Root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. A lesson quiz
/// is shown when the caller has already built one. The session carries the
/// pronunciation setting it started with. Units that are not in
/// `release-units.json` are not part of that session.
struct ContentView: View {
    var reviewStarted: Bool = false
    var quiz: LessonSession?
    var quizItems: [ContentItem] = []

    var body: some View {
        if let quiz, !quiz.tasks.isEmpty {
            QuizScreen(session: quiz, items: quizItems)
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else {
            Text("Pashto")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Lapis.background.ignoresSafeArea())
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        }
    }
}

#Preview {
    ContentView()
}
