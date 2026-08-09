import AppKit
import BridgeCore
import CoreGraphics
import Foundation

enum BridgeStatus: Equatable {
  case waiting
  case waitingForRecording
  case recording
  case waitingForCommit
  case restored
  case audioStateUnavailable
  case restoreFailed

  var title: String {
    switch self {
    case .waiting:
      "等待豆包语音"
    case .waitingForRecording:
      "等待豆包开始录音"
    case .recording:
      "豆包语音输入中"
    case .waitingForCommit:
      "语音已结束，等待提交"
    case .restored:
      "已恢复微信输入法"
    case .audioStateUnavailable:
      "无法读取豆包录音状态"
    case .restoreFailed:
      "恢复微信输入法失败"
    }
  }
}

final class BridgeController: @unchecked Sendable {
  private let inputSources: InputSourceController
  private let audioMonitor: AudioInputMonitor
  private let gracePeriod: TimeInterval
  private let sourceHandoffTimeout: TimeInterval
  private lazy var fastStartMonitor = FastStartMonitor(
    shortcut: VoiceShortcutStore.load()
  ) { [weak self] in
    self?.handleFastStartVoiceShortcut()
  }

  private var timer: Timer?
  private var lastSourceID = ""
  private var lastAudioState: Bool?
  private var session = VoiceSession()
  private var sessionDetachedAt: Date?
  private var pendingTargetID: String?
  private var pendingTargetExpiresAt: Date?
  private var lastFastStartRetryAt = Date.distantPast

  var statusDidChange: ((BridgeStatus) -> Void)?

  init(
    inputSources: InputSourceController = InputSourceController(),
    audioMonitor: AudioInputMonitor = AudioInputMonitor(),
    gracePeriod: TimeInterval = 0.6,
    sourceHandoffTimeout: TimeInterval = 1.5
  ) {
    self.inputSources = inputSources
    self.audioMonitor = audioMonitor
    self.gracePeriod = gracePeriod
    self.sourceHandoffTimeout = sourceHandoffTimeout
  }

  deinit {
    stop()
  }

  func start() {
    guard timer == nil else {
      return
    }

    lastSourceID = inputSources.currentID()
    session.cancel()
    sessionDetachedAt = nil
    clearPendingTarget()
    setStatus(.waiting)
    RuntimeLog.shared.write("application launched; inputSource=\(lastSourceID); detector=CoreAudio")
    fastStartMonitor.start()

    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.poll()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    fastStartMonitor.stop()
  }

  func refreshFastStartMonitor() {
    fastStartMonitor.stop()
    fastStartMonitor.start()
  }

  var fastStartAuthorized: Bool {
    fastStartMonitor.isAuthorized || fastStartMonitor.isRunning
  }

  var fastStartConfigured: Bool {
    fastStartMonitor.isConfigured
  }

  var fastStartShortcut: VoiceShortcut? {
    fastStartMonitor.shortcut
  }

  func setFastStartShortcut(_ shortcut: VoiceShortcut) {
    fastStartMonitor.updateShortcut(shortcut)
  }

  func requestFastStartAuthorization() {
    fastStartMonitor.requestAuthorization()
  }

  func restoreImmediately() {
    session.cancel()
    sessionDetachedAt = nil
    clearPendingTarget()
    if inputSources.selectWeType() {
      setStatus(.restored)
      RuntimeLog.shared.write("manual restore succeeded")
    } else {
      setStatus(.restoreFailed)
      RuntimeLog.shared.write("manual restore failed")
    }
  }

  private func poll() {
    expirePendingTargetIfNeeded(at: Date())
    let sourceID = inputSources.currentID()
    if sourceID != lastSourceID {
      handleSourceChange(from: lastSourceID, to: sourceID)
      lastSourceID = sourceID
    }

    expireUnrecordedSessionIfNeeded(sourceID: sourceID, at: Date())
    pollPendingHandoff(sourceID: sourceID)
    pollAudioState()

    if !fastStartMonitor.isRunning,
      fastStartMonitor.isAuthorized,
      Date().timeIntervalSince(lastFastStartRetryAt) >= 2
    {
      lastFastStartRetryAt = Date()
      fastStartMonitor.start()
    }
  }

  private func handleSourceChange(from previousID: String, to sourceID: String) {
    RuntimeLog.shared.write("input source changed; from=\(previousID); to=\(sourceID)")

    let isDoubao = sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix)
    let wasWeType = previousID.hasPrefix(InputSourceController.weTypeInputSourcePrefix)

    if isDoubao {
      if session.isActive {
        sessionDetachedAt = nil
        return
      }

      let targetID: String?
      if wasWeType {
        targetID = previousID
      } else if isPendingTargetValid(at: Date()) {
        targetID = pendingTargetID
      } else {
        targetID = nil
      }

      guard let targetID else {
        return
      }

      session.begin(targetID: targetID)
      sessionDetachedAt = nil
      clearPendingTarget()
      lastAudioState = nil
      setStatus(.waitingForRecording)
      RuntimeLog.shared.write(
        "voice session started; target=\(targetID); reason=input source handoff"
      )
      return
    }

    if session.isActive {
      if !session.sawRecording {
        sessionDetachedAt = sessionDetachedAt ?? Date()
      }
      RuntimeLog.shared.write(
        "voice session retained across input source change; source=\(sourceID)"
      )
      return
    }

    if wasWeType {
      pendingTargetID = previousID
      pendingTargetExpiresAt = Date().addingTimeInterval(sourceHandoffTimeout)
      RuntimeLog.shared.write(
        "input source handoff pending; target=\(previousID); timeout=\(sourceHandoffTimeout)"
      )
      setStatus(.waiting)
    } else if pendingTargetID == nil {
      setStatus(.waiting)
    }
  }

  private func isPendingTargetValid(at date: Date) -> Bool {
    guard pendingTargetID != nil, let expiresAt = pendingTargetExpiresAt else {
      return false
    }
    return date < expiresAt
  }

  private func expirePendingTargetIfNeeded(at date: Date) {
    guard pendingTargetID != nil, !isPendingTargetValid(at: date) else {
      return
    }
    RuntimeLog.shared.write("input source handoff expired")
    clearPendingTarget()
  }

  private func clearPendingTarget() {
    pendingTargetID = nil
    pendingTargetExpiresAt = nil
  }

  private func expireUnrecordedSessionIfNeeded(sourceID: String, at date: Date) {
    guard
      session.isActive,
      !session.sawRecording,
      !sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix),
      let detachedAt = sessionDetachedAt,
      date.timeIntervalSince(detachedAt) >= sourceHandoffTimeout
    else {
      return
    }

    session.cancel()
    sessionDetachedAt = nil
    lastAudioState = nil
    setStatus(.waiting)
    RuntimeLog.shared.write("voice session expired before recording started")
  }

  private func pollPendingHandoff(sourceID: String) {
    guard
      !session.isActive,
      !sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix),
      isPendingTargetValid(at: Date()),
      let targetID = pendingTargetID,
      audioMonitor.doubaoIsUsingAudioInput() == true,
      inputSources.selectFirstDoubao()
    else {
      return
    }

    session.begin(targetID: targetID)
    sessionDetachedAt = nil
    clearPendingTarget()
    lastAudioState = nil
    setStatus(.waitingForRecording)
    RuntimeLog.shared.write(
      "voice session started; target=\(targetID); reason=doubao audio detected during handoff"
    )
  }

  private func pollAudioState() {
    guard session.isActive else {
      return
    }

    let audioState = audioMonitor.doubaoIsUsingAudioInput()
    if audioState != lastAudioState {
      RuntimeLog.shared.write(
        "doubao audio input changed; active=\(String(describing: audioState))")
      lastAudioState = audioState
    }

    if audioState == nil {
      setStatus(.audioStateUnavailable)
      return
    }

    if audioState == true {
      setStatus(.recording)
    } else if session.sawRecording {
      setStatus(.waitingForCommit)
    }

    if session.observeAudio(active: audioState, at: Date(), gracePeriod: gracePeriod) {
      restoreSessionTarget()
    }
  }

  private func restoreSessionTarget() {
    guard let targetID = session.restoreTargetID else {
      return
    }

    if inputSources.select(id: targetID) {
      setStatus(.restored)
      RuntimeLog.shared.write(
        "restored input source; target=\(targetID); reason=doubao stopped recording")
    } else {
      setStatus(.restoreFailed)
      RuntimeLog.shared.write("restore failed; target=\(targetID)")
    }
    session.cancel()
    sessionDetachedAt = nil
    lastAudioState = nil
  }

  private func handleFastStartVoiceShortcut() {
    guard inputSources.currentID().hasPrefix(InputSourceController.weTypeInputSourcePrefix) else {
      return
    }

    let startedAt = Date()
    if inputSources.selectFirstDoubao() {
      RuntimeLog.shared.write(
        "fast start selected doubao; elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
      )
    } else {
      RuntimeLog.shared.write("fast start failed to select doubao")
    }
  }

  private func setStatus(_ status: BridgeStatus) {
    statusDidChange?(status)
  }
}
