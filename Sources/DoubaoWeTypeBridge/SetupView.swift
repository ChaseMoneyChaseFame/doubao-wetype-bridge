import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
  @Published private(set) var hasWeType = false
  @Published private(set) var hasDoubao = false
  @Published private(set) var fastStartAuthorized = false
  @Published var launchAtLogin = false

  private let inputSources: InputSourceController
  private let bridgeController: BridgeController

  init(inputSources: InputSourceController, bridgeController: BridgeController) {
    self.inputSources = inputSources
    self.bridgeController = bridgeController
    refresh()
  }

  var readyCount: Int {
    (hasWeType ? 1 : 0) + (hasDoubao ? 1 : 0)
  }

  var allReady: Bool {
    hasWeType && hasDoubao
  }

  func refresh() {
    hasWeType = inputSources.hasWeType()
    hasDoubao = inputSources.hasDoubao()
    fastStartAuthorized = bridgeController.fastStartAuthorized
    launchAtLogin = SMAppService.mainApp.status == .enabled
    if fastStartAuthorized {
      bridgeController.refreshFastStartMonitor()
    }
  }

  func requestFastStartAuthorization() {
    bridgeController.requestFastStartAuthorization()
    refresh()
    if !fastStartAuthorized {
      openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
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
        launchAtLoginSection
        footer
      }
      .padding(24)
    }
    .frame(width: 600, height: 520)
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
    actionTitle: String,
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

      if !ready || title == "豆包输入法" {
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

        Text("\(model.readyCount) / 2 已就绪")
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
          detail: "提前唤醒豆包，减少首次等待",
          accent: Palette.cobalt,
          ready: model.fastStartAuthorized,
          actionTitle: "授权",
          action: model.requestFastStartAuthorization
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

  private var launchAtLoginSection: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Palette.cobalt.opacity(0.10))
        Image(systemName: "power")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.cobalt)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text("登录时启动")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.ink)
        Text("让豆微输入法在开机后自动待命")
          .font(.system(size: 11))
          .foregroundStyle(Palette.muted)
      }

      Spacer()

      Toggle(
        "登录时启动",
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { enabled in model.setLaunchAtLogin(enabled) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
      .accessibilityLabel("登录时启动")
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
    .background(
      Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Palette.ink.opacity(0.07), lineWidth: 1)
    }
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
