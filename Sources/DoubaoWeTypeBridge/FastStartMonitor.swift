import ApplicationServices
import CoreGraphics
import Foundation

struct VoiceShortcut: Codable, Equatable {
  let keyCode: Int64
  let modifierFlagsRawValue: UInt64
  let modifierOnly: Bool
  let displayName: String

  var modifierFlags: CGEventFlags {
    CGEventFlags(rawValue: modifierFlagsRawValue)
  }
}

enum VoiceShortcutStore {
  private static let preferenceKey = "doubaoVoiceShortcut"

  static func load() -> VoiceShortcut? {
    guard let data = UserDefaults.standard.data(forKey: preferenceKey) else {
      return nil
    }
    return try? JSONDecoder().decode(VoiceShortcut.self, from: data)
  }

  static func save(_ shortcut: VoiceShortcut?) {
    guard let shortcut, let data = try? JSONEncoder().encode(shortcut) else {
      UserDefaults.standard.removeObject(forKey: preferenceKey)
      return
    }
    UserDefaults.standard.set(data, forKey: preferenceKey)
  }
}

/// Listens only for the shortcut explicitly captured in the bridge settings.
final class FastStartMonitor {
  private static let forwardedEventMarker: Int64 = 0x44425754
  private static let relevantModifierFlags: CGEventFlags = [
    .maskCommand,
    .maskAlternate,
    .maskControl,
    .maskShift,
    .maskSecondaryFn,
  ]

  private(set) var shortcut: VoiceShortcut?
  private let onVoiceShortcut: () -> Bool
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var shortcutIsDown = false
  private var suppressShortcutUntilRelease = false
  private var isCaptureSuspended = false
  private var shortcutCaptureHandler: ((CGEventType, Int64, CGEventFlags) -> Void)?

  init(shortcut: VoiceShortcut? = nil, onVoiceShortcut: @escaping () -> Bool) {
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

  var isAutomationAuthorized: Bool {
    AXIsProcessTrusted()
  }

  var isRunning: Bool {
    eventTap != nil
  }

  func requestAuthorization() {
    _ = CGRequestListenEventAccess()
  }

  func requestAutomationAuthorization() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  func updateShortcut(_ shortcut: VoiceShortcut?) {
    guard self.shortcut != shortcut else {
      return
    }
    stop()
    self.shortcut = shortcut
    VoiceShortcutStore.save(shortcut)
    start()
  }

  func setCaptureSuspended(_ suspended: Bool) {
    isCaptureSuspended = suspended
    shortcutIsDown = false
    suppressShortcutUntilRelease = false
  }

  @discardableResult
  func setShortcutCaptureHandler(
    _ handler: ((CGEventType, Int64, CGEventFlags) -> Void)?
  ) -> Bool {
    shortcutCaptureHandler = handler
    return eventTap != nil
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
    guard isAutomationAuthorized else {
      RuntimeLog.shared.write("fast start unavailable; accessibility permission required")
      return
    }

    let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
    let keyUpMask = CGEventMask(1) << CGEventType.keyUp.rawValue
    let eventMask = flagsChangedMask | keyDownMask | keyUpMask
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
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
    RuntimeLog.shared.write(
      "fast start monitor active; shortcut=\(shortcut.displayName); keyCode=\(shortcut.keyCode)"
    )
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
    suppressShortcutUntilRelease = false
  }

  /// Returns true when the physical event must be suppressed.
  fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      shortcutIsDown = false
      suppressShortcutUntilRelease = false
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
        RuntimeLog.shared.write("fast start monitor reenabled")
      }
      return false
    }

    if event.getIntegerValueField(.eventSourceUserData) == Self.forwardedEventMarker {
      return false
    }

    if let shortcutCaptureHandler {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      shortcutCaptureHandler(type, keyCode, event.flags)
    }

    guard let shortcut else {
      return false
    }
    guard !isCaptureSuspended else {
      return false
    }

    let currentModifierFlags = event.flags.intersection(Self.relevantModifierFlags)

    if shortcut.modifierOnly {
      guard type == .flagsChanged else {
        return false
      }
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      guard keyCode == shortcut.keyCode else {
        return false
      }
      let isDown = currentModifierFlags == shortcut.modifierFlags
      let wasDown = shortcutIsDown
      if isDown {
        if !wasDown {
          shortcutIsDown = true
          suppressShortcutUntilRelease = dispatchVoiceShortcut(phase: "modifierDown")
        }
        return suppressShortcutUntilRelease
      }
      shortcutIsDown = false
      let shouldSuppress = suppressShortcutUntilRelease
      suppressShortcutUntilRelease = false
      return shouldSuppress
    } else {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      guard keyCode == shortcut.keyCode else {
        return false
      }
      if type == .keyUp {
        let shouldSuppress = suppressShortcutUntilRelease
        suppressShortcutUntilRelease = false
        return shouldSuppress
      }
      guard type == .keyDown, currentModifierFlags == shortcut.modifierFlags else {
        return false
      }
      if !suppressShortcutUntilRelease {
        suppressShortcutUntilRelease = dispatchVoiceShortcut(phase: "keyDown")
      }
      return suppressShortcutUntilRelease
    }
  }

  private func dispatchVoiceShortcut(phase: String) -> Bool {
    RuntimeLog.shared.write("fast start shortcut detected; phase=\(phase)")
    guard onVoiceShortcut() else {
      return false
    }
    let forwardedShortcut = shortcut
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
      guard let self, let forwardedShortcut else {
        return
      }
      if self.post(shortcut: forwardedShortcut) {
        RuntimeLog.shared.write("fast start forwarded voice shortcut")
      } else {
        RuntimeLog.shared.write("fast start failed to forward voice shortcut")
      }
    }
    return true
  }

  private func post(shortcut: VoiceShortcut) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
      return false
    }
    guard
      let down = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(shortcut.keyCode),
        keyDown: true
      ),
      let up = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(shortcut.keyCode),
        keyDown: false
      )
    else {
      return false
    }

    down.setIntegerValueField(.eventSourceUserData, value: Self.forwardedEventMarker)
    up.setIntegerValueField(.eventSourceUserData, value: Self.forwardedEventMarker)
    down.flags = shortcut.modifierFlags
    up.flags = shortcut.modifierOnly ? [] : shortcut.modifierFlags
    if shortcut.modifierOnly {
      down.type = .flagsChanged
      up.type = .flagsChanged
    }

    down.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
      up.post(tap: .cghidEventTap)
    }
    return true
  }
}

private let fastStartEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }

  let monitor = Unmanaged<FastStartMonitor>.fromOpaque(userInfo).takeUnretainedValue()
  if monitor.handleEvent(type: type, event: event) {
    return nil
  }
  return Unmanaged.passUnretained(event)
}
