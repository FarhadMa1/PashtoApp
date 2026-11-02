import SwiftUI

/// Shown when progress was written by a newer version of the app.
///
/// This screen never moves or deletes the store. Open App Store is hidden
/// while `AppStoreID` in Info.plist is empty.
struct UpdateNeededScreen: View {
    var showsAppStoreButton: Bool
    var openAppStore: () -> Void

    var body: some View {
        LapisScreen {
            VStack(spacing: 0) {
                OctagramBadge(fill: Lapis.badge) {
                    UpArrowMark()
                        .stroke(
                            Lapis.badgeInk,
                            style: StrokeStyle(lineWidth: 2.2 * 52 / 24, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 52, height: 52)
                }
                .padding(.top, 24)
                Text("updateNeeded.title")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Lapis.text)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)
                Text("updateNeeded.body")
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
            if showsAppStoreButton {
                Button(action: openAppStore) {
                    Text("updateNeeded.openAppStore.button")
                }
                .buttonStyle(SaffronButtonStyle())
            }
        }
    }
}

#Preview("Update needed") {
    UpdateNeededScreen(showsAppStoreButton: true, openAppStore: {})
}

#Preview("Update needed, no listing") {
    UpdateNeededScreen(showsAppStoreButton: false, openAppStore: {})
}

#Preview("Update needed, dark") {
    UpdateNeededScreen(showsAppStoreButton: true, openAppStore: {})
        .preferredColorScheme(.dark)
}
