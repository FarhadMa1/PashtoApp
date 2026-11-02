import SwiftUI

/// Shown when a break was longer than the freezes the learner still holds.
///
/// There is no streak count and no "streak lost" line. Start review begins
/// the capped daily queue. Freezes are not spent on this screen.
struct WelcomeBackScreen: View {
    var startReview: () -> Void

    var body: some View {
        LapisScreen {
            VStack(spacing: 0) {
                WelcomeHero()
                    .padding(.top, 8)
                Text("welcomeBack.title")
                    .font(.title.weight(.heavy))
                    .foregroundStyle(Lapis.text)
                    .padding(.top, 30)
                    .accessibilityAddTraits(.isHeader)
                Text("welcomeBack.body")
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
        } footer: {
            Button(action: startReview) {
                Text("welcomeBack.startReview.button")
            }
            .buttonStyle(SaffronButtonStyle())
        }
    }
}

#Preview("Welcome back") {
    WelcomeBackScreen(startReview: {})
}

#Preview("Welcome back, dark") {
    WelcomeBackScreen(startReview: {})
        .preferredColorScheme(.dark)
}
