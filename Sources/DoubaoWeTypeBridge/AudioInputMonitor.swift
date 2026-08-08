import AppKit
import CoreAudio
import Foundation

final class AudioInputMonitor {
  private let doubaoBundleID = "com.bytedance.inputmethod.doubaoime"

  func doubaoIsUsingAudioInput() -> Bool? {
    guard let objectIDs = processObjectIDs() else {
      return nil
    }

    let doubaoPIDs = Set(
      NSRunningApplication.runningApplications(withBundleIdentifier: doubaoBundleID)
        .map { UInt32(bitPattern: $0.processIdentifier) }
    )
    guard !doubaoPIDs.isEmpty else {
      return false
    }

    for objectID in objectIDs {
      guard
        let pid = uint32Property(objectID: objectID, selector: kAudioProcessPropertyPID),
        doubaoPIDs.contains(pid)
      else {
        continue
      }

      return uint32Property(
        objectID: objectID,
        selector: kAudioProcessPropertyIsRunningInput
      ).map { $0 != 0 }
    }
    return false
  }

  private func processObjectIDs() -> [AudioObjectID]? {
    let systemObject = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
      return nil
    }

    var objectIDs = [AudioObjectID](
      repeating: 0,
      count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
    )
    guard
      AudioObjectGetPropertyData(
        systemObject,
        &address,
        0,
        nil,
        &dataSize,
        &objectIDs
      ) == noErr
    else {
      return nil
    }
    return objectIDs
  }

  private func uint32Property(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> UInt32? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var dataSize = UInt32(MemoryLayout<UInt32>.size)
    guard
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        &value
      ) == noErr
    else {
      return nil
    }
    return value
  }
}
