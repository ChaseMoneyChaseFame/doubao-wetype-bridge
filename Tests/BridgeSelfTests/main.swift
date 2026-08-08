import BridgeCore
import Foundation

private var failureCount = 0

private func expect(
  _ condition: @autoclosure () -> Bool,
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  guard !condition() else {
    return
  }
  failureCount += 1
  fputs("FAIL: \(message) (\(file):\(line))\n", stderr)
}

let start = Date(timeIntervalSince1970: 1_000)
let grace: TimeInterval = 0.6

do {
  var session = VoiceSession()
  session.begin(targetID: "wechat")
  expect(
    !session.observeAudio(active: false, at: start, gracePeriod: grace), "must wait for recording")
  expect(
    !session.observeAudio(active: false, at: start.addingTimeInterval(10), gracePeriod: grace),
    "idle must not restore")
}

do {
  var session = VoiceSession()
  session.begin(targetID: "wechat")
  for second in 0...120 {
    expect(
      !session.observeAudio(
        active: true, at: start.addingTimeInterval(TimeInterval(second)), gracePeriod: grace),
      "active recording must never restore"
    )
  }
}

do {
  var session = VoiceSession()
  session.begin(targetID: "wechat")
  expect(!session.observeAudio(active: true, at: start, gracePeriod: grace), "recording start")
  expect(
    !session.observeAudio(active: false, at: start.addingTimeInterval(5), gracePeriod: grace),
    "stop edge")
  expect(
    !session.observeAudio(active: false, at: start.addingTimeInterval(5.59), gracePeriod: grace),
    "grace period")
  expect(
    session.observeAudio(active: false, at: start.addingTimeInterval(5.6), gracePeriod: grace),
    "restore after grace")
}

do {
  var session = VoiceSession()
  session.begin(targetID: "wechat")
  _ = session.observeAudio(active: true, at: start, gracePeriod: grace)
  _ = session.observeAudio(active: false, at: start.addingTimeInterval(5), gracePeriod: grace)
  expect(
    !session.observeAudio(active: true, at: start.addingTimeInterval(5.3), gracePeriod: grace),
    "resume recording")
  expect(session.audioStoppedAt == nil, "resume must clear stop timestamp")
}

do {
  var session = VoiceSession()
  session.begin(targetID: "wechat")
  expect(!session.observeAudio(active: true, at: start, gracePeriod: grace), "first press starts recording")
  expect(
    !session.observeAudio(active: false, at: start.addingTimeInterval(8), gracePeriod: grace),
    "second press stops recording"
  )
  expect(
    session.observeAudio(active: false, at: start.addingTimeInterval(8.6), gracePeriod: grace),
    "second press restores WeType after commit grace"
  )
}

if failureCount > 0 {
  fputs("\(failureCount) self-test(s) failed\n", stderr)
  exit(1)
}

print("All BridgeCore self-tests passed")
