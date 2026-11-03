import SwiftUI

/// Chooses the progress screen. The ordinary app is the existing root.
struct RootView: View {
    @Bindable var model: AppModel
    /// SwiftUI's equivalent of `UIAccessibility.voiceOverStatusDidChangeNotification`.
    /// It changes when VoiceOver turns on or off.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        phaseContent
            .onChange(of: voiceOverEnabled, initial: true) { _, enabled in
                model.voiceOverChanged(to: enabled)
            }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .loading:
            Lapis.background.ignoresSafeArea()
        case .updateNeeded:
            UpdateNeededScreen(showsAppStoreButton: model.isAppStoreButtonVisible) {
                model.openAppStore()
            }
        case .storageError:
            StorageErrorScreen(
                tryAgain: { Task { await model.tryAgain() } },
                startOver: { Task { await model.confirmStartOver() } }
            )
        case .welcomeBack:
            WelcomeBackScreen {
                model.startReview()
            }
        case .ready:
            ContentView(
                reviewStarted: model.isReviewing,
                quiz: model.activeLesson,
                quizItems: model.lessonItems,
                lessons: model.releasedLessons,
                startLesson: { model.startLesson($0) },
                endSession: { model.endLesson() }
            )
        }
    }
}
