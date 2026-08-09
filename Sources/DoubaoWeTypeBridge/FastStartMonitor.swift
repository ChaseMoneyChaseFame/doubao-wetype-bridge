import CoreGraphics
import Foundation

/// Observes modifier-only shortcut candidates used by Doubao's global voice input.
/// Doubao exposes Command, Option, Control, Shift, Fn and modifier chords in its
/// settings, while the actual shortcut is handled by Doubao itself.
final class FastStartMonitor {
  private let onVoiceShortcut: () -> Void
  private let candidateDelay: TimeInterval
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var downModifierKeyCodes = Set<Int64>()
  private var candidateWorkItem: DispatchWorkItem?
  private var candidateGeneration = 0

  private static let modifierKeyCodes: Set<Int64> = [
    54, 55,  // right / left Command
    58, 61,  // right / left Option
    59, 62,  // right / left Control
    56, 60,  // right / left Shift
    63,  // Fn
  ]

  init(candidateDelay: TimeInterval = 0.018, onVoiceShortcut: @escaping () -> Void) {
    self.candidateDelay = candidateDelay
    self.onVoiceShortcut = onVoiceShortcut
  }

  deinit {
    stop()
  }

  var isAuthorized: Bool {
    CGPreflightListenEventAccess()
  }

  var isRunning: Bool {
    eventTap != nil
  }

  func requestAuthorization() {
    _ = CGRequestListenEventAccess()
  }

  func start() {
    guard eventTap == nil else {
      return
    }
    guard isAuthorized else {
      RuntimeLog.shared.write("fast start unavailable; input monitoring permission required")
      return
    }

    let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
    let eventMask = flagsChangedMask | keyDownMask
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: fastStartEventCallback,
        userInfo: pointer
      )
    else {
      RuntimeLog.shared.write("fast start unavailable; event tap creation failed")
      return
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      RuntimeLog.shared.write("fast start unavailable; run loop source creation failed")
      return
    }

    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    RuntimeLog.shared.write("fast start monitor active; shortcut=modifier candidate")
  }

  func stop() {
    cancelCandidate()
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
    downModifierKeyCodes.removeAll()
  }

  fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      cancelCandidate()
      downModifierKeyCodes.removeAll()
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
        RuntimeLog.shared.write("fast start monitor reenabled")
      }
      return
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    if type == .keyDown {
      // A regular Command/Option/Shift shortcut has a non-modifier key immediately
      // after the modifier. Cancel its pending voice candidate before it fires.
      if !Self.modifierKeyCodes.contains(keyCode) {
        cancelCandidate()
      }
      return
    }

    guard type == .flagsChanged, Self.modifierKeyCodes.contains(keyCode) else {
      return
    }

    let isDown = isModifierDown(keyCode: keyCode, flags: event.flags)
    if isDown {
      downModifierKeyCodes.insert(keyCode)
      scheduleCandidateIfNeeded()
    } else {
      downModifierKeyCodes.remove(keyCode)
    }
  }

  private func isModifierDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
    switch keyCode {
    case 54, 55:
      return flags.contains(.maskCommand)
    case 58, 61:
      return flags.contains(.maskAlternate)
    case 59, 62:
      return flags.contains(.maskControl)
    case 56, 60:
      return flags.contains(.maskShift)
    case 63:
      return flags.contains(.maskSecondaryFn)
    default:
      return false
    }
  }

  private func scheduleCandidateIfNeeded() {
    guard candidateWorkItem == nil else {
      return
    }

    candidateGeneration += 1
    let generation = candidateGeneration
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.candidateGeneration == generation else {
        return
      }
      self.candidateWorkItem = nil
      self.onVoiceShortcut()
    }
    candidateWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + candidateDelay, execute: workItem)
  }

  private func cancelCandidate() {
    candidateGeneration += 1
    candidateWorkItem?.cancel()
    candidateWorkItem = nil
  }
}

private let fastStartEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }

  let monitor = Unmanaged<FastStartMonitor>.fromOpaque(userInfo).takeUnretainedValue()
  monitor.handleEvent(type: type, event: event)
  return Unmanaged.passUnretained(event)
}
