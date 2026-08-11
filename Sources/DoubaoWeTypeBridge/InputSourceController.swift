import Carbon
import Foundation

struct InputSourceInfo: Equatable {
  let id: String
  let name: String
}

final class InputSourceController {
  static let weTypeInputSourceID = "com.tencent.inputmethod.wetype.pinyin"
  static let weTypeInputSourcePrefix = "com.tencent.inputmethod.wetype"
  static let doubaoInputSourcePrefix = "com.bytedance.inputmethod.doubaoime"

  private let sourceLock = NSLock()
  private var cachedInputSources: [TISInputSource]?

  init() {
    _ = inputSources()
  }

  func refresh() {
    sourceLock.lock()
    cachedInputSources = nil
    sourceLock.unlock()
  }

  func currentID() -> String {
    guard
      let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let rawValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else {
      return "unknown"
    }
    return Unmanaged<CFString>.fromOpaque(rawValue).takeUnretainedValue() as String
  }

  func installedSources() -> [InputSourceInfo] {
    inputSources().compactMap { source in
      guard let id = stringProperty(source, key: kTISPropertyInputSourceID) else {
        return nil
      }
      let name = stringProperty(source, key: kTISPropertyLocalizedName) ?? id
      return InputSourceInfo(id: id, name: name)
    }
  }

  func hasWeType() -> Bool {
    installedSources().contains { $0.id.hasPrefix(Self.weTypeInputSourcePrefix) }
  }

  func hasDoubao() -> Bool {
    installedSources().contains { $0.id.hasPrefix(Self.doubaoInputSourcePrefix) }
  }

  func preferredWeTypeID() -> String? {
    let sources = installedSources()
    if sources.contains(where: { $0.id == Self.weTypeInputSourceID }) {
      return Self.weTypeInputSourceID
    }
    return sources.first { $0.id.hasPrefix(Self.weTypeInputSourcePrefix) }?.id
  }

  @discardableResult
  func selectWeType() -> Bool {
    if select(id: Self.weTypeInputSourceID) {
      return true
    }
    return selectFirst(prefix: Self.weTypeInputSourcePrefix)
  }

  @discardableResult
  func selectFirstDoubao() -> Bool {
    selectFirst(prefix: Self.doubaoInputSourcePrefix)
  }

  @discardableResult
  func select(id targetID: String) -> Bool {
    for source in inputSources() {
      guard stringProperty(source, key: kTISPropertyInputSourceID) == targetID else {
        continue
      }
      return TISSelectInputSource(source) == noErr
    }
    return false
  }

  @discardableResult
  private func selectFirst(prefix: String) -> Bool {
    for source in inputSources() {
      guard
        let sourceID = stringProperty(source, key: kTISPropertyInputSourceID),
        sourceID.hasPrefix(prefix)
      else {
        continue
      }
      return TISSelectInputSource(source) == noErr
    }
    return false
  }

  private func inputSources() -> [TISInputSource] {
    sourceLock.lock()
    defer { sourceLock.unlock() }

    if let cachedInputSources {
      return cachedInputSources
    }

    let rawSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
    var sources: [TISInputSource] = []
    for case let source as TISInputSource in rawSources {
      sources.append(source)
    }
    cachedInputSources = sources
    return sources
  }

  private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else {
      return nil
    }
    return Unmanaged<CFString>.fromOpaque(rawValue).takeUnretainedValue() as String
  }
}
