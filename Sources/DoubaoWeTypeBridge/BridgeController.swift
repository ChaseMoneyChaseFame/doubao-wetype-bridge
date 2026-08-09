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
  private lazy var fastStartMonitor = FastStartMonitor { [weak self] in
    self?.handleFastStartRightOption()
  }

  private var timer: Timer?
  private var lastSourceID = ""
  private var lastAudioState: Bool?
  private var session = VoiceSession()
  private var lastFastStartRetryAt = Date.distantPast

  var statusDidChange: ((BridgeStatus) -> Void)?

  init(
    inputSources: InputSourceController = InputSourceController(),
    audioMonitor: AudioInputMonitor = AudioInputMonitor(),
    gracePeriod: TimeInterval = 0.6
  ) {
    self.inputSources = inputSources
    self.audioMonitor = audioMonitor
    self.gracePeriod = gracePeriod
  }

  deinit {
    stop()
  }

  func start() {
    guard timer == nil else {
      return
    }

    lastSourceID = inputSources.currentID()
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
    fastStartMonitor.isAuthorized
  }

  func requestFastStartAuthorization() {
    fastStartMonitor.requestAuthorization()
  }

  func restoreImmediately() {
    if inputSources.selectWeType() {
      session.cancel()
      setStatus(.restored)
      RuntimeLog.shared.write("manual restore succeeded")
    } else {
      setStatus(.restoreFailed)
      RuntimeLog.shared.write("manual restore failed")
    }
  }

  private func poll() {
    let sourceID = inputSources.currentID()
    if sourceID != lastSourceID {
      handleSourceChange(from: lastSourceID, to: sourceID)
      lastSourceID = sourceID
    }

    pollAudioState(sourceID: sourceID)

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

    if previousID.hasPrefix(InputSourceController.weTypeInputSourcePrefix),
      sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix)
    {
      session.begin(targetID: previousID)
      lastAudioState = nil
      setStatus(.waitingForRecording)
      RuntimeLog.shared.write("voice session started; target=\(previousID)")
    } else if !sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix) {
      session.cancel()
      lastAudioState = nil
      setStatus(.waiting)
    }
  }

  private func pollAudioState(sourceID: String) {
    guard session.isActive, sourceID.hasPrefix(InputSourceController.doubaoInputSourcePrefix) else {
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

    guard inputSources.currentID().hasPrefix(InputSourceController.doubaoInputSourcePrefix) else {
      session.cancel()
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
    lastAudioState = nil
  }

  private func handleFastStartRightOption() {
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
