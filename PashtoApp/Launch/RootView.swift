import SwiftUI

/// Chooses the progress screen. The ordinary app is the existing root.
struct RootView: View {
    @Bindable var model: AppModel
    /// SwiftUI's equivalent of `UIAccessibility.voiceOverStatusDidChangeNotification`.
    /// It changes when VoiceOver turns on or off.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        phaseContent
            .onChange(of: voiceOverEnabled, initial: true) { _, enabled in
                model.voiceOverChanged(to: enabled)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.saveLessonOnBackground()
                }
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
                startOver: model.offersStartOver
                    ? { Task { await model.confirmStartOver() } }
                    : nil,
                missingCourseAttempts: model.courseStillMissingToken,
                isBusy: model.isRetrying
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
                streakCount: model.streakCount,
                goalDone: model.goalDone,
                goalTotal: model.goalTotal,
                finishedLessonIDs: model.finishedLessonIDs,
                pendingHomeMotion: model.pendingHomeMotion,
                consumeHomeMotion: { model.consumePendingHomeMotion() },
                pendingStreakEvents: model.pendingStreakEvents,
                claimStreakEvents: { model.claimStreakEvents($0) },
                startLesson: { lesson in
                    Task { await model.startLesson(lesson, voiceOver: voiceOverEnabled) }
                },
                endSession: { model.endLesson() },
                answerSession: { model.saveAnswer($0) },
                finishSession: { model.finishLesson($0) }
            )
        }
    }
}
