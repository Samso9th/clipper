import SwiftUI

@main
struct ClipperApp: App {
    var body: some Scene {
        WindowGroup {
            StudioView()
                .frame(minWidth: 360, minHeight: 600)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 850)
        #endif
    }
}
