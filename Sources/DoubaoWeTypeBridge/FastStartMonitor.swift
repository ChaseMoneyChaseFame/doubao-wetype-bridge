import CoreGraphics
import Foundation

struct VoiceShortcut: Equatable {
  let keyCode: Int64
  let modifierFlags: CGEventFlags
  let modifierOnly: Bool
}

/// Listens only for an explicitly configured Doubao shortcut.
/// The bridge deliberately stays inactive when Doubao's setting cannot be read.
final class FastStartMonitor {
  private let shortcut: VoiceShortcut?
  private let onVoiceShortcut: () -> Void
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var shortcutIsDown = false

  init(shortcut: VoiceShortcut? = nil, onVoiceShortcut: @escaping () -> Void) {
    self.shortcut = shortcut
    self.onVoiceShortcut = onVoiceShortcut
  }

  deinit {
    stop()
  }

  var isConfigured: Bool {
    shortcut != nil
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
    guard let shortcut else {
      RuntimeLog.shared.write("fast start disabled; Doubao voice shortcut is unknown")
      return
    }
    guard isAuthorized else {
      RuntimeLog.shared.write("fast start unavailable; input monitoring permission required")
      return
    }

    let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
    let eventMask = shortcut.modifierOnly ? flagsChangedMask : flagsChangedMask | keyDownMask
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
    RuntimeLog.shared.write("fast start monitor active; shortcut explicitly configured")
  }

  func stop() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
    shortcutIsDown = false
  }

  fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      shortcutIsDown = false
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
        RuntimeLog.shared.write("fast start monitor reenabled")
      }
      return
    }

    guard let shortcut else {
      return
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard keyCode == shortcut.keyCode else {
      return
    }

    if shortcut.modifierOnly {
      guard type == .flagsChanged else {
        return
      }
      let isDown = event.flags.contains(shortcut.modifierFlags)
      let wasDown = shortcutIsDown
      shortcutIsDown = isDown
      guard isDown, !wasDown else {
        return
      }
    } else {
      guard type == .keyDown, event.flags.contains(shortcut.modifierFlags) else {
        return
      }
    }

    DispatchQueue.main.async { [onVoiceShortcut] in
      onVoiceShortcut()
    }
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
