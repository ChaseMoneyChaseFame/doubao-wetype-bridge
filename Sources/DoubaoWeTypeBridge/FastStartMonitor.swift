import CoreGraphics
import Foundation

/// Listens only for right Option so the bridge can select Doubao immediately
/// after the key event has reached Doubao's own global voice shortcut.
final class FastStartMonitor {
  private let onRightOptionDown: () -> Void
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var rightOptionIsDown = false

  init(onRightOptionDown: @escaping () -> Void) {
    self.onRightOptionDown = onRightOptionDown
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

    let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
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
    RuntimeLog.shared.write("fast start monitor active")
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
    rightOptionIsDown = false
  }

  fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      rightOptionIsDown = false
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
        RuntimeLog.shared.write("fast start monitor reenabled")
      }
      return
    }

    guard
      type == .flagsChanged,
      event.getIntegerValueField(.keyboardEventKeycode) == 61
    else {
      return
    }

    let isDown = event.flags.contains(.maskAlternate)
    let wasDown = rightOptionIsDown
    rightOptionIsDown = isDown
    guard isDown, !wasDown else {
      return
    }

    // Do this after returning from the event tap callback. Doubao receives
    // the same key event first and remains responsible for toggling voice.
    DispatchQueue.main.async { [onRightOptionDown] in
      onRightOptionDown()
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
