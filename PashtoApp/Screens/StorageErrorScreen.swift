import PashtoCore
import SwiftUI

/// Shown when the progress store cannot be opened for a reason other than a newer version.
///
/// Try again opens the same file. Start over asks first, then the caller moves
/// that file aside. Pass no start-over action to hide that button, which is
/// what a missing course does. This view does not touch the file itself.
///
/// `missingCourseAttempts` counts Try again while the course is still missing.
/// The error content shakes, and plays an error haptic. Reduce Motion fades
/// it instead. The existing body is announced again when that string is in
/// the catalog.
struct StorageErrorScreen: View {
    var tryAgain: () -> Void
    var startOver: (() -> Void)?
    var missingCourseAttempts = 0
    /// True while Try again is still working. The buttons stay disabled and the progress indicator is shown.
    var isBusy = false
    @State private var confirmingStartOver = false

    var body: some View {
        LapisScreen {
            VStack(spacing: 0) {
                OctagramBadge(fill: Lapis.saffron) {
                    ExclamationMark()
                }
                .padding(.top, 24)
                Text("storageError.title")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Lapis.text)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)
                Text("storageError.body")
                    .font(.body)
                    .foregroundStyle(Lapis.secondaryText)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .modifier(MissingCourseFeedback(attempts: missingCourseAttempts))
        } footer: {
            VStack(spacing: 8) {
                Button(action: tryAgain) {
                    HStack(spacing: 10) {
                        if isBusy {
                            ProgressView()
                                .tint(Lapis.saffronInk)
                                .accessibilityHidden(true)
                        }
                        Text("storageError.tryAgain.button")
                    }
                }
                .buttonStyle(SaffronButtonStyle())
                .disabled(isBusy)
                if startOver != nil {
                    Button("storageError.startOver.button", role: .destructive, action: { confirmingStartOver = true })
                        .buttonStyle(.plain)
                        .font(.body.weight(.bold))
                        .foregroundStyle(Lapis.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .disabled(isBusy)
                }
            }
        }
        .alert("storageError.startOver.confirmTitle", isPresented: $confirmingStartOver) {
            Button("storageError.startOver.button", role: .destructive, action: { startOver?() })
            Button("storageError.startOver.cancel", role: .cancel) {}
        } message: {
            Text("storageError.startOver.confirmMessage")
        }
    }
}

/// Shake, or a short fade when Reduce Motion is on, after Try again still has no course.
private struct MissingCourseFeedback: ViewModifier {
    var attempts: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ShakeMotion(token: reduceMotion ? 0 : attempts))
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? attempts : 0) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.45, duration: QuizMotion.reduceMotionFade)
                    LinearKeyframe(1.0, duration: QuizMotion.reduceMotionFade)
                }
            }
            .sensoryFeedback(.error, trigger: attempts)
            .onChange(of: attempts) { _, attempts in
                guard attempts > 0 else { return }
                announceExistingStorageError()
            }
    }

    /// The catalog body, posted only when that string is present.
    private func announceExistingStorageError() {
        let message = String(localized: "storageError.body")
        guard message != "storageError.body" else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

#Preview("Storage error") {
    StorageErrorScreen(tryAgain: {}, startOver: {})
}

#Preview("Storage error, dark") {
    StorageErrorScreen(tryAgain: {}, startOver: {})
        .preferredColorScheme(.dark)
}
