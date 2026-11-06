import XCTest
@testable import WhiteShot

/// Vision's one-time preparation, done in the background before it is needed (see `VisionWarmUp`).
@MainActor
final class VisionWarmUpTests: XCTestCase {
    private func scratch() throws -> (UserDefaults, () -> Void) {
        let name = "me.fbrd.whiteshot.tests.warmup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    func testItIsNeededUntilItHasRunForThisVersionOfMacOS() throws {
        let (defaults, cleanUp) = try scratch()
        defer { cleanUp() }
        XCTAssertFalse(VisionWarmUp.osBuild.isEmpty, "the macOS build is how a new version of macOS is recognised")
        XCTAssertTrue(VisionWarmUp.isNeeded(defaults: defaults))
        defaults.set(VisionWarmUp.osBuild, forKey: VisionWarmUp.doneKey)
        XCTAssertFalse(VisionWarmUp.isNeeded(defaults: defaults))
        defaults.set("some older build", forKey: VisionWarmUp.doneKey)
        XCTAssertTrue(VisionWarmUp.isNeeded(defaults: defaults), "compiled models do not carry over to another macOS")
    }

    func testItWaitsForAGoodMoment() {
        XCTAssertTrue(VisionWarmUp.isGoodMoment(lowPowerMode: false, thermalState: .nominal))
        XCTAssertTrue(VisionWarmUp.isGoodMoment(lowPowerMode: false, thermalState: .fair))
        XCTAssertFalse(VisionWarmUp.isGoodMoment(lowPowerMode: true, thermalState: .nominal), "not while the Mac is saving power")
        XCTAssertFalse(VisionWarmUp.isGoodMoment(lowPowerMode: false, thermalState: .serious), "not while it is running hot")
        XCTAssertFalse(VisionWarmUp.isGoodMoment(lowPowerMode: false, thermalState: .critical))
    }

    func testResetLeavesItAlone() {
        XCTAssertFalse(Preferences.registeredDefaults.keys.contains(VisionWarmUp.doneKey), "it is state, not a setting")
        XCTAssertEqual(VisionWarmUp.helperFlag, "--warm-up-vision")
    }

    func testThePicturesStartSmallAndEndLarge() {
        let pictures = VisionWarmUp.pictures
        XCTAssertGreaterThanOrEqual(pictures.count, 3)
        XCTAssertLessThan(pictures[0].width * pictures[0].height, 300_000, "the first one pays for the base models; it should be cheap to make")
        XCTAssertGreaterThanOrEqual(pictures.map { $0.width * $0.height }.max() ?? 0, 15_000_000, "one covers a large display")
        XCTAssertTrue(pictures.contains { $0.kind == .screenshot }, "a window-like screenshot was what needed the extra preparation")
    }

    func testTheWarmUpPicturesAreRealSubjectsForTextRecognition() async throws {
        let lines = try XCTUnwrap(VisionWarmUp.makeImage(.lines, width: 600, height: 240))
        XCTAssertEqual(lines.width, 600); XCTAssertEqual(lines.height, 240)
        let linesResult = try await TextRecognizer.recognize(in: lines)
        XCTAssertFalse(linesResult.isEmpty, "there is text on it")

        let screenshot = try XCTUnwrap(VisionWarmUp.makeImage(.screenshot, width: 2560, height: 1600))
        XCTAssertEqual(screenshot.width, 2560); XCTAssertEqual(screenshot.height, 1600)
        let result = try await TextRecognizer.recognize(in: screenshot)
        let text = result.fullText
        XCTAssertTrue(text.contains("Invoice"), "the heading is there: \(text.prefix(200))")
        XCTAssertTrue(text.contains("alex@example.com") || text.contains("Contoso"), "so is the rest")
        XCTAssertEqual(result.codes.first?.payload, "https://contoso.example/pay/2026-0142", "and a QR code that can be read")
        XCTAssertFalse(SensitiveDetector.matches(in: result).isEmpty, "it contains the things the editor points out, so those paths get prepared too")
    }

    func testTheRecognitionBarSaysSomethingAfterAWhile() throws {
        let model = EditorModel(image: TestImage.solid(100, 100), scale: 1)
        XCTAssertNil(model.recognitionStartedAt)
        let generation = try XCTUnwrap(model.beginTextRecognition())
        XCTAssertNotNil(model.recognitionStartedAt, "so the bar can tell how long it has been")
        model.finishTextRecognition(.success(RecognizedText(lines: [])), generation: generation)
        XCTAssertNil(model.recognitionStartedAt)
        let other = EditorModel(image: TestImage.solid(100, 100), scale: 1)
        _ = try XCTUnwrap(other.beginTextRecognition())
        other.endTextRecognition()
        XCTAssertNil(other.recognitionStartedAt, "also when the user gives up before Vision has answered")
    }
}
