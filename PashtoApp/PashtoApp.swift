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
        let themed = screenshotTheme(
            content.modifier(ProfileChrome()),
            dark: dark,
            light: light,
            extraLarge: extraLarge
        )
        if bold {
            themed.environment(\.legibilityWeight, .bold)
        } else {
            themed
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

/// Applies Profile appearance and the text-size offset.
///
/// System appearance leaves the surrounding scheme alone, so screenshot runs
/// still choose light or dark. The offset starts from that surrounding text
/// size and never replaces it with a fixed size.
private struct ProfileChrome: ViewModifier {
    @AppStorage(ProfileSettingsStore.appearanceKey) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(ProfileSettingsStore.textSizeOffsetKey) private var textSizeOffset = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let step = TextSizeOffset.shifted(TextSizeStep(dynamicTypeSize), by: textSizeOffset)
        content
            .dynamicTypeSize(step.dynamicTypeSize)
            .modifier(AppearanceScheme(choice: AppearanceChoice.resolved(appearanceRaw)))
    }
}

private struct AppearanceScheme: ViewModifier {
    var choice: AppearanceChoice

    @ViewBuilder
    func body(content: Content) -> some View {
        switch choice {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }
}

extension TextSizeStep {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .xSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .xLarge
        case .xxLarge: self = .xxLarge
        case .xxxLarge: self = .xxxLarge
        case .accessibility1: self = .accessibility1
        case .accessibility2: self = .accessibility2
        case .accessibility3: self = .accessibility3
        case .accessibility4: self = .accessibility4
        case .accessibility5: self = .accessibility5
        @unknown default: self = .large
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        case .accessibility1: .accessibility1
        case .accessibility2: .accessibility2
        case .accessibility3: .accessibility3
        case .accessibility4: .accessibility4
        case .accessibility5: .accessibility5
        }
    }
}
