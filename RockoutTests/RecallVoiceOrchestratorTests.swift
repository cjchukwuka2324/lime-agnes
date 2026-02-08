import XCTest
@testable import Rockout

@MainActor
final class RecallVoiceOrchestratorTests: XCTestCase {

    var orchestrator: RecallVoiceOrchestrator!

    override func setUp() {
        super.setUp()
        orchestrator = RecallVoiceOrchestrator()
    }

    override func tearDown() {
        orchestrator = nil
        super.tearDown()
    }

    // MARK: - State Transitions

    func testInitialState() {
        XCTAssertEqual(orchestrator.currentState, .idle)
        XCTAssertFalse(orchestrator.isMuted)
    }

    func testUserTappedStartFromIdle() {
        orchestrator.handleEvent(.userTappedStart)
        XCTAssertEqual(orchestrator.currentState, .listening)
    }

    func testUserTappedStopFromListening() {
        orchestrator.handleEvent(.userTappedStart)
        XCTAssertEqual(orchestrator.currentState, .listening)
        orchestrator.handleEvent(.userTappedStop)
        XCTAssertEqual(orchestrator.currentState, .idle)
    }

    func testUserTappedMuteSetsMuted() {
        orchestrator.handleEvent(.userTappedMute)
        XCTAssertTrue(orchestrator.isMuted)
    }

    func testUserTappedUnmuteClearsMuted() {
        orchestrator.handleEvent(.userTappedMute)
        orchestrator.handleEvent(.userTappedUnmute)
        XCTAssertFalse(orchestrator.isMuted)
    }

    func testVadSpeechStartFromListening() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.handleEvent(.vadSpeechStart)
        XCTAssertEqual(orchestrator.currentState, .capturingUtterance)
    }

    func testVadSpeechEndFromCapturing() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.handleEvent(.vadSpeechStart)
        orchestrator.handleEvent(.vadSpeechEnd)
        XCTAssertEqual(orchestrator.currentState, .classifyingAudio)
    }

    func testSttPartialUpdatesLiveTranscript() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.handleEvent(.vadSpeechStart)
        orchestrator.handleEvent(.vadSpeechEnd)
        orchestrator.handleEvent(.audioClassified(.speech))
        orchestrator.handleEvent(.sttPartial("hello"))
        XCTAssertEqual(orchestrator.liveTranscript, "hello")
    }

    func testSttFinalTransitionsToThinking() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.handleEvent(.vadSpeechStart)
        orchestrator.handleEvent(.vadSpeechEnd)
        orchestrator.handleEvent(.audioClassified(.speech))
        orchestrator.handleEvent(.sttFinal("what song is this"))
        XCTAssertEqual(orchestrator.currentState, .thinking)
        XCTAssertEqual(orchestrator.finalTranscript, "what song is this")
    }

    func testResetClearsState() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.reset()
        XCTAssertEqual(orchestrator.currentState, .idle)
        XCTAssertNil(orchestrator.lastError)
    }

    func testErrorOccurredTransitionsToError() {
        orchestrator.handleEvent(.userTappedStart)
        orchestrator.handleEvent(.errorOccurred(NSError(domain: "Test", code: -1, userInfo: nil)))
        XCTAssertEqual(orchestrator.currentState, .error)
    }

    func testRecoveredFromError() {
        orchestrator.handleEvent(.errorOccurred(NSError(domain: "Test", code: -1, userInfo: nil)))
        orchestrator.handleEvent(.recovered)
        XCTAssertEqual(orchestrator.currentState, .idle)
    }
}
