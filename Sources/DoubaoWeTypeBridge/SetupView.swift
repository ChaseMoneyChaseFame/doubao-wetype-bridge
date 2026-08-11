import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
  @Published private(set) var hasWeType = false
  @Published private(set) var hasDoubao = false
  @Published private(set) var fastStartAuthorized = false
  @Published private(set) var fastStartAutomationAuthorized = false
  @Published private(set) var fastStartConfigured = false
  @Published private(set) var fastStartShortcutName: String?
  @Published private(set) var isCapturingShortcut = false
  @Published private(set) var alwaysRestoreToWeType = false
  @Published var launchAtLogin = false

  private let inputSources: InputSourceController
  private let bridgeController: BridgeController
  private var permissionTimer: Timer?
  private var shortcutCaptureMonitor: Any?
  private var pendingModifierShortcut: VoiceShortcut?
  private var modifierShortcutCandidates: [VoiceShortcut] = []
  private var pendingModifierCommit: DispatchWorkItem?
  private var shortcutCaptureGeneration = 0
  private var usingGlobalShortcutCapture = false

  init(inputSources: InputSourceController, bridgeController: BridgeController) {
    self.inputSources = inputSources
    self.bridgeController = bridgeController
    refresh()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.pollFastStartAuthorization()
      }
    }
  }

  deinit {
    permissionTimer?.invalidate()
    pendingModifierCommit?.cancel()
    if let shortcutCaptureMonitor {
      NSEvent.removeMonitor(shortcutCaptureMonitor)
    }
  }

  var readyCount: Int {
    (hasWeType ? 1 : 0)
      + (hasDoubao ? 1 : 0)
      + (fastStartReady ? 1 : 0)
  }

  var allReady: Bool {
    hasWeType && hasDoubao && fastStartReady
  }

  var fastStartReady: Bool {
    fastStartConfigured && fastStartAuthorized && fastStartAutomationAuthorized
  }

  func refresh() {
    inputSources.refresh()
    hasWeType = inputSources.hasWeType()
    hasDoubao = inputSources.hasDoubao()
    let wasFastStartAuthorized = fastStartAuthorized
    let wasFastStartAutomationAuthorized = fastStartAutomationAuthorized
    fastStartAuthorized = bridgeController.fastStartAuthorized
    fastStartAutomationAuthorized = bridgeController.fastStartAutomationAuthorized
    fastStartConfigured = bridgeController.fastStartConfigured
    fastStartShortcutName = bridgeController.fastStartShortcut?.displayName
    alwaysRestoreToWeType = bridgeController.alwaysRestoreToWeTypeEnabled
    launchAtLogin = SMAppService.mainApp.status == .enabled
    if fastStartReady
      && (!wasFastStartAuthorized || !wasFastStartAutomationAuthorized)
    {
      bridgeController.refreshFastStartMonitor()
    }
  }

  private func pollFastStartAuthorization() {
    let wasAuthorized = fastStartAuthorized
    let wasAutomationAuthorized = fastStartAutomationAuthorized
    let isAuthorized = bridgeController.fastStartAuthorized
    let isAutomationAuthorized = bridgeController.fastStartAutomationAuthorized
    guard
      isAuthorized != wasAuthorized
        || isAutomationAuthorized != wasAutomationAuthorized
    else {
      return
    }
    fastStartAuthorized = isAuthorized
    fastStartAutomationAuthorized = isAutomationAuthorized
    if isAuthorized && isAutomationAuthorized {
      bridgeController.refreshFastStartMonitor()
      RuntimeLog.shared.write("fast start permissions detected; monitor refreshed")
    }
  }

  func requestFastStartAuthorization() {
    if !fastStartAuthorized {
      bridgeController.requestFastStartAuthorization()
    } else if !fastStartAutomationAuthorized {
      bridgeController.requestFastStartAutomationAuthorization()
    }
    refresh()
    if !fastStartAuthorized {
      openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    } else if !fastStartAutomationAuthorized {
      openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
  }

  func handleFastStartAction() {
    if fastStartConfigured && !fastStartReady {
      requestFastStartAuthorization()
    } else {
      beginShortcutCapture()
    }
  }

  private func beginShortcutCapture() {
    guard !isCapturingShortcut else {
      return
    }
    shortcutCaptureGeneration += 1
    pendingModifierShortcut = nil
    modifierShortcutCandidates = []
    pendingModifierCommit?.cancel()
    pendingModifierCommit = nil
    isCapturingShortcut = true
    usingGlobalShortcutCapture = bridgeController.setFastStartShortcutCaptureHandler {
      [weak self] type, keyCode, flags in
      Task { @MainActor [weak self] in
        self?.captureShortcut(type: type, keyCode: keyCode, flags: flags)
      }
    }
    bridgeController.setFastStartShortcutCaptureActive(true)

    if !usingGlobalShortcutCapture {
      shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.flagsChanged, .keyDown]
      ) { [weak self] event in
        MainActor.assumeIsolated {
          self?.captureShortcut(from: event)
        }
        return nil
      }
    }
  }

  private func captureShortcut(from event: NSEvent) {
    if event.type == .keyDown, event.keyCode == 53 {
      endShortcutCapture()
      return
    }

    if event.type == .flagsChanged {
      guard let shortcut = Self.modifierShortcut(for: event) else {
        return
      }
      scheduleModifierShortcutCommit(shortcut)
      return
    }

    guard event.type == .keyDown else {
      return
    }
    if handleSyntheticInputSourceSwitch(
      keyCode: Int64(event.keyCode),
      flags: Self.modifierFlags(from: event.modifierFlags)
    ) {
      return
    }
    cancelPendingModifierCommit()
    commitShortcut(Self.keyShortcut(for: event))
  }

  private func captureShortcut(
    type: CGEventType,
    keyCode: Int64,
    flags: CGEventFlags
  ) {
    if type == .keyDown, keyCode == 53 {
      endShortcutCapture()
      return
    }

    if type == .flagsChanged {
      guard let shortcut = Self.modifierShortcut(keyCode: keyCode, flags: flags) else {
        return
      }
      scheduleModifierShortcutCommit(shortcut)
      return
    }

    guard type == .keyDown else {
      return
    }
    if handleSyntheticInputSourceSwitch(keyCode: keyCode, flags: flags) {
      return
    }
    cancelPendingModifierCommit()
    commitShortcut(Self.keyShortcut(keyCode: keyCode, flags: flags))
  }

  private func scheduleModifierShortcutCommit(_ shortcut: VoiceShortcut) {
    if modifierShortcutCandidates.last != shortcut {
      modifierShortcutCandidates.append(shortcut)
    }
    pendingModifierShortcut = shortcut
    pendingModifierCommit?.cancel()

    let generation = shortcutCaptureGeneration
    let workItem = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard
          let self,
          self.shortcutCaptureGeneration == generation,
          let shortcut = self.pendingModifierShortcut
        else {
          return
        }
        self.pendingModifierCommit = nil
        self.pendingModifierShortcut = nil
        self.commitShortcut(shortcut)
      }
    }
    pendingModifierCommit = workItem

    // Doubao can synthesize input-source switching events around the physical
    // shortcut. Keep the candidates briefly so that burst can be discarded.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
  }

  private func handleSyntheticInputSourceSwitch(
    keyCode: Int64,
    flags: CGEventFlags
  ) -> Bool {
    let relevantFlags = flags.intersection([
      .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
    ])
    guard keyCode == 49, relevantFlags == .maskControl else {
      return false
    }

    let physicalCandidate = modifierShortcutCandidates.last {
      !$0.modifierFlags.contains(.maskControl)
    }
    pendingModifierCommit?.cancel()
    pendingModifierCommit = nil
    pendingModifierShortcut = nil
    modifierShortcutCandidates.removeAll { $0.modifierFlags.contains(.maskControl) }

    RuntimeLog.shared.write("shortcut capture ignored synthetic Control + Space")
    if let physicalCandidate {
      scheduleModifierShortcutCommit(physicalCandidate)
    }
    return true
  }

  private func commitShortcut(_ shortcut: VoiceShortcut) {
    bridgeController.setFastStartShortcut(shortcut)
    RuntimeLog.shared.write(
      "Doubao voice shortcut captured; name=\(shortcut.displayName); keyCode=\(shortcut.keyCode)"
    )
    endShortcutCapture()
    refresh()
  }

  private func endShortcutCapture() {
    shortcutCaptureGeneration += 1
    cancelPendingModifierCommit()
    if let shortcutCaptureMonitor {
      NSEvent.removeMonitor(shortcutCaptureMonitor)
      self.shortcutCaptureMonitor = nil
    }
    bridgeController.setFastStartShortcutCaptureHandler(nil)
    usingGlobalShortcutCapture = false
    bridgeController.setFastStartShortcutCaptureActive(false)
    isCapturingShortcut = false
  }

  private func cancelPendingModifierCommit() {
    pendingModifierCommit?.cancel()
    pendingModifierCommit = nil
    pendingModifierShortcut = nil
    modifierShortcutCandidates = []
  }

  private static func modifierShortcut(for event: NSEvent) -> VoiceShortcut? {
    modifierShortcut(
      keyCode: Int64(event.keyCode),
      flags: modifierFlags(from: event.modifierFlags)
    )
  }

  private static func modifierShortcut(
    keyCode: Int64,
    flags: CGEventFlags
  ) -> VoiceShortcut? {
    let mapping: (name: String, nsFlag: NSEvent.ModifierFlags, cgFlag: CGEventFlags)?
    switch keyCode {
    case 54:
      mapping = ("右 Command", .command, .maskCommand)
    case 55:
      mapping = ("左 Command", .command, .maskCommand)
    case 58:
      mapping = ("左 Option", .option, .maskAlternate)
    case 61:
      mapping = ("右 Option", .option, .maskAlternate)
    case 59:
      mapping = ("左 Control", .control, .maskControl)
    case 62:
      mapping = ("右 Control", .control, .maskControl)
    case 56:
      mapping = ("左 Shift", .shift, .maskShift)
    case 60:
      mapping = ("右 Shift", .shift, .maskShift)
    case 63:
      mapping = ("Fn", .function, .maskSecondaryFn)
    default:
      mapping = nil
    }

    guard let mapping, flags.contains(mapping.cgFlag) else {
      return nil
    }
    return VoiceShortcut(
      keyCode: keyCode,
      modifierFlagsRawValue: mapping.cgFlag.rawValue,
      modifierOnly: true,
      displayName: mapping.name
    )
  }

  private static func keyShortcut(for event: NSEvent) -> VoiceShortcut {
    keyShortcut(
      keyCode: Int64(event.keyCode),
      flags: modifierFlags(from: event.modifierFlags),
      keyName: event.charactersIgnoringModifiers?.uppercased()
    )
  }

  private static func keyShortcut(
    keyCode: Int64,
    flags: CGEventFlags,
    keyName rawKeyName: String? = nil
  ) -> VoiceShortcut {
    var cgFlags: CGEventFlags = []
    var names: [String] = []
    if flags.contains(.maskControl) {
      cgFlags.insert(.maskControl)
      names.append("Control")
    }
    if flags.contains(.maskAlternate) {
      cgFlags.insert(.maskAlternate)
      names.append("Option")
    }
    if flags.contains(.maskShift) {
      cgFlags.insert(.maskShift)
      names.append("Shift")
    }
    if flags.contains(.maskCommand) {
      cgFlags.insert(.maskCommand)
      names.append("Command")
    }
    if flags.contains(.maskSecondaryFn) {
      cgFlags.insert(.maskSecondaryFn)
      names.append("Fn")
    }

    let keyName = rawKeyName?.isEmpty == false ? rawKeyName! : "键码 \(keyCode)"
    names.append(keyName)
    return VoiceShortcut(
      keyCode: keyCode,
      modifierFlagsRawValue: cgFlags.rawValue,
      modifierOnly: false,
      displayName: names.joined(separator: " + ")
    )
  }

  private static func modifierFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
    var result: CGEventFlags = []
    if flags.contains(.control) { result.insert(.maskControl) }
    if flags.contains(.option) { result.insert(.maskAlternate) }
    if flags.contains(.shift) { result.insert(.maskShift) }
    if flags.contains(.command) { result.insert(.maskCommand) }
    if flags.contains(.function) { result.insert(.maskSecondaryFn) }
    return result
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      RuntimeLog.shared.write("launch at login update failed; error=\(error)")
    }
    refresh()
  }

  func setAlwaysRestoreToWeType(_ enabled: Bool) {
    bridgeController.setAlwaysRestoreToWeTypeEnabled(enabled)
    alwaysRestoreToWeType = enabled
  }

  func openDoubaoSettings() {
    let settingsURL = URL(
      fileURLWithPath:
        "/Library/Input Methods/DoubaoIme.app/Contents/Applications/DoubaoImeSettings.app"
    )
    NSWorkspace.shared.openApplication(
      at: settingsURL,
      configuration: NSWorkspace.OpenConfiguration()
    )
  }

  func openKeyboardSettings() {
    openURL("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
  }

  private func openURL(_ rawValue: String) {
    guard let url = URL(string: rawValue) else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}

struct SetupView: View {
  @ObservedObject var model: SetupModel
  let close: () -> Void

  @State private var hoveredRow: String?

  private enum Palette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let cobalt = Color(red: 0.16, green: 0.43, blue: 0.90)
    static let wechatGreen = Color(red: 0.03, green: 0.67, blue: 0.38)
    static let doubaoBlue = Color(red: 0.20, green: 0.48, blue: 0.92)
    static let ready = Color(red: 0.03, green: 0.63, blue: 0.34)
    static let pending = Color(red: 0.28, green: 0.48, blue: 0.78)
  }

  var body: some View {
    ZStack {
      Palette.canvas

      LinearGradient(
        colors: [
          Palette.canvas,
          Palette.canvas.opacity(0.86),
          Palette.cobalt.opacity(0.05),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      VStack(alignment: .leading, spacing: 18) {
        header
          .padding(.horizontal, -24)
          .padding(.top, -24)
        connectionSection
        preferencesSection
        footer
      }
      .padding(24)
    }
    .frame(width: 600, height: 574)
    .background(Palette.canvas)
  }

  @ViewBuilder
  private func statusRow(
    id: String,
    icon: String,
    title: String,
    detail: String,
    accent: Color,
    ready: Bool,
    actionTitle: String?,
    action: @escaping () -> Void
  ) -> some View {
    let isHovered = hoveredRow == id

    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(accent.opacity(0.13))
        Image(systemName: icon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.ink)
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(Palette.muted)
      }

      Spacer(minLength: 8)

      statusBadge(ready: ready)

      if let actionTitle, !ready || title == "豆包输入法" || title == "快速启动" {
        Button(actionTitle, action: action)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 58)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(isHovered ? Palette.ink.opacity(0.045) : .clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      hoveredRow = hovering ? id : nil
    }
    .animation(.easeOut(duration: 0.16), value: isHovered)
  }

  private var header: some View {
    ZStack(alignment: .leading) {
      if let artwork = SetupArtworkLoader.image {
        Image(nsImage: artwork)
          .resizable()
          .scaledToFill()
          .frame(width: 360, height: 150)
          .clipped()
          .mask {
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.18), location: 0.16),
                .init(color: .white, location: 0.42),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          }
          .mask {
            LinearGradient(
              stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.76),
                .init(color: .clear, location: 1),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          AppMark()

          Text("豆微输入法")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.ink)
        }

        Text(model.allReady ? "连接已建立，随时可以开始。" : "把两个输入通道接好，就可以开始。")
          .font(.system(size: 12))
          .foregroundStyle(model.allReady ? Palette.ready : Palette.muted)
          .animation(.easeOut(duration: 0.2), value: model.allReady)
      }
      .padding(.leading, 24)
      .padding(.top, 24)
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(height: 150)
    .clipped()
  }

  private var connectionSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text("输入通道")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Palette.ink)

        Spacer()

        Text("\(model.readyCount) / 3 已就绪")
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(model.allReady ? Palette.ready : Palette.pending)
      }

      VStack(spacing: 0) {
        statusRow(
          id: "wetype",
          icon: "keyboard",
          title: "微信输入法",
          detail: "文字输入通道",
          accent: Palette.wechatGreen,
          ready: model.hasWeType,
          actionTitle: "输入法设置",
          action: model.openKeyboardSettings
        )

        Divider()
          .padding(.leading, 56)

        statusRow(
          id: "doubao",
          icon: "waveform",
          title: "豆包输入法",
          detail: "语音输入通道",
          accent: Palette.doubaoBlue,
          ready: model.hasDoubao,
          actionTitle: "语音设置",
          action: model.openDoubaoSettings
        )

        Divider()
          .padding(.leading, 56)

        statusRow(
          id: "fast-start",
          icon: "bolt.fill",
          title: "快速启动",
          detail: fastStartDetail,
          accent: Palette.cobalt,
          ready: model.fastStartReady,
          actionTitle: fastStartActionTitle,
          action: model.handleFastStartAction
        )
      }
      .padding(6)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Palette.ink.opacity(0.08), lineWidth: 1)
      }
    }
  }

  private var fastStartDetail: String {
    if model.isCapturingShortcut {
      return "请按下豆包设置的语音快捷键"
    }
    guard let name = model.fastStartShortcutName else {
      return "录制豆包语音快捷键后启用"
    }
    if !model.fastStartAuthorized {
      return "已录制 \(name)，请授权输入监控"
    }
    if !model.fastStartAutomationAuthorized {
      return "已录制 \(name)，请授权辅助功能"
    }
    return "已录制 \(name)，减少首次等待"
  }

  private var fastStartActionTitle: String? {
    if model.isCapturingShortcut {
      return nil
    }
    if model.fastStartConfigured && !model.fastStartReady {
      return "授权"
    }
    return model.fastStartConfigured ? "重录" : "录制"
  }

  private var preferencesSection: some View {
    VStack(spacing: 0) {
      preferenceRow(
        icon: "arrow.uturn.left",
        title: "语音结束回微信",
        detail: "即使从豆包开始，语音结束后也切回微信",
        isOn: Binding(
          get: { model.alwaysRestoreToWeType },
          set: { enabled in model.setAlwaysRestoreToWeType(enabled) }
        )
      )

      Divider()
        .padding(.leading, 62)

      preferenceRow(
        icon: "power",
        title: "登录时启动",
        detail: "让豆微输入法在开机后自动待命",
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { enabled in model.setLaunchAtLogin(enabled) }
        )
      )
    }
    .background(
      Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Palette.ink.opacity(0.07), lineWidth: 1)
    }
  }

  private func preferenceRow(
    icon: String,
    title: String,
    detail: String,
    isOn: Binding<Bool>
  ) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Palette.cobalt.opacity(0.10))
        Image(systemName: icon)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.cobalt)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.ink)
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(Palette.muted)
      }

      Spacer()

      Toggle(title, isOn: isOn)
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
      .accessibilityLabel(title)
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
  }

  private var footer: some View {
    HStack(spacing: 9) {
      Button(action: model.refresh) {
        Image(systemName: "arrow.clockwise")
        Text("重新检查")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(Palette.muted)
      .help("刷新输入法状态")

      Text("状态会自动同步")
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted.opacity(0.78))

      Spacer()

      Button("完成", action: close)
        .buttonStyle(.borderedProminent)
        .tint(Palette.cobalt)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.allReady)
    }
  }

  private func statusBadge(ready: Bool) -> some View {
    HStack(spacing: 4) {
      Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .font(.system(size: 12, weight: .semibold))
      Text(ready ? "已就绪" : "待处理")
        .font(.system(size: 11, weight: .semibold))
    }
    .foregroundStyle(ready ? Palette.ready : Palette.pending)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      (ready ? Palette.ready : Palette.pending).opacity(0.10),
      in: Capsule()
    )
  }
}

private enum SetupArtworkLoader {
  static let image: NSImage? = {
    guard let resourceURL = Bundle.main.resourceURL else {
      return nil
    }

    let imageURL =
      resourceURL
      .appendingPathComponent("DoubaoWeTypeBridge_DoubaoWeTypeBridge.bundle")
      .appendingPathComponent("SetupArtwork.png")
    return NSImage(contentsOf: imageURL)
  }()
}

private struct AppMark: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color(red: 0.16, green: 0.43, blue: 0.90),
              Color(red: 0.24, green: 0.62, blue: 0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Image(systemName: "waveform")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: 36, height: 36)
    .shadow(color: Color(red: 0.16, green: 0.43, blue: 0.90).opacity(0.20), radius: 7, y: 3)
    .accessibilityHidden(true)
  }
}
