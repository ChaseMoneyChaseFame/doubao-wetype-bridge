import BridgeCore
import Foundation
import XCTest

final class VoiceSessionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000)
  private let gracePeriod: TimeInterval = 0.6

  func testDoesNotRestoreBeforeRecordingStarts() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")
    XCTAssertFalse(session.observeAudio(active: false, at: start, gracePeriod: gracePeriod))
    XCTAssertFalse(
      session.observeAudio(
        active: false, at: start.addingTimeInterval(10), gracePeriod: gracePeriod))
  }

  func testDoesNotRestoreWhileRecordingContinues() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")
    for second in 0...120 {
      XCTAssertFalse(
        session.observeAudio(
          active: true,
          at: start.addingTimeInterval(TimeInterval(second)),
          gracePeriod: gracePeriod
        )
      )
    }
  }

  func testRestoresOnlyAfterAudioStopsForGracePeriod() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")
    XCTAssertFalse(session.observeAudio(active: true, at: start, gracePeriod: gracePeriod))
    XCTAssertFalse(
      session.observeAudio(active: false, at: start.addingTimeInterval(5), gracePeriod: gracePeriod)
    )
    XCTAssertFalse(
      session.observeAudio(
        active: false, at: start.addingTimeInterval(5.59), gracePeriod: gracePeriod))
    XCTAssertTrue(
      session.observeAudio(
        active: false, at: start.addingTimeInterval(5.6), gracePeriod: gracePeriod))
  }

  func testRecordingResumeCancelsPendingRestore() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")
    XCTAssertFalse(session.observeAudio(active: true, at: start, gracePeriod: gracePeriod))
    XCTAssertFalse(
      session.observeAudio(active: false, at: start.addingTimeInterval(5), gracePeriod: gracePeriod)
    )
    XCTAssertFalse(
      session.observeAudio(
        active: true, at: start.addingTimeInterval(5.3), gracePeriod: gracePeriod))
    XCTAssertNil(session.audioStoppedAt)
    XCTAssertFalse(
      session.observeAudio(active: false, at: start.addingTimeInterval(6), gracePeriod: gracePeriod)
    )
    XCTAssertTrue(
      session.observeAudio(
        active: false, at: start.addingTimeInterval(6.6), gracePeriod: gracePeriod))
  }

  func testTwoPressWorkflowRestoresAfterSecondPressStopsRecording() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")
    XCTAssertFalse(session.observeAudio(active: true, at: start, gracePeriod: gracePeriod))
    XCTAssertFalse(
      session.observeAudio(active: false, at: start.addingTimeInterval(8), gracePeriod: gracePeriod)
    )
    XCTAssertTrue(
      session.observeAudio(
        active: false, at: start.addingTimeInterval(8.6), gracePeriod: gracePeriod))
  }

  func testBriefAudioPulseDoesNotConfirmRecording() {
    var session = VoiceSession()
    session.begin(targetID: "wechat")

    XCTAssertFalse(
      session.observeAudio(
        active: true,
        at: start,
        gracePeriod: gracePeriod,
        recordingConfirmationPeriod: 0.2
      )
    )
    XCTAssertFalse(
      session.observeAudio(
        active: false,
        at: start.addingTimeInterval(0.05),
        gracePeriod: gracePeriod,
        recordingConfirmationPeriod: 0.2
      )
    )
    XCTAssertFalse(session.sawRecording)
    XCTAssertNil(session.audioStoppedAt)
  }
}
