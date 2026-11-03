import PashtoCore
import SwiftUI

/// Root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. A lesson quiz
/// is shown when the caller has already built one. The session carries the
/// pronunciation setting it started with. Units that are not in
/// `release-units.json` are not part of that session. Tapping a released
/// lesson starts one. Finishing it, or leaving it, returns here. An empty
/// release list keeps the placeholder.
struct ContentView: View {
    var reviewStarted: Bool = false
    var quiz: LessonSession?
    var quizItems: [ContentItem] = []
    /// Lessons from the release list. Empty keeps the placeholder below.
    var lessons: [ReleasedLesson] = []
    var startLesson: (LessonID) -> Void = { _ in }
    var endSession: () -> Void = {}

    var body: some View {
        if let quiz, !quiz.tasks.isEmpty {
            quizSession(quiz)
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else if lessons.isEmpty {
            Text("Pashto")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Lapis.background.ignoresSafeArea())
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else {
            lessonList
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        }
    }

    private func quizSession(_ quiz: LessonSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: endSession) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward")
                        Text("Pashto")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            QuizScreen(session: quiz, items: quizItems, onFinish: endSession)
        }
        .background(Lapis.background.ignoresSafeArea())
    }

    private var lessonList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pashto")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                ForEach(lessons) { lesson in
                    Button {
                        startLesson(lesson.id)
                    } label: {
                        Text(verbatim: lesson.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Lapis.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Lapis.secondaryText.opacity(0.35), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(lesson.id.rawValue)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
