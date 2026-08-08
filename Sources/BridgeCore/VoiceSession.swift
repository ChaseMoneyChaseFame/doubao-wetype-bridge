import Foundation

public struct VoiceSession {
  public private(set) var restoreTargetID: String?
  public private(set) var sawRecording = false
  public private(set) var audioStoppedAt: Date?

  public init() {}

  public var isActive: Bool {
    restoreTargetID != nil
  }

  public mutating func begin(targetID: String) {
    restoreTargetID = targetID
    sawRecording = false
    audioStoppedAt = nil
  }

  public mutating func cancel() {
    restoreTargetID = nil
    sawRecording = false
    audioStoppedAt = nil
  }

  public mutating func observeAudio(
    active: Bool?,
    at date: Date,
    gracePeriod: TimeInterval
  ) -> Bool {
    guard isActive, let active else {
      return false
    }

    if active {
      sawRecording = true
      audioStoppedAt = nil
      return false
    }

    guard sawRecording else {
      return false
    }

    if audioStoppedAt == nil {
      audioStoppedAt = date
      return false
    }

    return date.timeIntervalSince(audioStoppedAt!) >= gracePeriod
  }
}
