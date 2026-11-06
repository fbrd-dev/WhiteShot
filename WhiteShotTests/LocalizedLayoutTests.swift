import AppKit
import SwiftUI
import XCTest
@testable import WhiteShot

/// The bars around the picture must lay out cleanly in every language the app ships, however long its words are.
///
/// Each bar is rendered in each shipped language (the test reads the languages from the app bundle, so a language added to
/// the string catalog later is covered without touching this file) at a wide, a narrow and a very narrow width. Controls
/// must keep their natural width, never overlap one another, and, where there is room, lie inside the bar.
@MainActor
final class LocalizedLayoutTests: XCTestCase {
    override func setUp() { StyleDefaults.stash() }
    override func tearDown() { StyleDefaults.restore() }

    /// Every language the app is translated into (the development language included).
    private var languages: [String] { Bundle.main.localizations.filter { $0 != "Base" }.sorted() }

    private let widths: [CGFloat] = [1200, 760, 420]

    // MARK: Helpers

    private final class Rendered {
        let window: NSWindow
        let host: NSHostingView<AnyView>
        init(window: NSWindow, host: NSHostingView<AnyView>) { self.window = window; self.host = host }
        deinit { window.close() }
    }

    private func render<V: View>(_ view: V, language: String, width: CGFloat, height: CGFloat) -> Rendered {
        let root = AnyView(view.environment(\.locale, Locale(identifier: language)))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false          // ARC owns it; AppKit must not release it a second time on close
        window.setFrameOrigin(NSPoint(x: -6000, y: 0))
        window.contentView = host
        window.orderBack(nil)
        for _ in 0..<2 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        return Rendered(window: window, host: host)
    }

    private func controls(in view: NSView) -> [NSView] {
        var found: [NSView] = []
        func walk(_ v: NSView) {
            if v is NSSegmentedControl || v is NSSlider || v is NSStepper || v is NSPopUpButton || v is NSButton { found.append(v) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    private func frame(of control: NSView, in host: NSView) -> NSRect { control.convert(control.bounds, to: host) }

    private func segmentTitles(_ control: NSSegmentedControl) -> [String] { (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" } }

    /// The checks every bar has to pass, in every language and at every width.
    /// `needsControls` is off for a bar whose buttons SwiftUI draws itself, which leaves no AppKit control to measure.
    private func assertCleanLayout(_ rendered: Rendered, _ what: String, needsControls: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let host = rendered.host
        let all = controls(in: host)
        if needsControls { XCTAssertFalse(all.isEmpty, "\(what): no controls were created", file: file, line: line) }
        for control in all {
            let box = frame(of: control, in: host)
            XCTAssertGreaterThan(box.width, 0, "\(what): a control has no width", file: file, line: line)
            // Controls that show words must not be squeezed below the width their words need: that is what made the
            // segments of a picker run into the control next to it.
            if let segmented = control as? NSSegmentedControl {
                XCTAssertGreaterThanOrEqual(box.width + 1, segmented.intrinsicContentSize.width,
                                            "\(what): the picker “\(segmentTitles(segmented).joined(separator: " | "))” is \(Int(box.width)) pt wide but its labels need \(Int(segmented.intrinsicContentSize.width)) pt",
                                            file: file, line: line)
            }
        }
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                if a.isDescendant(of: b) || b.isDescendant(of: a) { continue }
                let overlap = frame(of: a, in: host).intersection(frame(of: b, in: host))
                XCTAssertFalse(overlap.width > 1 && overlap.height > 1,
                               "\(what): two controls overlap by \(Int(overlap.width)) × \(Int(overlap.height)) pt", file: file, line: line)
            }
        }
    }

    /// Stands in for the editor window, which the bars only call into; a real one per case would be a window each.
    private final class NoCommands: EditorCommands {
        func selectTool(_ tool: EditorTool) {}
        func applyCrop() {}
        func cancelCrop() {}
        func zoomIn() {}
        func zoomOut() {}
        func zoomToActualSize() {}
        func zoomToFit() {}
        func endTextRecognition() {}
        func copyAllRecognizedText() {}
        func copyRecognizedSelection() {}
        func openSelectedCode() {}
        func pinImage() {}
        func prepareDragFile() -> (url: URL, preview: NSImage)? { nil }
    }

    private func makeBar(model: EditorModel) -> (PropertyBarView, NoCommands) {
        let commands = NoCommands()
        return (PropertyBarView(model: model, commands: commands), commands)
    }

    // MARK: Tests

    func testTheLanguageSwitchInTheTestReallyChangesTheWords() throws {
        XCTAssertTrue(languages.contains("en") && languages.contains("de"), "found \(languages)")
        let model = EditorModel(image: TestImage.solid(400, 300), scale: 1)
        model.tool = .obfuscate
        let (bar, controller) = makeBar(model: model)
        var titles: [String: [String]] = [:]
        for language in ["en", "de"] {
            let rendered = render(bar, language: language, width: 1200, height: 42)
            titles[language] = controls(in: rendered.host).compactMap { $0 as? NSSegmentedControl }.flatMap(segmentTitles)
        }
        XCTAssertEqual(titles["en"], ["Pixelate", "Blur", "Black Out"])
        XCTAssertEqual(titles["de"], ["Verpixeln", "Weichzeichnen", "Schwärzen"], "otherwise this test would check nothing")
        _ = controller
    }

    func testEveryToolBarLaysOutCleanlyInEveryLanguage() throws {
        struct Case { var name: String; var tool: EditorTool; var prepare: (EditorModel) -> Void = { _ in } }
        var cases: [Case] = [.init(name: "rectangle", tool: .rectangle), .init(name: "ellipse", tool: .ellipse), .init(name: "line", tool: .line),
                             .init(name: "arrow", tool: .arrow), .init(name: "freehand", tool: .freehand), .init(name: "text", tool: .text),
                             .init(name: "speech bubble", tool: .bubble), .init(name: "step number", tool: .step),
                             .init(name: "crop", tool: .crop, prepare: { $0.cropRect = CGRect(x: 10, y: 10, width: 200, height: 100) })]
        for mode in ObfuscateMode.allCases {
            cases.append(.init(name: "censor (\(mode))", tool: .obfuscate, prepare: { $0.setCensorMode(mode) }))
        }
        for mode in HighlightMode.allCases {
            cases.append(.init(name: "highlight (\(mode))", tool: .highlight, prepare: { model in model.updateStyle { $0.highlightMode = mode } }))
        }
        for language in languages {
            for item in cases {
                let model = EditorModel(image: TestImage.solid(400, 300), scale: 1)
                model.tool = item.tool
                item.prepare(model)
                let (bar, controller) = makeBar(model: model)
                for width in widths {
                    let rendered = render(bar, language: language, width: width, height: 42)
                    assertCleanLayout(rendered, "\(item.name) bar, \(language), \(Int(width)) pt wide", needsControls: item.tool != .crop)
                }
                _ = controller
            }
        }
    }

    func testTheBarWithAnAnnotationSelectedLaysOutCleanly() throws {
        for language in languages {
            let model = EditorModel(image: TestImage.solid(400, 300), scale: 1)
            var box = model.makeAnnotation(.bubble)
            box.rect = CGRect(x: 20, y: 20, width: 120, height: 60)
            model.add(box)                                         // selected: the Delete button joins the bar
            let (bar, controller) = makeBar(model: model)
            for width in widths {
                assertCleanLayout(render(bar, language: language, width: width, height: 42), "selected bubble bar, \(language), \(Int(width)) pt wide")
            }
            _ = controller
        }
    }

    func testTheTextRecognitionBarLaysOutCleanlyInEveryLanguage() throws {
        let lines = ["Contact alex@example.com", "Call +49 30 1234567", "IBAN DE89 3704 0044 0532 0130 00", "Host 192.168.0.12"].enumerated().map { index, text in
            RecognizedLine(text: text, rect: CGRect(x: 100, y: 50 + CGFloat(index) * 40, width: 10 * CGFloat(text.count), height: 24),
                           edges: (0...text.count).map { 100 + 10 * CGFloat($0) })
        }
        for language in languages {
            let model = EditorModel(image: TestImage.solid(800, 600), scale: 1)
            model.suggestionKindsProvider = { Set(SensitiveKind.allCases) }
            let generation = try XCTUnwrap(model.beginTextRecognition())
            model.finishTextRecognition(.success(RecognizedText(lines: lines, codes: [])), generation: generation)
            model.textSelection = model.recognizedText?.fullRange
            let (bar, controller) = makeBar(model: model)
            for width in widths {
                assertCleanLayout(render(bar, language: language, width: width, height: 76), "text recognition bar, \(language), \(Int(width)) pt wide")
            }
            _ = controller
        }
    }

    func testTheStatusBarLaysOutCleanlyInEveryLanguage() throws {
        for language in languages {
            let model = EditorModel(image: TestImage.solid(400, 300), scale: 1)
            let commands = NoCommands()
            for width in widths {
                let rendered = render(StatusBarView(model: model, commands: commands), language: language, width: width, height: 26)
                assertCleanLayout(rendered, "status bar, \(language), \(Int(width)) pt wide")
            }
        }
    }

    func testWhereThereIsRoomEverythingLiesInsideTheBar() throws {
        for language in languages {
            for tool in [EditorTool.obfuscate, .highlight, .text, .bubble] {
                let model = EditorModel(image: TestImage.solid(400, 300), scale: 1)
                model.tool = tool
                let (bar, controller) = makeBar(model: model)
                let rendered = render(bar, language: language, width: 1600, height: 42)
                for control in controls(in: rendered.host) {
                    let box = frame(of: control, in: rendered.host)
                    XCTAssertGreaterThanOrEqual(box.minX, -0.5, "\(tool) bar, \(language): a control starts outside the bar")
                    XCTAssertLessThanOrEqual(box.maxX, 1600.5, "\(tool) bar, \(language): a control ends outside the bar")
                }
                _ = controller
            }
        }
    }
}
