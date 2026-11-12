import SwiftUI
import PashtoCore

@main
struct PashtoApp: App {
    @State private var model: AppModel

    init() {
        // Keeps the PashtoCore product linked. Not product behavior.
        _ = PashtoCore.moduleName
        _model = State(initialValue: AppModel.live())
    }

    var body: some Scene {
        WindowGroup {
            screenshotConfiguredRoot
                .task { await model.loadProgress() }
        }
    }

    /// Screenshot CI passes `-PashtoScreenshotLight`, `-PashtoScreenshotDark`,
    /// and `-PashtoScreenshotXL`. `-PashtoScreenshotCelebration` opens the
    /// settled celebration. `-PashtoScreenshotDailyWord` opens the daily word.
    /// `-PashtoScreenshotBoldText` turns on the Bold Text weight. A normal
    /// launch has none of them.
    @ViewBuilder
    private var screenshotConfiguredRoot: some View {
        configured(screenshotRoot)
    }

    @ViewBuilder
    private var screenshotRoot: some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PashtoScreenshotCelebration"),
           let offer = celebrationPreview {
            CategoryCelebrationScreen(offer: offer, startsSettled: true, onContinue: {})
        } else if arguments.contains("-PashtoScreenshotDailyWord") {
            DailyWordScreenshotScreen()
        } else {
            RootView(model: model)
        }
    }

    /// Introduction, the unit on the approved sketch. The word is the menu label.
    private var celebrationPreview: CategoryCelebrationOffer? {
        guard let id = UnitID(rawValue: "u-introductions") else { return nil }
        return CategoryCelebrationOffer(
            unitID: id,
            unitName: MainMenuLabels.word(for: id, title: "Introduction"),
            ringFrom: 2.0 / 3.0,
            ringTo: 1
        )
    }

    @ViewBuilder
    private func configured<Content: View>(_ content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        let dark = arguments.contains("-PashtoScreenshotDark")
        let light = arguments.contains("-PashtoScreenshotLight")
        let extraLarge = arguments.contains("-PashtoScreenshotXL")
        let bold = arguments.contains("-PashtoScreenshotBoldText")
        if bold {
            screenshotTheme(content, dark: dark, light: light, extraLarge: extraLarge)
                .environment(\.legibilityWeight, .bold)
        } else {
            screenshotTheme(content, dark: dark, light: light, extraLarge: extraLarge)
        }
    }

    @ViewBuilder
    private func screenshotTheme<Content: View>(
        _ content: Content,
        dark: Bool,
        light: Bool,
        extraLarge: Bool
    ) -> some View {
        if dark && extraLarge {
            content
                .preferredColorScheme(.dark)
                .dynamicTypeSize(.accessibility5)
        } else if dark {
            content
                .preferredColorScheme(.dark)
        } else if light && extraLarge {
            content
                .preferredColorScheme(.light)
                .dynamicTypeSize(.accessibility5)
        } else if light {
            content
                .preferredColorScheme(.light)
        } else if extraLarge {
            content
                .dynamicTypeSize(.accessibility5)
        } else {
            content
        }
    }
}
