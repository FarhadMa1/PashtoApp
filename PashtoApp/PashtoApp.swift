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
    /// and `-PashtoScreenshotXL`. A normal launch has none of them, and the
    /// root is the same view the learner gets.
    @ViewBuilder
    private var screenshotConfiguredRoot: some View {
        let arguments = ProcessInfo.processInfo.arguments
        let dark = arguments.contains("-PashtoScreenshotDark")
        let light = arguments.contains("-PashtoScreenshotLight")
        let extraLarge = arguments.contains("-PashtoScreenshotXL")
        if dark && extraLarge {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .dynamicTypeSize(.accessibility5)
        } else if dark {
            RootView(model: model)
                .preferredColorScheme(.dark)
        } else if light && extraLarge {
            RootView(model: model)
                .preferredColorScheme(.light)
                .dynamicTypeSize(.accessibility5)
        } else if light {
            RootView(model: model)
                .preferredColorScheme(.light)
        } else if extraLarge {
            RootView(model: model)
                .dynamicTypeSize(.accessibility5)
        } else {
            RootView(model: model)
        }
    }
}
