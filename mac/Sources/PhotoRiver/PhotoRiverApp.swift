import AppKit
import SwiftUI

@main
struct PhotoRiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let river = River()   // one window, one river; held here because @State needs Xcode's macro plugin

    var body: some Scene {
        Window("Photo River", id: "river") {
            RootView(river: river)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // also when run as a bare binary outside the .app bundle
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct RootView: View {
    let river: River

    var body: some View {
        ZStack {
            RiverViewRepresentable(river: river)
            Overlay(river: river)
        }
        .ignoresSafeArea()
        .background(Color(red: 2 / 255, green: 4 / 255, blue: 10 / 255))
        .onAppear { river.start() }
    }
}
