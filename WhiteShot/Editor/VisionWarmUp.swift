import AppKit
import CoreImage
import CoreText

/// Gets Vision ready for Recognize Text before anyone asks for it.
///
/// The first time an app uses Vision's text recognition, macOS compiles the models for it: about half a minute for the very first
/// picture, plus a few seconds more for the first window-like screenshot of large size. The compiled models are kept per app and
/// per macOS version, so after that every recognition takes a fraction of a second. Without this, that wait lands on the first
/// Recognize Text the user presses. With it, the same work is done in the background, once per macOS version, a little after
/// WhiteShot starts, on pictures made here that look like screenshots: lines of text, numbers, addresses and a QR code.
///
/// It runs in a short-lived helper process (this app started with `--warm-up-vision`), not in the app itself, so the memory the
/// models and the large pictures need (several hundred megabytes at the peak) is never taken from the menu bar app. Both
/// processes are the same app, so they share the compiled models.
@MainActor
enum VisionWarmUp {
    /// Remembers the macOS version the warm-up has run for. State, not a preference: "Reset All Settings" leaves it alone.
    static let doneKey = "ocr.warmedUpFor"

    /// Passed to the helper process.
    nonisolated static let helperFlag = "--warm-up-vision"

    enum Picture { case lines, screenshot }

    /// The pictures to prepare, smallest first. The first one pays for the base models. The others are the kinds of picture that
    /// were found to make Vision compile something more the first time it sees them: lines of text in columns, and a window-like
    /// screenshot (title bar, sidebar, table, button, QR code) of a size that only a large display produces. Anything in between,
    /// from a small region to a 6K screen, in light or dark mode, in Latin, Cyrillic or Chinese and Japanese text, was found to
    /// be fast afterwards.
    nonisolated static let pictures: [(kind: Picture, width: Int, height: Int)] = [
        (.lines, 600, 240), (.lines, 2560, 1600), (.screenshot, 5120, 3200),
    ]

    private static var helper: Process?

    /// The build of macOS, e.g. "26A434": compiled models do not carry over to another one.
    nonisolated static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func isNeeded(defaults: UserDefaults = .standard) -> Bool { defaults.string(forKey: doneKey) != osBuild }

    /// Whether this is a good moment: not while the Mac is saving power or running hot.
    static func isGoodMoment(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState) -> Bool {
        !lowPowerMode && thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    /// Starts the helper after `delay` seconds if the warm-up has not been done for this macOS version. At a bad moment it waits
    /// for the next launch.
    static func scheduleIfNeeded(after delay: TimeInterval = 12, defaults: UserDefaults = .standard) {
        guard helper == nil, isNeeded(defaults: defaults) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let info = ProcessInfo.processInfo
            guard isNeeded(defaults: defaults), isGoodMoment(lowPowerMode: info.isLowPowerModeEnabled, thermalState: info.thermalState) else { return }
            startHelper()
        }
    }

    /// Runs this app again as the helper, at a low priority and without a window. It writes `doneKey` itself when it has finished.
    @discardableResult
    static func startHelper() -> Process? {
        guard helper == nil, let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = [helperFlag]
        process.qualityOfService = .utility
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in DispatchQueue.main.async { helper = nil } }
        do { try process.run() } catch { return nil }
        helper = process
        return process
    }

    /// What the helper process does: prepare Vision, remember it, and quit.
    static func runAsHelper() {
        Task { @MainActor in
            let report = await run()
            if report.completedAll { UserDefaults.standard.set(osBuild, forKey: doneKey) }
            exit(report.completedAll ? 0 : 1)
        }
    }

    struct Report {
        /// Seconds per picture, in the order of `pictures`.
        var seconds: [Double] = []
        var completedAll = false
    }

    /// Recognises every warm-up picture once, one after the other, off the main thread at a low priority.
    static func run() async -> Report {
        await Task.detached(priority: .utility) {
            var report = Report()
            for item in VisionWarmUp.pictures {
                guard !Task.isCancelled, let image = VisionWarmUp.makeImage(item.kind, width: item.width, height: item.height) else { return report }
                let start = Date()
                do { _ = try await TextRecognizer.recognize(in: image) } catch { return report }
                report.seconds.append(Date().timeIntervalSince(start))
            }
            report.completedAll = true
            return report
        }.value
    }

    // MARK: The pictures

    private nonisolated static let lines = [
        "Invoice #2026-0142 for Contoso Ltd", "Customer: Alex Example, alex@example.com", "Phone: +49 30 1234567    Fax: 0800 1234567",
        "IBAN: DE89 3704 0044 0532 0130 00", "https://contoso.example/billing/2026-0142", "Server: 192.168.0.12    Port: 8443",
        "Consulting package 1        1        € 120.00        € 120.00", "Consulting package 2        2        € 135.00        € 270.00",
        "Consulting package 3        3        € 150.00        € 450.00", "func render(base: CGImage, annotations: [Annotation]) -> CGImage?",
        "let result = try await recognize(in: image, text: true, codes: true)", "Rechnung für Müller & Söhne GmbH, Straße 12, 10115 Berlin",
        "Dashboard    Invoices    Customers    Payments    Reports    Settings", "Total due on 2026-11-30: € 1,170.00 (incl. 19% VAT)",
    ]

    nonisolated static func makeImage(_ kind: Picture, width: Int, height: Int) -> CGImage? {
        switch kind {
        case .lines: return makeLinesImage(width: width, height: height)
        case .screenshot: return makeScreenshotImage(width: width, height: height)
        }
    }

    /// A window-like screenshot drawn at 2x (everything below is in points, 2 pixels each), in the top left corner of a picture of
    /// `width` × `height` pixels: title bar, sidebar, headings, a table with striped rows, a button and a QR code.
    nonisolated static func makeScreenshotImage(width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 2, y: -2)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        func fill(_ rect: CGRect, gray: CGFloat) { ctx.setFillColor(CGColor(gray: gray, alpha: 1)); ctx.fill(rect) }
        func fill(_ rect: CGRect, color: CGColor) { ctx.setFillColor(color); ctx.fill(rect) }
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, bold: Bool = false, gray: CGFloat = 0.12) {
            var font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            if bold, let heavier = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .boldTrait, .boldTrait) { font = heavier }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: CGColor(gray: gray, alpha: 1)]))
            ctx.textPosition = CGPoint(x: x, y: y + size)
            CTLineDraw(line, ctx)
        }
        let pointsWide = CGFloat(width) / 2, pointsHigh = CGFloat(height) / 2
        fill(CGRect(x: 0, y: 0, width: pointsWide, height: pointsHigh), gray: 0.97)
        fill(CGRect(x: 0, y: 0, width: pointsWide, height: 44), gray: 0.90)
        for (i, color) in [CGColor(red: 1, green: 0.27, blue: 0.23, alpha: 1), CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1), CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)].enumerated() {
            ctx.setFillColor(color); ctx.fillEllipse(in: CGRect(x: 16 + i * 22, y: 15, width: 13, height: 13))
        }
        text("Fabrikam Billing", 540, 13, size: 14, bold: true)
        fill(CGRect(x: 0, y: 44, width: 220, height: pointsHigh - 44), gray: 0.93)
        for (i, item) in ["Dashboard", "Invoices", "Customers", "Payments", "Reports", "Settings"].enumerated() {
            if i == 1 { fill(CGRect(x: 10, y: 66 + i * 36, width: 200, height: 30), color: CGColor(red: 0.8, green: 0.86, blue: 0.95, alpha: 1)) }
            text(item, 28, CGFloat(73 + i * 36), size: 14, bold: i == 1)
        }
        text("Invoice #2026-0142", 260, 70, size: 26, bold: true)
        text("Customer: Contoso Ltd", 260, 116, size: 15)
        text("Contact: Alex Example, alex@example.com", 260, 142, size: 15)
        text("IBAN: DE89 3704 0044 0532 0130 00", 260, 168, size: 15)
        text("Card: 4111 1111 1111 1111", 260, 194, size: 15)
        text("Phone: +49 30 1234567", 260, 220, size: 15)
        text("Portal: https://contoso.example/billing", 760, 168, size: 15)
        text("Server: 192.168.0.12", 760, 194, size: 15)
        fill(CGRect(x: 260, y: 250, width: 960, height: 36), gray: 0.86)
        for (i, head) in ["Item", "Qty", "Price", "Total"].enumerated() { text(head, CGFloat(276 + i * 230), 259, size: 13, bold: true) }
        for row in 0..<6 {
            let y = CGFloat(296 + row * 44)
            fill(CGRect(x: 260, y: y, width: 960, height: 40), gray: row % 2 == 0 ? 1 : 0.985)
            text("Consulting package \(row + 1)", 276, y + 11, size: 14)
            text("\(row + 1)", 506, y + 11, size: 14)
            text("€ \(120 + row * 15).00", 736, y + 11, size: 14)
            text("€ \((120 + row * 15) * (row + 1)).00", 966, y + 11, size: 14)
        }
        fill(CGRect(x: 1020, y: 590, width: 200, height: 44), color: CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1))
        text("Mark as paid", 1060, 603, size: 15, bold: true, gray: 1)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(Data("https://contoso.example/pay/2026-0142".utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage?.samplingNearest().transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
               let qr = CIContext().createCGImage(output, from: output.extent) {
                fill(CGRect(x: 1066, y: 58, width: 140, height: 140), gray: 1)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: 188 + 68); ctx.scaleBy(x: 1, y: -1)           // CGContext.draw puts images upright in a y-up space
                ctx.draw(qr, in: CGRect(x: 1076, y: 68, width: 120, height: 120).applying(CGAffineTransform(translationX: 0, y: 0)))
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }

    /// A picture full of lines of text, with a QR code, `width` × `height` pixels.
    nonisolated static func makeLinesImage(width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let large = height >= 800
        if large {
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 0, y: CGFloat(height) - 88, width: CGFloat(width), height: 88))
        }

        // Lines of text in 28 px type (14 pt on a Retina screen), in as many columns as the picture is wide.
        let font = CTFontCreateUIFontForLanguage(.system, 28, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let columnWidth: CGFloat = 1300
        let columns = max(1, Int(CGFloat(width - 80) / columnWidth))
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 0.1, alpha: 1)]
        var index = 0
        for column in 0..<columns {
            var y = CGFloat(height) - (large ? 150 : 60)
            while y > (large ? 60 : 20) {
                let line = NSAttributedString(string: lines[index % lines.count], attributes: attributes)
                ctx.textPosition = CGPoint(x: 60 + CGFloat(column) * columnWidth, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(line), ctx)
                y -= 56
                index += 1
            }
        }

        // A QR code in the top right corner.
        if large, let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(Data("https://contoso.example/pay/2026-0142".utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage?.samplingNearest().transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
               let qr = CIContext().createCGImage(output, from: output.extent) {
                let side = CGFloat(qr.width)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: CGFloat(width) - side - 100, y: CGFloat(height) - side - 140, width: side + 40, height: side + 40))
                ctx.draw(qr, in: CGRect(x: CGFloat(width) - side - 80, y: CGFloat(height) - side - 120, width: side, height: side))
            }
        }
        return ctx.makeImage()
    }
}
