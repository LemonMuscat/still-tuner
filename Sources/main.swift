import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var model: TunerModel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = TunerModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("tuner")
        window.title = "Still — Guitar Tuner"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(calibratedRed: 0.085, green: 0.105, blue: 0.11, alpha: 1)
        window.contentView = NSHostingView(rootView: TunerView(model: model).padding(.top, 20).background(Color(red: 0.085, green: 0.105, blue: 0.11)))
        model.onLayoutChange = { [weak self] in self?.resizeForMode() }
        resizeForMode()
        window.center()
        window.setFrameAutosaveName("StillTunerWindow")
        resizeForMode()
        window.level = model.alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Still 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Still 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Still 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = self.window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
                NSApp.terminate(nil)
            }
        }
    }
    func resizeForMode() {
        let top = window.frame.maxY
        let size = model.compact ? NSSize(width: 380, height: 310) : NSSize(width: 440, height: 670)
        window.minSize = model.compact ? NSSize(width: 340, height: 310) : NSSize(width: 400, height: 670)
        window.setContentSize(size)
        var frame = window.frame
        frame.origin.y = top - frame.height
        if let screen = window.screen {
            let visible = screen.visibleFrame
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        window.setFrame(frame, display: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.suspend() }
}
if CommandLine.arguments.contains("--devices") {
    for device in inputDevices() { print("\(device.name) | \(device.channels) inputs | \(device.rate) Hz | \(device.uid)") }
    exit(0)
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
