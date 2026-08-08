import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
  @Published private(set) var hasWeType = false
  @Published private(set) var hasDoubao = false
  @Published var launchAtLogin = false

  private let inputSources: InputSourceController

  init(inputSources: InputSourceController) {
    self.inputSources = inputSources
    refresh()
  }

  func refresh() {
    hasWeType = inputSources.hasWeType()
    hasDoubao = inputSources.hasDoubao()
    launchAtLogin = SMAppService.mainApp.status == .enabled
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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("豆微输入法")
          .font(.system(size: 24, weight: .semibold))
        Text("设置")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, 22)

      statusRow(
        icon: "keyboard",
        title: "微信输入法",
        ready: model.hasWeType,
        actionTitle: "输入法设置",
        action: model.openKeyboardSettings
      )
      Divider()
      statusRow(
        icon: "waveform",
        title: "豆包输入法",
        ready: model.hasDoubao,
        actionTitle: "语音设置",
        action: model.openDoubaoSettings
      )
      Divider()

      HStack(spacing: 12) {
        Image(systemName: "power")
          .frame(width: 22)
          .foregroundStyle(.secondary)
        Text("开机启动")
          .font(.system(size: 14, weight: .medium))
        Spacer()
        Toggle(
          "",
          isOn: Binding(
            get: { model.launchAtLogin },
            set: { enabled in model.setLaunchAtLogin(enabled) }
          )
        )
        .labelsHidden()
      }
      .frame(height: 54)

      Spacer(minLength: 20)

      HStack {
        Button(action: model.refresh) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("刷新状态")

        Spacer()

        Button("完成", action: close)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(!model.hasWeType || !model.hasDoubao)
      }
    }
    .padding(28)
    .frame(width: 520, height: 370)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder
  private func statusRow(
    icon: String,
    title: String,
    ready: Bool,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .frame(width: 22)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.system(size: 14, weight: .medium))
      Spacer()
      Label(
        ready ? "已就绪" : "待处理",
        systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle"
      )
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(ready ? Color.green : Color.orange)
      if !ready || title == "豆包输入法" {
        Button(actionTitle, action: action)
          .controlSize(.small)
      }
    }
    .frame(height: 58)
  }
}
