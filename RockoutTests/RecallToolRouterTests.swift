import XCTest
@testable import Rockout

@MainActor
final class RecallToolRouterTests: XCTestCase {
    var router: RecallToolRouter!

    override func setUp() {
        super.setUp()
        router = RecallToolRouter.shared
    }

    override func tearDown() {
        router = nil
        super.tearDown()
    }

    // MARK: - Router Errors

    func testEmptyTranscriptThrows() async {
        do {
            _ = try await router.resolve(
                threadId: UUID(),
                messageId: UUID(),
                audioType: .speech,
                text: "   ",
                mediaPath: nil
            )
            XCTFail("Expected emptyTranscript error")
        } catch let error as RecallToolRouterError {
            if case .emptyTranscript = error { } else {
                XCTFail("Expected emptyTranscript, got \(error)")
            }
        } catch {
            XCTFail("Expected RecallToolRouterError, got \(error)")
        }
    }

    func testMissingMediaPathForMusicThrows() async {
        do {
            _ = try await router.resolve(
                threadId: UUID(),
                messageId: UUID(),
                audioType: .music,
                text: nil,
                mediaPath: nil
            )
            XCTFail("Expected missingMediaPath error")
        } catch let error as RecallToolRouterError {
            if case .missingMediaPath = error { } else {
                XCTFail("Expected missingMediaPath, got \(error)")
            }
        } catch {
            XCTFail("Expected RecallToolRouterError, got \(error)")
        }
    }

    func testNoiseClassificationThrows() async {
        do {
            _ = try await router.resolve(
                threadId: UUID(),
                messageId: UUID(),
                audioType: .noise,
                text: nil,
                mediaPath: nil
            )
            XCTFail("Expected noiseIgnored error")
        } catch let error as RecallToolRouterError {
            if case .noiseIgnored = error { } else {
                XCTFail("Expected noiseIgnored, got \(error)")
            }
        } catch {
            XCTFail("Expected RecallToolRouterError, got \(error)")
        }
    }

    func testRecallToolRouterErrorDescriptions() {
        XCTAssertNotNil(RecallToolRouterError.emptyTranscript.errorDescription)
        XCTAssertNotNil(RecallToolRouterError.missingMediaPath.errorDescription)
        XCTAssertNotNil(RecallToolRouterError.noiseIgnored.errorDescription)
    }
}
