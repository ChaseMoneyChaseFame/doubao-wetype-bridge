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
  private static let relevantModifierFlags: CGEventFlags = [
    .maskCommand,
    .maskAlternate,
    .maskControl,
    .maskShift,
    .maskSecondaryFn,
  ]

  private(set) var shortcut: VoiceShortcut?
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

  func updateShortcut(_ shortcut: VoiceShortcut?) {
    guard self.shortcut != shortcut else {
      return
    }
    stop()
    self.shortcut = shortcut
    VoiceShortcutStore.save(shortcut)
    start()
  }

  func start() {
    guard eventTap == nil else {
      return
    }
    guard let shortcut else {
      RuntimeLog.shared.write("fast start disabled; Doubao voice shortcut is unknown")
      return
    }
    if !isAuthorized {
      RuntimeLog.shared.write("fast start awaiting input monitoring permission")
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
    let currentModifierFlags = event.flags.intersection(Self.relevantModifierFlags)

    if shortcut.modifierOnly {
      guard type == .flagsChanged else {
        return
      }
      let isDown = currentModifierFlags == shortcut.modifierFlags
      let wasDown = shortcutIsDown
      shortcutIsDown = isDown
      guard isDown, !wasDown else {
        return
      }
    } else {
      guard type == .keyDown, currentModifierFlags == shortcut.modifierFlags else {
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
