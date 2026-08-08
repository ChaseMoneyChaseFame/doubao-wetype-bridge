import Foundation

final class RuntimeLog: @unchecked Sendable {
  static let shared = RuntimeLog()

  let fileURL: URL
  private let queue = DispatchQueue(label: "app.doubaowetype.bridge.log")
  private let formatter: ISO8601DateFormatter

  private init() {
    let logDirectory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/DoubaoWeTypeBridge", isDirectory: true)
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    fileURL = logDirectory.appendingPathComponent("runtime.log")

    formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  }

  func write(_ message: String) {
    let line = "[\(formatter.string(from: Date()))] \(message)\n"
    queue.async { [fileURL] in
      guard let data = line.data(using: .utf8) else {
        return
      }

      if !FileManager.default.fileExists(atPath: fileURL.path) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
      }

      guard let handle = try? FileHandle(forWritingTo: fileURL) else {
        return
      }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    }
  }
}
