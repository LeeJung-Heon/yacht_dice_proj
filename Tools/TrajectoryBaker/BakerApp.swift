import SwiftUI
import AppKit

@main
struct BakerApp: App {
    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Trajectory Baker") {
            SpikeScene()
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}
