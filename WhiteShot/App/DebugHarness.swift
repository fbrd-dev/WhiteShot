#if DEBUG
import AppKit
import ScreenCaptureKit
import Vision
import CoreText
import Darwin
import SwiftUI

/// Development aid, compiled into Debug builds only.
///
///     WhiteShot --debug-editor-shot out.png [--dark] [--tool rectangle] [--select text]
///
/// opens an editor window off-screen on synthetic content, renders it to a PNG and exits. It never
/// touches the screen contents, the real screenshots folder or the capture permission.
@MainActor
enum DebugHarness {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--debug-drag-test") {
            // An editor and a drop target, both WhiteShot's own windows, to drag between with a real mouse.
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await DragTest.run()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-textgrab") {
            // Runs the text-grab pipeline on the synthetic sample into a private pasteboard (never the real clipboard).
            NSApp.setActivationPolicy(.accessory)
            Preferences.register()
            Task { @MainActor in
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("me.fbrd.whiteshot.debug.grab"))
                var finished = false
                TextGrab.run(on: SampleScreenshot.make(width: 1280, height: 800), pasteboard: pasteboard) { string in
                    print("GRAB result: \(string.map { "\($0.split(separator: "\n").count) lines" } ?? "nothing")")
                    print("GRAB pasteboard: \((pasteboard.string(forType: .string) ?? "").replacingOccurrences(of: "\n", with: " | "))")
                    finished = true
                }
                for _ in 0..<160 where !finished { try? await Task.sleep(nanoseconds: 250_000_000) }
                if args.contains("--hud") {
                    if let window = GrabHUD.shared.windowForTesting { print("WINDOW \(window.windowNumber)"); fflush(stdout); try? await Task.sleep(nanoseconds: 6_000_000_000) }
                }
                pasteboard.releaseGlobally()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-qr") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runQR()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-diversity") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runDiversity()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-warmup") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runWarmUpLab()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-dense") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runDense()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-lab") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runLab()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-sizes") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.runSizes()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-ocr-timing") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await OCRTiming.run()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-pin") {
            // Pins a synthetic picture so the pin window can be looked at.
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                let image = SampleScreenshot.make(width: 560, height: 360)
                let pin = PinnedImageController.pin(image, scale: 2, name: "Sample", near: NSRect(x: 120, y: 260, width: 560, height: 360))
                if args.contains("--half") { pin.setOpacity(0.5) }
                guard let window = pin.window else { exit(1) }
                print("WINDOW \(window.windowNumber)")
                fflush(stdout)
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                exit(0)
            }
            return true
        }
        if args.contains("--debug-window-shadow-test") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await WindowShadowTest.run()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-relaunch-test") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                print("PID \(ProcessInfo.processInfo.processIdentifier)"); fflush(stdout)
                try? await Task.sleep(nanoseconds: 800_000_000)
                AppRestarter.relaunch()
            }
            return true
        }
        if args.contains("--debug-memory-test") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await runMemoryTest(withEdits: !args.contains("--plain"))
                exit(0)
            }
            return true
        }
        if args.contains("--debug-twowindows") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await runTwoWindows()
                exit(0)
            }
            return true
        }
        if args.contains("--debug-hotkey-test") {
            // Registers the shortcuts from the preferences and just prints which action fires. No overlay, no capture.
            NSApp.setActivationPolicy(.accessory)
            Preferences.register()
            ShortcutStore.migrateLegacyOverrides()
            HotKeyManager.shared.onAction = { print("FIRED \($0.rawValue)"); fflush(stdout) }
            HotKeyManager.shared.start()
            for action in HotkeyAction.allCases {
                for index in 0..<ShortcutStore.slotCount {
                    let slot = ShortcutSlot(action: action, index: index)
                    if let shortcut = ShortcutStore.shortcut(for: action, slot: index) {
                        print("SLOT \(action.rawValue).\(index) \(shortcut.displayString) registered=\(HotKeyManager.shared.isRegistered(slot))")
                    }
                }
            }
            print("READY"); fflush(stdout)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                exit(0)
            }
            return true
        }
        if args.contains("--debug-color-popover") {
            NSApp.setActivationPolicy(.accessory)
            if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            let kind = args.contains("--none") ? RGBAColor.clear : (args.contains("--half") ? RGBAColor.blue.with(alpha: 0.5) : RGBAColor.red)
            Task { @MainActor in
                await showColorPopover(color: kind)
                exit(0)
            }
            return true
        }
        if args.contains("--debug-settings-shot") {
            NSApp.setActivationPolicy(.accessory)
            if let i = args.firstIndex(of: "--tab"), i + 1 < args.count { UserDefaults.standard.set(args[i + 1], forKey: "settings.selectedTab") }
            Task { @MainActor in
                Preferences.register()
                SettingsWindowController.shared.show()
                guard let window = SettingsWindowController.shared.window else { exit(1) }
                window.setFrameOrigin(NSPoint(x: 80, y: 220))
                window.orderFrontRegardless()
                print("WINDOW \(window.windowNumber)")
                fflush(stdout)
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                exit(0)
            }
            return true
        }
        if args.contains("--debug-overlay-shot") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await renderOverlay(windowMode: args.contains("--window-mode"))
                exit(0)
            }
            return true
        }
        if args.contains("--debug-capture-selftest") {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                await CaptureSelfTest.run()
                exit(0)
            }
            return true
        }
        guard let flag = args.firstIndex(of: "--debug-editor-shot"), flag + 1 < args.count else { return false }
        let output = URL(fileURLWithPath: args[flag + 1])
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        NSApp.setActivationPolicy(.accessory)
        let tool = args.firstIndex(of: "--tool").flatMap { i in i + 1 < args.count ? EditorTool(rawValue: args[i + 1]) : nil }
        let selectKind = args.firstIndex(of: "--select").flatMap { i in i + 1 < args.count ? AnnotationKind(rawValue: args[i + 1]) : nil }
        let onScreen = args.contains("--onscreen")
        Task { @MainActor in
            await renderEditor(to: output, tool: tool, selectKind: selectKind, onScreen: onScreen)
            exit(0)
        }
        return true
    }

    /// The process's physical footprint in MB: the number Xcode's memory gauge shows.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// Opens and closes editor windows several times and prints the footprint at each stage, and whether the
    /// controller, model and window were actually freed. Only weak references are kept here, so nothing in
    /// this harness itself keeps a closed editor alive. `withEdits` adds annotations, a crop and a rotation,
    /// which leave full-size images in the undo history.
    private static func runMemoryTest(withEdits: Bool) async {
        func settle() async { try? await Task.sleep(nanoseconds: 900_000_000) }

        /// Creates an editor and returns only weak references to its parts.
        func openEditor() -> (EditorWindowController, EditorModel, NSWindow)? {
            let controller = EditorWindowController.present(CaptureResult(image: SampleScreenshot.make(width: 1280, height: 800), scale: 2), savedURL: nil)
            guard let window = controller.window else { return nil }
            window.setFrameOrigin(NSPoint(x: -6000, y: 200))
            let model = controller.model
            if withEdits {
                for (i, kind) in [AnnotationKind.rectangle, .obfuscate, .arrow, .step].enumerated() {
                    var a = model.makeAnnotation(kind)
                    a.rect = CGRect(x: 200 + 150 * i, y: 200, width: 300, height: 120)
                    if a.isLinear { a.start = CGPoint(x: 100, y: 100); a.end = CGPoint(x: 600, y: 400) }
                    model.add(a, select: false)
                }
                model.crop(to: CGRect(x: 40, y: 40, width: 2200, height: 1400))
                model.rotate(clockwise: true)
            }
            return (controller, model, window)
        }

        await settle()
        let baseline = footprintMB()
        print(String(format: "baseline (menu bar only)      %6.1f MB", baseline))
        for cycle in 1...5 {
            weak var weakController: EditorWindowController?
            weak var weakModel: EditorModel?
            weak var weakWindow: NSWindow?
            do {
                guard let parts = openEditor() else { return }
                weakController = parts.0; weakModel = parts.1; weakWindow = parts.2
            }
            await settle()
            let open = footprintMB()
            EditorWindowController.controllers.last?.window?.close()
            await settle()
            let closed = footprintMB()
            print(String(format: "cycle %d: open %6.1f MB   closed %6.1f MB (%+.1f vs baseline)   freed: controller=%@ model=%@ window=%@",
                         cycle, open, closed, closed - baseline,
                         weakController == nil ? "yes" : "NO", weakModel == nil ? "yes" : "NO", weakWindow == nil ? "yes" : "NO"))
            fflush(stdout)
        }
    }

    private final class PopoverSwitch: ObservableObject { @Published var on = false }

    private struct PopoverProbe: View {
        @ObservedObject var model: PopoverSwitch
        var body: some View {
            Color.clear
                .background(PopoverAnchor(isPresented: Binding(get: { model.on }, set: { model.on = $0 })) {
                    ColorEditorDemo(color: .red)
                })
        }
    }

    /// Two editor windows, a colour popover open in the front one, and a periodic log of window order
    /// and popover state, so a real click on the other window can be judged from outside.
    private static func runTwoWindows() async {
        let settingsAsB = CommandLine.arguments.contains("--settings-as-b")
        // With --settings-as-b the second window is the Settings window instead of another editor.
        var b: EditorWindowController?
        if settingsAsB {
            Preferences.register()
            SettingsWindowController.shared.show()
        } else {
            b = EditorWindowController.present(CaptureResult(image: SampleScreenshot.make(width: 900, height: 560), scale: 2), savedURL: nil)
        }
        let a = EditorWindowController.present(CaptureResult(image: SampleScreenshot.make(width: 900, height: 560), scale: 2), savedURL: nil)
        guard let windowA = a.window, let windowB = settingsAsB ? SettingsWindowController.shared.window : b?.window else { return }
        // B at the left, A overlapping its right part and in front.
        if settingsAsB {
            windowB.setFrameOrigin(NSPoint(x: 60, y: 200))
        } else {
            windowB.setFrame(NSRect(x: 60, y: 200, width: 700, height: 520), display: true)
            windowB.title = "WINDOW-B"
        }
        windowA.setFrame(NSRect(x: 460, y: 260, width: 700, height: 520), display: true)
        windowA.title = "WINDOW-A"
        windowB.orderFrontRegardless()
        windowA.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 600_000_000)

        let model = PopoverSwitch()
        let host = NSHostingView(rootView: PopoverProbe(model: model))
        host.frame = NSRect(x: 120, y: 120, width: 60, height: 24)
        windowA.contentView?.addSubview(host)
        windowA.contentView?.layoutSubtreeIfNeeded()
        // The anchor view must already be in the window when the flag flips, or nothing is shown.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if !CommandLine.arguments.contains("--no-popover") { model.on = true }
        try? await Task.sleep(nanoseconds: 700_000_000)
        // Timeline of everything that could explain a window coming forward (timestamps in ms since start).
        let t0 = Date()
        func stamp() -> String { String(format: "T+%05d", Int(Date().timeIntervalSince(t0) * 1000)) }
        func name(_ w: NSWindow?) -> String { w === windowA ? "A" : (w === windowB ? "B" : (w == nil ? "-" : "other:\(type(of: w!))")) }
        for (label, notification) in [("KEY", NSWindow.didBecomeKeyNotification), ("RESIGN-KEY", NSWindow.didResignKeyNotification),
                                      ("MAIN", NSWindow.didBecomeMainNotification), ("RESIGN-MAIN", NSWindow.didResignMainNotification)] {
            NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { note in
                print("\(stamp()) \(label) \(name(note.object as? NSWindow))"); fflush(stdout)
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            print("\(stamp()) \(event.type == .leftMouseDown ? "MOUSE-DOWN" : "MOUSE-UP") on \(name(event.window))"); fflush(stdout)
            return event
        }
        var lastOrder = ""
        Task { @MainActor in
            while true {
                let order = NSApp.orderedWindows.compactMap { $0 === windowA ? "A" : ($0 === windowB ? "B" : nil) }.joined()
                if order != lastOrder { print("\(stamp()) ORDER \(order)  (key=\(name(NSApp.keyWindow)) main=\(name(NSApp.mainWindow)))"); fflush(stdout); lastOrder = order }
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
        }
        print("READY A=\(windowA.windowNumber) B=\(windowB.windowNumber)")
        fflush(stdout)
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let order = NSApp.orderedWindows.compactMap { $0 === windowA ? "A" : ($0 === windowB ? "B" : nil) }.joined()
            let popovers = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }.count
            print("STATE active=\(NSApp.isActive) key=\(NSApp.keyWindow?.title ?? "-") front-to-back=\(order) popover=\(popovers)")
            fflush(stdout)
        }
    }

    private struct ColorEditorDemo: View {
        @State var color: RGBAColor
        var body: some View { ColorEditor(title: "Border Color", color: $color, allowsNone: true) }
    }

    /// Shows the colour editor popover beside an editor window, for a screenshot.
    private static func showColorPopover(color: RGBAColor) async {
        let sample = SampleScreenshot.make(width: 900, height: 560)
        let controller = EditorWindowController.present(CaptureResult(image: sample, scale: 2), savedURL: nil)
        guard let window = controller.window, let content = window.contentView else { return }
        window.setFrame(NSRect(x: 60, y: 200, width: 1100, height: 780), display: true)
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 600_000_000)
        let host = NSHostingController(rootView: ColorEditorDemo(color: color))
        host.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = host
        popover.show(relativeTo: NSRect(x: content.bounds.midX, y: content.bounds.maxY - 50, width: 24, height: 24), of: content, preferredEdge: .minY)
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let popoverWindow = host.view.window else { return }
        print("WINDOW \(popoverWindow.windowNumber)")
        fflush(stdout)
        try? await Task.sleep(nanoseconds: 9_000_000_000)
    }

    /// Shows the region-selection overlay over synthetic content, in a small window, mid-drag.
    private static func renderOverlay(windowMode: Bool) async {
        guard let screen = NSScreen.main else { return }
        let sample = SampleScreenshot.make(width: 1000, height: 650)
        let frozen = FrozenDisplay(screen: screen, displayID: 0, image: sample, scale: 2)
        let frame = NSRect(x: 60, y: 200, width: 1000, height: 650)
        let controller = CaptureOverlayController(frozen: [frozen], mode: windowMode ? .window : .region, windows: [], showLoupe: true, frame: frame)
        controller.begin { _ in }
        guard let window = controller.overlayWindows.first, let view = controller.views.first else { return }
        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        if !windowMode {
            // The drag ends on text, so the magnifier has something to show.
            view.mouseMoved(with: event(.mouseMoved, CGPoint(x: 240, y: 600)))
            view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 240, y: 600)))
            view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 330, y: 500)))
            view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 404, y: 421)))
        }
        print("WINDOW \(window.windowNumber)")
        fflush(stdout)
        try? await Task.sleep(nanoseconds: 9_000_000_000)
    }

    private static func renderEditor(to url: URL, tool: EditorTool?, selectKind: AnnotationKind?, onScreen: Bool) async {
        // `--small` mimics a small region capture: the editor then opens at its smallest natural size.
        let small = CommandLine.arguments.contains("--small")
        let sample = small ? SampleScreenshot.make(width: 360, height: 220) : SampleScreenshot.make(width: 1280, height: 800)
        let controller = EditorWindowController.present(CaptureResult(image: sample, scale: 2), savedURL: nil)
        let model = controller.model
        if !CommandLine.arguments.contains("--ocr-demo") { SampleScreenshot.annotate(model) }
        if let kind = selectKind, let match = model.annotations.first(where: { $0.kind == kind }) { model.selection = [match.id]; model.refresh() }
        // `--docs`: a plain file name in the title bar, for the pictures on the project page.
        if CommandLine.arguments.contains("--docs") { model.displayName = "Invoice 2026-0142"; model.refresh() }
        if CommandLine.arguments.contains("--edit-text") { controller.debugBeginTextEditing(of: .text) }
        if let tool {
            controller.selectTool(tool)
            if tool == .crop { model.cropRect = CGRect(x: 300, y: 260, width: 1700, height: 1000); model.refresh() }
        }
        guard let window = controller.window else { return }
        // `--settle`: let the window show at its natural size first, as a real window does, before it is resized below.
        if CommandLine.arguments.contains("--settle") { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        if CommandLine.arguments.contains("--ocr") {
            // Text recognition on the synthetic sample: prints what Vision found, optionally with a selection.
            controller.toggleTextRecognition(nil)
            for _ in 0..<80 where model.textMode == .recognizing { try? await Task.sleep(nanoseconds: 250_000_000) }
            let lines = model.recognizedText?.lines ?? []
            print("OCR mode=\(model.textMode) tool=\(model.tool.rawValue) lines=\(lines.count) codes=\(model.recognizedText?.codes.count ?? 0)")
            for code in model.recognizedText?.codes ?? [] { print("OCR code \(code.kindName): \(code.payload)") }
            for match in model.sensitiveMatches { print("OCR suggestion \(match.kind.rawValue): \(match.text)") }
            for (i, line) in lines.enumerated() { print(String(format: "OCR %2d x=%4.0f y=%4.0f w=%4.0f h=%3.0f  %@", i, line.rect.minX, line.rect.minY, line.rect.width, line.rect.height, line.text)) }
            if CommandLine.arguments.contains("--ocr-select"), lines.count > 4 {
                model.textSelection = TextSelection(anchor: TextPosition(line: 1, offset: 3), head: TextPosition(line: 4, offset: min(6, lines[4].text.count)))
                model.refresh()
                print("OCR selected: \(model.selectedRecognizedText ?? "-")")
            }
            if let word = CommandLine.arguments.firstIndex(of: "--ocr-select-word").map({ CommandLine.arguments[$0 + 1] }),
               let first = model.recognizedText?.occurrences(of: word).first {
                model.textSelection = first
                print("OCR word \"\(word)\" occurs \(model.occurrencesOfSelectedText) time(s)")
            }
            if CommandLine.arguments.contains("--ocr-censor-suggestions") { print("OCR censored \(model.censorSuggestions()) suggestion(s); lines left: \(model.recognizedText?.lines.count ?? 0)") }
            if CommandLine.arguments.contains("--ocr-censor-all") { print("OCR censored \(model.censorAllOccurrencesOfSelectedText()) occurrence(s); lines left: \(model.recognizedText?.lines.count ?? 0)") }
            if CommandLine.arguments.contains("--ocr-pick-code") { model.selectedCodeIndex = 0; model.refresh() }
            fflush(stdout)
        }
        if small {
            window.setFrameOrigin(NSPoint(x: onScreen ? 60 : -6000, y: 300))
            // `--min`: shrink to the smallest size the user can drag the window to.
            if CommandLine.arguments.contains("--min") { window.setContentSize(window.contentMinSize) }
        } else {
            window.setFrame(NSRect(x: onScreen ? 60 : -6000, y: 200, width: 1100, height: 780), display: true)
        }
        window.orderFrontRegardless()
        if !small { controller.zoomToFit() }
        if CommandLine.arguments.contains("--geometry"), let scroll = controller.canvasForTesting.enclosingScrollView {
            try? await Task.sleep(nanoseconds: 800_000_000)
            print("GEOM window=\(window.frame) canvas=\(controller.canvasForTesting.frame) clipBounds=\(scroll.contentView.bounds) clipFrame=\(scroll.contentView.frame) contentSize=\(scroll.contentSize) zoom=\(model.zoom)")
            fflush(stdout)
        }
        if onScreen {
            // The caller grabs just this window with `screencapture -l <number>`.
            print("WINDOW \(window.windowNumber)")
            print("editing=\(model.editingTextID != nil) firstResponder=\(String(describing: window.firstResponder))")
            fflush(stdout)
            for _ in 0..<14 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                print("editing=\(model.editingTextID != nil) tool=\(model.tool.rawValue) key=\(window.isKeyWindow) annotations=\(model.annotations.count) steps=\(model.annotations.filter { $0.kind == .step }.count)")
                fflush(stdout)
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            return
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}

/// Verifies the real ScreenCaptureKit paths against a window WhiteShot draws itself: four solid colour
/// quadrants. Only pixels inside that fixture are inspected; nothing else on screen is read out,
/// saved or printed.
@MainActor
enum CaptureSelfTest {
    private final class QuadrantView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let colors: [NSColor] = [NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0.85, blue: 0, alpha: 1),
                                     NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), NSColor(srgbRed: 1, green: 0.9, blue: 0, alpha: 1)]
            let w = bounds.width / 2, h = bounds.height / 2
            // Cocoa y is up: top-left red, top-right green, bottom-left blue, bottom-right yellow.
            let rects = [NSRect(x: 0, y: h, width: w, height: h), NSRect(x: w, y: h, width: w, height: h),
                         NSRect(x: 0, y: 0, width: w, height: h), NSRect(x: w, y: 0, width: w, height: h)]
            for (c, r) in zip(colors, rects) { c.setFill(); r.fill() }
        }
    }

    private static func report(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(name) \(detail)")
        fflush(stdout)
    }

    /// Dominant-channel check, tolerant of colour management between sRGB and the display profile.
    private static func looksLike(_ p: (r: Int, g: Int, b: Int, a: Int), _ expected: String) -> Bool {
        switch expected {
        case "red": return p.r > 200 && p.g < 90 && p.b < 90
        case "green": return p.g > 150 && p.r < 90 && p.b < 90
        case "blue": return p.b > 200 && p.r < 90 && p.g < 90
        default: return p.r > 200 && p.g > 180 && p.b < 90
        }
    }

    private static func checkQuadrants(_ name: String, _ image: CGImage) {
        let w = image.width, h = image.height
        let points = [("red", w / 4, h / 4), ("green", 3 * w / 4, h / 4), ("blue", w / 4, 3 * h / 4), ("yellow", 3 * w / 4, 3 * h / 4)]
        let bad = points.filter { !looksLike(TestPixel.read(image, $0.1, $0.2), $0.0) }.map(\.0)
        report(name, bad.isEmpty, "\(w)x\(h) \(bad.isEmpty ? "" : "wrong: \(bad)")")
    }

    static func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            report("permission", false, "Screen Recording is not granted to this process")
            return
        }
        guard let screen = NSScreen.main, let displayID = ScreenGrabber.displayID(of: screen) else { report("screen", false); return }
        let frame = NSRect(x: screen.frame.minX + 300, y: screen.frame.maxY - 600, width: 400, height: 240)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = QuadrantView(frame: NSRect(origin: .zero, size: frame.size))
        window.level = .screenSaver
        window.hasShadow = false
        window.isOpaque = true
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 800_000_000)

        let local = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)

        do {
            let frozen = try await ScreenGrabber.grabAllDisplays(includeCursor: false)
            guard let display = frozen.first(where: { $0.displayID == displayID }) else { report("freeze-frame", false, "main display missing"); return }
            let s = display.scale
            report("freeze-frame scale", s >= 1, "scale \(s)")
            let pixels = CGRect(x: local.minX * s, y: local.minY * s, width: local.width * s, height: local.height * s)
            if let crop = ImageOps.crop(display.image, to: pixels) {
                checkQuadrants("freeze-frame crop", crop)
                report("freeze-frame size", crop.width == Int(local.width * s), "\(crop.width) expected \(Int(local.width * s))")
            } else { report("freeze-frame crop", false, "crop failed") }
        } catch { report("freeze-frame", false, "\(error)") }

        do {
            let grabbed = try await ScreenGrabber.grabRegion(displayID: displayID, rect: local, includeCursor: false)
            checkQuadrants("direct region", grabbed.image)
        } catch { report("direct region", false, "\(error)") }

        do {
            let grabbed = try await ScreenGrabber.grabWindow(id: CGWindowID(window.windowNumber), includeCursor: false)
            checkQuadrants("single window", grabbed.image)
        } catch { report("single window", false, "\(error)") }

        // Window mode: hovering the fixture must find it, and the highlight must land exactly on it.
        // (Moves the pointer briefly, then puts it back.)
        do {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let cgFrame = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            let info = WindowInfo(id: CGWindowID(window.windowNumber), frame: cgFrame, title: "fixture", ownerName: "WhiteShot")
            let frozen = FrozenDisplay(screen: screen, displayID: displayID, image: TestPixel.blank(), scale: screen.backingScaleFactor)
            let controller = CaptureOverlayController(frozen: [frozen], mode: .window, windows: [info], showLoupe: false)
            var outcome: CaptureOverlayController.Outcome?
            controller.begin(present: false) { outcome = $0 }
            let original = NSEvent.mouseLocation
            CGWarpMouseCursorPosition(CGPoint(x: cgFrame.midX, y: cgFrame.midY))
            try? await Task.sleep(nanoseconds: 200_000_000)
            controller.refreshHover()
            report("window hover finds the window", controller.hoveredWindow?.id == info.id)
            let highlight = controller.hoveredWindowFrame(on: screen)
            let expected = CGRect(x: frame.minX - screen.frame.minX, y: frame.minY - screen.frame.minY, width: frame.width, height: frame.height)
            report("window highlight rectangle", highlight.map { abs($0.minX - expected.minX) < 1 && abs($0.minY - expected.minY) < 1 && abs($0.width - expected.width) < 1 && abs($0.height - expected.height) < 1 } ?? false,
                   "got \(String(describing: highlight)) expected \(expected)")
            CGWarpMouseCursorPosition(CGPoint(x: cgFrame.maxX + 120, y: cgFrame.midY))
            try? await Task.sleep(nanoseconds: 200_000_000)
            controller.refreshHover()
            report("window hover off the window", controller.hoveredWindow == nil)
            controller.cancel()
            CGWarpMouseCursorPosition(CGPoint(x: original.x, y: primaryHeight - original.y))
            _ = outcome
        }

        let listed = WindowList.onScreenWindows()
        report("window list", true, "\(listed.count) windows (own fixture excluded by layer)")
        window.orderOut(nil)
    }
}

/// Pixel reader used by the self-test (the unit tests have their own).
enum TestPixel {
    static func blank() -> CGImage {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    static func read(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
    }
}

/// A made-up app window with fictional data, so tests never involve real screen content.
enum SampleScreenshot {
    static func make(width: Int, height: Int) -> CGImage {
        let w = width * 2, h = height * 2
        let ctx = Renderer.makeContext(width: w, height: h, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        ctx.scaleBy(x: 2, y: 2)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        func fill(_ r: CGRect, _ c: NSColor) { c.setFill(); r.fill() }
        func text(_ s: String, _ p: CGPoint, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor = NSColor(white: 0.12, alpha: 1)) {
            (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }

        fill(CGRect(x: 0, y: 0, width: width, height: height), NSColor(white: 0.97, alpha: 1))
        fill(CGRect(x: 0, y: 0, width: width, height: 44), NSColor(white: 0.90, alpha: 1))
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: CGRect(x: 16 + i * 22, y: 15, width: 13, height: 13)).fill()
        }
        text("Fabrikam Billing", CGPoint(x: 540, y: 13), size: 14, weight: .semibold)
        fill(CGRect(x: 0, y: 44, width: 220, height: height - 44), NSColor(white: 0.93, alpha: 1))
        for (i, item) in ["Dashboard", "Invoices", "Customers", "Payments", "Reports", "Settings"].enumerated() {
            if i == 1 { fill(CGRect(x: 10, y: 66 + i * 36, width: 200, height: 30), NSColor.systemBlue.withAlphaComponent(0.18)) }
            text(item, CGPoint(x: 28, y: 73 + i * 36), size: 14, weight: i == 1 ? .semibold : .regular)
        }
        text("Invoice #2026-0142", CGPoint(x: 260, y: 70), size: 26, weight: .bold)
        text("Customer: Contoso Ltd", CGPoint(x: 260, y: 116), size: 15)
        text("Contact: Alex Example, alex@example.com", CGPoint(x: 260, y: 142), size: 15)
        // Well-known test numbers: they pass the IBAN and card checksums but belong to nobody.
        text("IBAN: DE89 3704 0044 0532 0130 00", CGPoint(x: 260, y: 168), size: 15)
        text("Card: 4111 1111 1111 1111", CGPoint(x: 260, y: 194), size: 15)
        text("Phone: +49 30 1234567", CGPoint(x: 260, y: 220), size: 15)
        text("Portal: https://contoso.example/billing", CGPoint(x: 760, y: 168), size: 15)
        text("Server: 192.168.0.12", CGPoint(x: 760, y: 194), size: 15)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(Data("https://contoso.example/pay/2026-0142".utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage {
                let scaled = output.transformed(by: CGAffineTransform(scaleX: 5, y: 5))
                if let qr = CIContext().createCGImage(scaled, from: scaled.extent) {
                    fill(CGRect(x: 1066, y: 58, width: 140, height: 140), .white)
                    NSImage(cgImage: qr, size: NSSize(width: 120, height: 120)).draw(in: CGRect(x: 1076, y: 68, width: 120, height: 120), from: .zero,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
                }
            }
        }
        fill(CGRect(x: 260, y: 250, width: 960, height: 36), NSColor(white: 0.86, alpha: 1))
        for (i, head) in ["Item", "Qty", "Price", "Total"].enumerated() {
            text(head, CGPoint(x: 276 + i * 230, y: 259), size: 13, weight: .semibold)
        }
        for row in 0..<6 {
            let y = 296 + row * 44
            fill(CGRect(x: 260, y: y, width: 960, height: 40), row % 2 == 0 ? .white : NSColor(white: 0.985, alpha: 1))
            text("Consulting package \(row + 1)", CGPoint(x: 276, y: y + 11), size: 14)
            text("\(row + 1)", CGPoint(x: 506, y: y + 11), size: 14)
            text("€ \(120 + row * 15).00", CGPoint(x: 736, y: y + 11), size: 14)
            text("€ \((120 + row * 15) * (row + 1)).00", CGPoint(x: 966, y: y + 11), size: 14)
        }
        fill(CGRect(x: 1020, y: 590, width: 200, height: 44), NSColor.systemGreen)
        text("Mark as paid", CGPoint(x: 1060, y: 603), size: 15, weight: .semibold, color: .white)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    @MainActor
    static func annotate(_ model: EditorModel) {
        func add(_ kind: AnnotationKind, _ configure: (inout Annotation) -> Void) {
            var a = model.makeAnnotation(kind)
            configure(&a)
            model.add(a, select: false)
        }
        let k: CGFloat = 2
        add(.obfuscate) { $0.rect = CGRect(x: 260 * k, y: 164 * k, width: 330 * k, height: 26 * k); $0.style.obfuscateMode = .pixelate }
        add(.obfuscate) { $0.rect = CGRect(x: 260 * k, y: 190 * k, width: 270 * k, height: 26 * k); $0.style.obfuscateMode = .blur }
        add(.rectangle) { $0.rect = CGRect(x: 255 * k, y: 105 * k, width: 290 * k, height: 50 * k); $0.style.strokeColor = .red; $0.style.lineWidth = 3 * k }
        add(.arrow) { $0.start = CGPoint(x: 700 * k, y: 140 * k); $0.end = CGPoint(x: 560 * k, y: 128 * k); $0.style.lineWidth = 4 * k; $0.style.shadow = true }
        add(.text) {
            $0.rect = CGRect(x: 710 * k, y: 120 * k, width: 260 * k, height: 40 * k)
            $0.text = "Check the customer name"
            $0.style.fontSize = 20 * k; $0.style.bold = true
        }
        add(.highlight) { $0.rect = CGRect(x: 258 * k, y: 66 * k, width: 270 * k, height: 36 * k); $0.style.highlightMode = .text }
        add(.step) { $0.rect = CGRect(x: 236 * k, y: 255 * k, width: 30 * k, height: 30 * k) }
        add(.step) { $0.rect = CGRect(x: 1190 * k, y: 566 * k, width: 30 * k, height: 30 * k) }
        add(.ellipse) { $0.rect = CGRect(x: 1010 * k, y: 580 * k, width: 220 * k, height: 64 * k); $0.style.strokeColor = .blue; $0.style.lineWidth = 3 * k }
        add(.bubble) {
            $0.rect = CGRect(x: 800 * k, y: 660 * k, width: 260 * k, height: 70 * k)
            $0.tail = CGPoint(x: 1060 * k, y: 640 * k)
            $0.text = "Click here when paid"
        }
        add(.freehand) {
            $0.points = (0...40).map { (i: Int) -> CGPoint in
                let x: CGFloat = CGFloat(300 + i * 9) * k
                let wave: CGFloat = CGFloat(sin(Double(i) / 3)) * 14
                return CGPoint(x: x, y: (690 + wave) * k)
            }
            $0.style.strokeColor = .green; $0.style.lineWidth = 4 * k
        }
        model.selection = []
        model.undoManager.removeAllActions()
        model.markClean()
    }
}


/// Debug builds only: with `WHITESHOT_DEBUG_ACTIVATION=<file>` set, writes what the app believes about being active and
/// about its menu bar to that file (every change, and the key events around it). With `WHITESHOT_FAKE_CAPTURE=1` the
/// capture shortcuts deliver a synthetic picture through the normal output pipeline instead of reading the screen.
@MainActor
enum ActivationProbe {
    static var fakeCaptureRequested: Bool { ProcessInfo.processInfo.environment["WHITESHOT_FAKE_CAPTURE"] == "1" }
    /// `WHITESHOT_FAKE_CAPTURE=overlay`: the real selection overlay, but over a synthetic picture instead of the screen.
    static var fakeOverlayRequested: Bool { ProcessInfo.processInfo.environment["WHITESHOT_FAKE_CAPTURE"] == "overlay" }

    static func syntheticDisplays() -> [FrozenDisplay] {
        NSScreen.screens.map { screen in
            FrozenDisplay(screen: screen, displayID: ScreenGrabber.displayID(of: screen) ?? 0,
                          image: SampleScreenshot.make(width: Int(screen.frame.width), height: Int(screen.frame.height)), scale: 2)
        }
    }

    private static var lastState = ""

    private nonisolated static func menuItem(_ action: Selector, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.action == action { return item }
            if let found = menuItem(action, in: item.submenu) { return found }
        }
        return nil
    }

    static func start() {
        guard let path = ProcessInfo.processInfo.environment["WHITESHOT_DEBUG_ACTIVATION"] else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        let start = Date()
        func log(_ text: String) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            handle.write(String(format: "%6.2f %@\n", Date().timeIntervalSince(start), text).data(using: .utf8)!)
            try? handle.close()
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let title = (note.object as? NSWindow)?.title ?? ""
                MainActor.assumeIsolated { log("EVENT \(note.name.rawValue.replacingOccurrences(of: "NS", with: "")) \(title)") }
            }
        }
        log("PROBE started pid=\(ProcessInfo.processInfo.processIdentifier)")
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                NSApp.mainMenu?.update()
                func enabled(_ selector: Selector) -> String {
                    guard let item = menuItem(selector, in: NSApp.mainMenu) else { return "?" }
                    return item.isEnabled ? "on" : "OFF"
                }
                let editors = EditorWindowController.controllers.count
                let state = "policy=\(NSApp.activationPolicy().rawValue) isActive=\(NSApp.isActive) runningAppActive=\(NSRunningApplication.current.isActive)"
                    + " frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")"
                    + " key=\(NSApp.keyWindow?.title ?? "-") main=\(NSApp.mainWindow?.title ?? "-") editors=\(editors) zoom=\(EditorWindowController.controllers.first?.model.zoom ?? 0)"
                    + " menuBarVisible=\(NSMenu.menuBarVisible())"
                    + " | menu: zoomIn=\(enabled(#selector(EditorWindowController.zoomInMenu(_:)))) save=\(enabled(#selector(EditorWindowController.saveDocument(_:))))"
                    + " close=\(enabled(#selector(NSWindow.performClose(_:)))) settings=\(enabled(#selector(AppDelegate.showSettings(_:))))"
                if state != lastState { lastState = state; log("STATE \(state)") }
            }
        }
    }
}


/// Captures one of WhiteShot's own windows with and without its shadow and reports the sizes and the transparency around it.
/// Only that window's pixels are looked at.
@MainActor
enum WindowShadowTest {
    static func run() async {
        guard CGPreflightScreenCaptureAccess() else { print("FAIL permission"); return }
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(x: screen.frame.minX + 300, y: screen.frame.maxY - 640, width: 420, height: 260)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Shadow fixture"
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemTeal.cgColor
        window.contentView = view
        window.hasShadow = true
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 900_000_000)
        print("window frame \(window.frame) number \(window.windowNumber)")
        for shadow in [false, true] {
            do {
                let grabbed = try await ScreenGrabber.grabWindow(id: CGWindowID(window.windowNumber), includeCursor: false, includeShadow: shadow)
                let image = grabbed.image
                func alpha(_ x: Int, _ y: Int) -> Int { TestPixel.read(image, x, y).a }
                print("shadow=\(shadow): image \(image.width)x\(image.height) scale \(grabbed.scale); alpha corner(0,0)=\(alpha(0, 0)) edge-mid-left=\(alpha(0, image.height / 2)) centre=\(alpha(image.width / 2, image.height / 2)) below-bottom-mid=\(alpha(image.width / 2, image.height - 1))")
            } catch { print("shadow=\(shadow): error \(error)") }
        }
        // Experiments with the output size: where do the opaque window and its faint shadow end up?
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { window.orderOut(nil); return }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        func bounds(_ image: CGImage, minAlpha: Int) -> String {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            let width = image.width
            for y in 0..<image.height {
                for x in 0..<width {
                    let alpha = Int(data[(y * width + x) * 4 + 3])
                    if alpha >= minAlpha {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            return maxX < 0 ? "none" : "x \(minX)...\(maxX) y \(minY)...\(maxY)"
        }
        for (label, w, h) in [("default size 840x520", 840, 520), ("padded 1200x880", 1200, 880), ("padded 1000x760", 1000, 760)] {
            let config = SCStreamConfiguration()
            config.width = w; config.height = h
            config.ignoreShadowsSingleWindow = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                print("\(label): image \(image.width)x\(image.height); opaque(255) \(bounds(image, minAlpha: 250)); any shadow(>=2) \(bounds(image, minAlpha: 2))")
            }
        }
        window.orderOut(nil)
    }
}


/// Drags the picture out of an editor onto a window of this process and reports what arrived. Needs a real mouse drag from
/// outside (cliclick), between two of WhiteShot's own windows.
@MainActor
enum DragTest {
    private final class DropTargetView: NSView {
        var onDrop: ([URL]) -> Void = { _ in }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            onDrop(urls)
            return !urls.isEmpty
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemGreen.withAlphaComponent(0.35).setFill()
            bounds.fill()
        }
    }

    private static func findHandle(in view: NSView) -> ImageDragSourceView? {
        if let handle = view as? ImageDragSourceView { return handle }
        for sub in view.subviews { if let found = findHandle(in: sub) { return found } }
        return nil
    }

    static func run() async {
        let controller = EditorWindowController.present(CaptureResult(image: SampleScreenshot.make(width: 640, height: 400), scale: 2), savedURL: nil)
        guard let window = controller.window, let screen = NSScreen.main else { return }
        window.setFrame(NSRect(x: 60, y: screen.frame.maxY - 760, width: 900, height: 620), display: true)
        let target = NSWindow(contentRect: NSRect(x: 1000, y: screen.frame.maxY - 640, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        target.title = "Drop here"
        let dropView = DropTargetView(frame: NSRect(origin: .zero, size: NSSize(width: 300, height: 300)))
        var dropped = false
        dropView.onDrop = { urls in
            dropped = true
            for url in urls {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
                let decoded = ImageEncoder.decode(contentsOf: url)
                print("DROPPED \(url.lastPathComponent) bytes=\(size) image=\(decoded.map { "\($0.image.width)x\($0.image.height)" } ?? "unreadable") inDragFolder=\(url.path.hasPrefix(Exporter.dragDirectory.path))")
            }
            fflush(stdout)
        }
        target.contentView = dropView
        target.orderFrontRegardless()
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        guard let handle = findHandle(in: window.contentView ?? NSView()) else { print("NOHANDLE"); return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        func cg(_ rect: NSRect) -> CGPoint { CGPoint(x: rect.midX, y: primaryHeight - rect.midY) }
        let handlePoint = cg(window.convertToScreen(handle.convert(handle.bounds, to: nil)))
        let targetPoint = cg(target.convertToScreen(dropView.convert(dropView.bounds, to: nil)))
        print("READY handle=\(Int(handlePoint.x)),\(Int(handlePoint.y)) target=\(Int(targetPoint.x)),\(Int(targetPoint.y)) pid=\(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        for _ in 0..<120 where !dropped { try? await Task.sleep(nanoseconds: 250_000_000) }
        print(dropped ? "DONE" : "TIMEOUT")
        fflush(stdout)
    }
}

/// How long Vision takes on the synthetic sample, with different settings, in a fresh process. Prints milliseconds.
@MainActor
enum OCRTiming {
    struct Variant {
        var name: String
        var level: VNRequestTextRecognitionLevel = .accurate
        var correction = true
        var autoLanguage = true
        var languages: [String] = []
        var barcodes = true
    }

    /// Runs one recognition the way `TextRecognizer` does, and returns seconds and the number of lines.
    static func time(_ image: CGImage, _ v: Variant) async -> (seconds: Double, lines: Int) {
        let start = Date()
        let lines: Int = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = v.level
                text.usesLanguageCorrection = v.correction
                text.automaticallyDetectsLanguage = v.autoLanguage
                if !v.languages.isEmpty { text.recognitionLanguages = v.languages }
                var requests: [VNRequest] = [text]
                if v.barcodes { requests.append(VNDetectBarcodesRequest()) }
                try? VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
                continuation.resume(returning: text.results?.count ?? -1)
            }
        }
        return (Date().timeIntervalSince(start), lines)
    }

    /// Number of compiled models Vision has cached for this app (entries under the app's e5bundlecache folder).
    static func cachedModelCount() -> Int {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "").appendingPathComponent("com.apple.e5rt.e5bundlecache")
        guard let base, let builds = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return 0 }
        return builds.reduce(0) { $0 + ((try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent($1).path))?.count ?? 0) }
    }

    static func dense(width: Int, height: Int) -> CGImage {
        let ctx = Renderer.makeContext(width: width, height: height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        let g = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let words = ["function", "return", "value", "request", "result", "let", "config", "string", "image", "model", "count", "index", "self", "guard", "else",
                     "Invoice", "customer", "payment", "total", "2026-11-06", "alex@example.com", "https://contoso.example/api", "192.168.0.12", "0.75", "42"]
        var seed: UInt64 = 7
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        let font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        var y: CGFloat = 20
        while y < CGFloat(height) - 40 {
            var line = ""
            let count = 4 + next() % 10
            for _ in 0..<count { line += words[next() % words.count] + " " }
            (line as NSString).draw(at: CGPoint(x: 40 + CGFloat(next() % 4) * 48, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            y += 38
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func footprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? String(format: "%.0f MB", Double(info.phys_footprint) / 1_048_576) : "?"
    }

    /// Lines of text of one size and colour on a plain background, drawn with CoreText.
    static func textPicture(width: Int, height: Int, lines: [String], size: CGFloat, bold: Bool = false, fg: CGColor = CGColor(gray: 0.1, alpha: 1),
                            bg: CGColor = CGColor(gray: 0.97, alpha: 1), spacing: CGFloat = 1.6, mono: Bool = false, repeatLines: Bool = true,
                            colorful: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font: NSFont = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular) : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let palette: [CGColor] = [CGColor(red: 0.99, green: 0.5, blue: 0.4, alpha: 1), CGColor(red: 0.5, green: 0.8, blue: 1, alpha: 1), CGColor(red: 0.6, green: 0.9, blue: 0.5, alpha: 1), fg]
        var y = CGFloat(height) - size * 2
        var i = 0
        while y > size {
            let text = lines[i % lines.count]
            let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: fg])
            if colorful {
                var location = 0
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    attributed.addAttribute(.foregroundColor, value: palette[(location + i) % palette.count], range: NSRange(location: location, length: word.utf16.count))
                    location += word.utf16.count + 1
                }
            }
            ctx.textPosition = CGPoint(x: size * 2, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
            y -= size * spacing
            i += 1
            if !repeatLines && i >= lines.count { break }
        }
        return ctx.makeImage()!
    }

    /// A white picture with one QR code that is `fraction` of the picture's width.
    static func qrPicture(width: Int, height: Int, fraction: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("https://contoso.example/pay/2026-0142".utf8), forKey: "inputMessage")
        let raw = filter.outputImage!.samplingNearest()
        let side = max(24, CGFloat(width) * fraction)
        let scale = side / raw.extent.width
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let qr = CIContext().createCGImage(scaled, from: scaled.extent)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: CGFloat(width) * 0.3 - 20, y: CGFloat(height) * 0.4 - 20, width: side + 40, height: side + 40))
        ctx.draw(qr, in: CGRect(x: CGFloat(width) * 0.3, y: CGFloat(height) * 0.4, width: side, height: side))
        return ctx.makeImage()!
    }

    /// Does Vision compile its barcode model for each size of QR code it meets? Text and barcode detection are timed separately.
    static func runQR() async {
        func perform(_ image: CGImage, text: Bool, barcodes: Bool) async -> (Double, Int, Int) {
            let start = Date()
            let found: (Int, Int) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var requests: [VNRequest] = []
                    let t = VNRecognizeTextRequest(); t.recognitionLevel = .accurate; t.usesLanguageCorrection = true; t.automaticallyDetectsLanguage = true
                    let b = VNDetectBarcodesRequest()
                    if text { requests.append(t) }
                    if barcodes { requests.append(b) }
                    try? VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
                    continuation.resume(returning: (t.results?.count ?? 0, b.results?.count ?? 0))
                }
            }
            return (Date().timeIntervalSince(start), found.0, found.1)
        }
        print("bundle \(Bundle.main.bundleIdentifier ?? "?"), cached models \(cachedModelCount())")
        let tiny = SampleScreenshot.make(width: 300, height: 120)
        var before = cachedModelCount()
        var r = await perform(tiny, text: true, barcodes: false)
        print(String(format: "  %8.0f ms  cached models %d -> %d  TEXT ONLY, first call (tiny)", r.0 * 1000, before, cachedModelCount()))
        for fraction in [0.45, 0.3, 0.2, 0.14, 0.1, 0.07, 0.05, 0.035, 0.025, 0.018] as [CGFloat] {
            before = cachedModelCount()
            let picture = qrPicture(width: 2000, height: 1200, fraction: fraction)
            r = await perform(picture, text: false, barcodes: true)
            print(String(format: "  %8.0f ms  cached models %d -> %d  BARCODES ONLY, QR = %4.1f%% of the width (%4.0f px), codes found %d", r.0 * 1000, before, cachedModelCount(),
                         fraction * 100, 2000 * fraction, r.2))
            fflush(stdout)
        }
        before = cachedModelCount()
        r = await perform(SampleScreenshot.make(width: 2560, height: 1600), text: true, barcodes: true)
        print(String(format: "  %8.0f ms  cached models %d -> %d  TEXT + BARCODES on the sample 5120x3200 afterwards", r.0 * 1000, before, cachedModelCount()))
    }

    /// After the warm-up in a fresh app: which kinds of pictures still make Vision compile something new?
    static func runDiversity() async {
        let report = await VisionWarmUp.run()
        print(String(format: "warm-up: %.1f s, completed %@, cached models %d", report.seconds.reduce(0, +), report.completedAll ? "yes" : "NO", cachedModelCount()))
        let prose = ["The quick brown fox jumps over the lazy dog while Alex reads the invoice", "Please transfer 1,170.00 EUR to the account below by Friday",
                     "Customer support is available from Monday to Friday, 9:00 to 17:00", "Reports, Settings, Dashboard, Payments and Customers"]
        let code = ["func render(base: CGImage, annotations: [Annotation]) -> CGImage? {", "    guard let ctx = makeContext(width: w, height: h) else { return nil }",
                    "    let result = annotations.reduce(into: [:]) { $0[$1.id] = $1 }  // 42", "}"]
        let german = ["Überweisen Sie bitte den Betrag bis Freitag auf das Konto der Müller & Söhne GmbH", "Größe ändern, Schatten hinzufügen, Rand und Weichzeichnen"]
        let cjk = ["請於週五前將款項匯入以下帳戶，謝謝您的合作", "お支払いは金曜日までにお願いいたします。ご不明な点はお問い合わせください"]
        let cyrillic = ["Пожалуйста, переведите сумму до пятницы на указанный счёт", "Служба поддержки работает с понедельника по пятницу"]
        let dark = CGColor(gray: 0.12, alpha: 1), light = CGColor(gray: 0.92, alpha: 1)
        let cases: [(String, CGImage)] = [
            ("sample with QR 5120x3200", SampleScreenshot.make(width: 2560, height: 1600)),
            ("big heading text 100 px, 2560x1600", textPicture(width: 2560, height: 1600, lines: ["Quarterly Report", "Invoice 2026-0142"], size: 100, bold: true, spacing: 1.5)),
            ("small text 16 px, 2560x1600", textPicture(width: 2560, height: 1600, lines: prose, size: 16)),
            ("dark mode text 24 px, 2560x1600", textPicture(width: 2560, height: 1600, lines: prose, size: 24, fg: light, bg: dark)),
            ("coloured code on dark, 3456x2234", textPicture(width: 3456, height: 2234, lines: code, size: 24, fg: light, bg: dark, mono: true, colorful: true)),
            ("bold text 28 px, 2560x1600", textPicture(width: 2560, height: 1600, lines: prose, size: 28, bold: true)),
            ("medium text 40 px, 3840x2160", textPicture(width: 3840, height: 2160, lines: prose, size: 40)),
            ("one very long line 28 px, 3024x300", textPicture(width: 3024, height: 300, lines: [prose[0] + " — " + prose[1] + " — " + prose[2]], size: 28, repeatLines: false)),
            ("German text 28 px, 2560x1600", textPicture(width: 2560, height: 1600, lines: german, size: 28)),
            ("Japanese and Chinese text, 2560x1600", textPicture(width: 2560, height: 1600, lines: cjk, size: 32)),
            ("Cyrillic text, 2560x1600", textPicture(width: 2560, height: 1600, lines: cyrillic, size: 32)),
        ]
        if CommandLine.arguments.contains("--many-lines") {
            // Does a picture with many lines of text need a model of its own? Dense pictures from few lines to very many, then the sample.
            let words = ["function", "return", "value", "request", "result", "config", "string", "image", "model", "count", "index", "Invoice", "customer"]
            func lineSet(_ count: Int) -> [String] { (0..<count).map { i in (0..<6).map { words[(i * 7 + $0 * 3) % words.count] }.joined(separator: " ") } }
            let sets: [(String, CGImage)] = [
                ("  20 lines of 24 px text, 2560x1600", textPicture(width: 2560, height: 1600, lines: lineSet(20), size: 24, spacing: 3.0, repeatLines: false)),
                ("  45 lines of 24 px text, 2560x1600", textPicture(width: 2560, height: 1600, lines: lineSet(45), size: 24, spacing: 1.45, repeatLines: false)),
                ("  70 lines of 20 px text, 3024x1964", textPicture(width: 3024, height: 1964, lines: lineSet(70), size: 20, spacing: 1.35, repeatLines: false)),
                (" 100 lines of 20 px text, 3456x2234", textPicture(width: 3456, height: 2234, lines: lineSet(100), size: 20, spacing: 1.05, repeatLines: false)),
                (" 140 lines of 16 px text, 5120x2880", textPicture(width: 5120, height: 2880, lines: lineSet(140), size: 16, spacing: 1.2, repeatLines: false)),
                (" 200 lines of 14 px text, 5120x2880", textPicture(width: 5120, height: 2880, lines: lineSet(200), size: 14, spacing: 1.0, repeatLines: false)),
                ("sample with QR 5120x3200", SampleScreenshot.make(width: 2560, height: 1600)),
            ]
            for (name, image) in sets {
                let before = cachedModelCount()
                let r = await time(image, Variant(name: name))
                print(String(format: "  %8.0f ms  lines %3d  cached models %d -> %d  %@", r.seconds * 1000, r.lines, before, cachedModelCount(), name))
                fflush(stdout)
            }
            return
        }
        let ordered = CommandLine.arguments.contains("--sample-last") ? Array(cases.dropFirst()) + [cases[0]] : cases
        for (name, image) in ordered {
            let before = cachedModelCount()
            let r = await time(image, Variant(name: name))
            let after = cachedModelCount()
            print(String(format: "  %8.0f ms  lines %3d  cached models %d -> %d  %@", r.seconds * 1000, r.lines, before, after, name))
            fflush(stdout)
        }
    }

    /// The warm-up in an app whose model cache starts empty, then a mixed set of pictures that must all be fast afterwards.
    /// With `--concurrent` a recognition is started while the warm-up is still busy.
    static func runWarmUpLab() async {
        print("bundle \(Bundle.main.bundleIdentifier ?? "?"), cached models \(cachedModelCount()), memory \(footprint())")
        if CommandLine.arguments.contains("--concurrent") {
            let background = Task { await VisionWarmUp.run() }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let t0 = Date()
            let r = await time(SampleScreenshot.make(width: 1280, height: 800), Variant(name: "user's first recognition, 2 s into the warm-up"))
            print(String(format: "  the user's recognition, started 2 s into the warm-up, took %.1f s (lines %d)", Date().timeIntervalSince(t0), r.lines))
            let report = await background.value
            print(String(format: "  the warm-up finished %.1f s after it started", report.seconds.reduce(0, +)))
            return
        }
        let start = Date()
        let report = await VisionWarmUp.run()
        print(String(format: "warm-up: %.1f s in total, completed: %@, per picture: %@, cached models %d, memory %@", Date().timeIntervalSince(start),
                     report.completedAll ? "yes" : "NO", report.seconds.map { String(format: "%.1f", $0) }.joined(separator: " / "), cachedModelCount(), footprint()))
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        print("  memory 8 s after the warm-up: \(footprint())")
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        print("  memory 28 s after the warm-up: \(footprint())")
        let cases: [(String, CGImage)] = [
            ("sample with QR 2560x1600", SampleScreenshot.make(width: 1280, height: 800)),
            ("sample with QR 3200x2000", SampleScreenshot.make(width: 1600, height: 1000)),
            ("sample with QR 4000x2500", SampleScreenshot.make(width: 2000, height: 1250)),
            ("sample with QR 5120x3200", SampleScreenshot.make(width: 2560, height: 1600)),
            ("sample with QR 6016x3384", SampleScreenshot.make(width: 3008, height: 1692)),
            ("dense text 2560x1600", dense(width: 2560, height: 1600)),
            ("dense text 3024x1964 (14\" MacBook)", dense(width: 3024, height: 1964)),
            ("dense text 3456x2234 (16\" MacBook)", dense(width: 3456, height: 2234)),
            ("dense text 3840x2160 (4K)", dense(width: 3840, height: 2160)),
            ("dense text 5120x2880 (5K)", dense(width: 5120, height: 2880)),
            ("dense text 5120x1440 (super ultrawide)", dense(width: 5120, height: 1440)),
            ("dense text 6016x3384 (6K)", dense(width: 6016, height: 3384)),
            ("dense text 7680x4320 (8K)", dense(width: 7680, height: 4320)),
            ("dense text 900x2600 (tall window)", dense(width: 900, height: 2600)),
            ("dense text 1000x600 (small window)", dense(width: 1000, height: 600)),
            ("dense text 420x260 (tiny region)", dense(width: 420, height: 260)),
        ]
        for (name, image) in cases {
            let before = cachedModelCount()
            let r = await time(image, Variant(name: name))
            let after = cachedModelCount()
            print(String(format: "  %8.0f ms  lines %3d  cached models %d -> %d  %@", r.seconds * 1000, r.lines, before, after, name))
            fflush(stdout)
        }
    }

    /// A screen full of text: where does the time go once everything is compiled and cached?
    static func runDense() async {
        // Everything compiled first (a tiny call plus one large, QR-carrying image), so only the steady-state cost shows.
        _ = await time(SampleScreenshot.make(width: 300, height: 120), Variant(name: "warm"))
        for (w, h) in [(2560, 1600), (3456, 2234), (5120, 2880)] {
            let image = OCRTiming.dense(width: w, height: h)
            let t0 = Date()
            let result = try? await TextRecognizer.recognize(in: image)
            let full = Date().timeIntervalSince(t0)
            let raw = await time(image, Variant(name: "raw", barcodes: false))
            let chars = result?.lines.reduce(0) { $0 + $1.text.count } ?? 0
            let t1 = Date()
            _ = result.map(SensitiveDetector.matches(in:))
            let detect = Date().timeIntervalSince(t1)
            print(String(format: "  %4dx%4d: Vision alone %5.0f ms | full TextRecognizer.recognize %5.0f ms | lines %3d chars %5d | sensitive scan %4.0f ms",
                         w, h, raw.seconds * 1000, full * 1000, result?.lines.count ?? 0, chars, detect * 1000))
            fflush(stdout)
        }
    }

    /// A fixed sequence of images in an app whose model cache starts empty: which calls compile something new?
    static func runLab() async {
        func text(_ lines: [String], width: Int, height: Int, size: CGFloat = 15) -> CGImage {
            let ctx = Renderer.makeContext(width: width, height: height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
            let g = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
            ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + CGFloat(i) * size * 2.2), withAttributes: [.font: NSFont.systemFont(ofSize: size * 2), .foregroundColor: NSColor.black])
            }
            NSGraphicsContext.restoreGraphicsState()
            return ctx.makeImage()!
        }
        let english = ["Invoice 2026-0142 for Contoso Ltd", "Consulting package three costs 450 euros", "Please call us on Monday morning"]
        let german = ["Rechnung für Müller & Söhne GmbH", "Überweisung bitte bis Freitag, Straße 12", "Größe: ändern, löschen, öffnen"]
        let second = CommandLine.arguments.contains("--lab2")
        let cases: [(String, CGImage)] = second ? [
            ("tiny English text 600x240", text(english, width: 600, height: 240)),
            ("sample with QR 2560x1600", SampleScreenshot.make(width: 1280, height: 800)),
            ("sample with QR 3200x2000", SampleScreenshot.make(width: 1600, height: 1000)),
            ("sample with QR 4000x2500", SampleScreenshot.make(width: 2000, height: 1250)),
            ("sample with QR 5120x3200 (the earlier slow one)", SampleScreenshot.make(width: 2560, height: 1600)),
            ("sample with QR 6016x3384", SampleScreenshot.make(width: 3008, height: 1692)),
            ("sample with QR 5120x3200 again", SampleScreenshot.make(width: 2560, height: 1600)),
        ] : [
            ("tiny English text 600x240", text(english, width: 600, height: 240)),
            ("tiny English again", text(english, width: 600, height: 240)),
            ("tiny German text 600x240", text(german, width: 600, height: 240)),
            ("sample with QR 2560x1600", SampleScreenshot.make(width: 1280, height: 800)),
            ("ultrawide 3440x1440", text(english, width: 3440, height: 1440)),
            ("4K 3840x2160", text(english, width: 3840, height: 2160)),
            ("5K 5120x2880", text(english, width: 5120, height: 2880)),
            ("6K 6016x3384", text(english, width: 6016, height: 3384)),
            ("narrow tall 700x2400", text(english, width: 700, height: 2400)),
            ("sample with QR again", SampleScreenshot.make(width: 1280, height: 800)),
        ]
        print("bundle \(Bundle.main.bundleIdentifier ?? "?"), cached models at start: \(cachedModelCount())")
        for (name, image) in cases {
            let before = cachedModelCount()
            let r = await time(image, Variant(name: name))
            let after = cachedModelCount()
            print(String(format: "  %8.0f ms  lines %2d  cached models %d -> %d  %@", r.seconds * 1000, r.lines, before, after, name))
            fflush(stdout)
        }
    }

    /// First call per image size, in pixels, never used before: where does Vision's one-time preparation kick in?
    static func runSizes() async {
        let sizes = CommandLine.arguments.drop { $0 != "--sizes" }.dropFirst().first.map { $0.split(separator: ",").map(String.init) } ?? []
        for entry in sizes {
            let parts = entry.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let image = SampleScreenshot.make(width: parts[0] / 2, height: parts[1] / 2)
            let first = await time(image, Variant(name: entry))
            let second = await time(image, Variant(name: entry))
            print(String(format: "  %5d x %5d px (%5.1f MP): first %8.0f ms   second %6.0f ms   lines %d", image.width, image.height,
                         Double(image.width * image.height) / 1e6, first.seconds * 1000, second.seconds * 1000, first.lines))
            fflush(stdout)
        }
    }

    static func run() async {
        func ms(_ s: Double) -> String { String(format: "%7.0f ms", s * 1000) }
        let tiny = SampleScreenshot.make(width: 300, height: 120)             // 600 x 240 px with a few lines of text
        let normal = SampleScreenshot.make(width: 1280, height: 800)           // 2560 x 1600 px, a typical Retina window
        let huge = SampleScreenshot.make(width: 2560, height: 1600)            // 5120 x 3200 px, a full 5K screen
        print("process started; first calls in this process:")
        let base = Variant(name: "baseline")
        for i in 1...3 { let r = await time(tiny, base); print("  tiny   call \(i): \(ms(r.seconds))  lines \(r.lines)") }
        for i in 1...3 { let r = await time(normal, base); print("  normal call \(i): \(ms(r.seconds))  lines \(r.lines)") }
        for i in 1...2 { let r = await time(huge, base); print("  huge   call \(i): \(ms(r.seconds))  lines \(r.lines)") }
        print("variants on the normal image (best of 3):")
        let variants = [
            Variant(name: "baseline (accurate, correction, auto language, barcodes)"),
            Variant(name: "without barcode detection", barcodes: false),
            Variant(name: "language correction off", correction: false),
            Variant(name: "auto language off, en-US + de-DE", autoLanguage: false, languages: ["en-US", "de-DE"]),
            Variant(name: "auto language off, en-US only", autoLanguage: false, languages: ["en-US"]),
            Variant(name: "fast level", level: .fast),
            Variant(name: "fast, no correction, no barcodes", level: .fast, correction: false, barcodes: false),
        ]
        for v in variants {
            var best = Double.infinity, lines = 0
            for _ in 1...3 { let r = await time(normal, v); best = min(best, r.seconds); lines = r.lines }
            print("  \(ms(best))  lines \(lines)  \(v.name)")
        }
        fflush(stdout)
    }
}
#endif
