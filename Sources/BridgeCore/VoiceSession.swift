import Foundation

public struct VoiceSession {
  public private(set) var restoreTargetID: String?
  public private(set) var sawRecording = false
  public private(set) var audioStoppedAt: Date?
  public private(set) var audioBecameActiveAt: Date?

  public init() {}

  public var isActive: Bool {
    restoreTargetID != nil
  }

  public mutating func begin(targetID: String) {
    restoreTargetID = targetID
    sawRecording = false
    audioStoppedAt = nil
    audioBecameActiveAt = nil
  }

  public mutating func cancel() {
    restoreTargetID = nil
    sawRecording = false
    audioStoppedAt = nil
    audioBecameActiveAt = nil
  }

  public mutating func observeAudio(
    active: Bool?,
    at date: Date,
    gracePeriod: TimeInterval,
    recordingConfirmationPeriod: TimeInterval = 0
  ) -> Bool {
    guard isActive, let active else {
      return false
    }

    if active {
      audioStoppedAt = nil
      if audioBecameActiveAt == nil {
        audioBecameActiveAt = date
      }
      if let audioBecameActiveAt,
        date.timeIntervalSince(audioBecameActiveAt) >= recordingConfirmationPeriod
      {
        sawRecording = true
      }
      return false
    }

    audioBecameActiveAt = nil
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
