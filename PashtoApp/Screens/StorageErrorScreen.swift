import SwiftUI

/// Shown when the progress store cannot be opened for a reason other than a newer version.
///
/// Try again opens the same file. Start over asks first, then the caller moves
/// that file aside. This view does not touch the file itself.
struct StorageErrorScreen: View {
    var tryAgain: () -> Void
    var startOver: () -> Void
    @State private var confirmingStartOver = false

    var body: some View {
        LapisScreen {
            VStack(spacing: 0) {
                OctagramBadge(fill: Lapis.saffron) {
                    ExclamationMark()
                }
                .padding(.top, 24)
                Text("We couldn't open your progress")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Lapis.text)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)
                Text("Something went wrong while loading. Try again first.")
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
            VStack(spacing: 8) {
                Button(action: tryAgain) {
                    Text("Try again")
                }
                .buttonStyle(SaffronButtonStyle())
                Button("Start over", role: .destructive, action: { confirmingStartOver = true })
                    .buttonStyle(.plain)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Lapis.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .alert("Start over?", isPresented: $confirmingStartOver) {
            Button("Start over", role: .destructive, action: startOver)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your lessons, words and streak start from the beginning. Your settings stay the same.")
        }
    }
}

#Preview("Storage error") {
    StorageErrorScreen(tryAgain: {}, startOver: {})
}

#Preview("Storage error, dark") {
    StorageErrorScreen(tryAgain: {}, startOver: {})
        .preferredColorScheme(.dark)
}
