import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let inputSources = InputSourceController()
  private lazy var bridgeController = BridgeController(inputSources: inputSources)
  private var statusItem: NSStatusItem?
  private var statusMenuItem: NSMenuItem?
  private var launchAtLoginMenuItem: NSMenuItem?
  private var setupWindow: NSWindow?
  private var setupModel: SetupModel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureStatusItem()
    bridgeController.statusDidChange = { [weak self] status in
      DispatchQueue.main.async {
        self?.updateStatus(status)
      }
    }
    bridgeController.start()

    if !UserDefaults.standard.bool(forKey: "hasCompletedSetup")
      || !inputSources.hasWeType()
      || !inputSources.hasDoubao()
    {
      showSetup()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    bridgeController.stop()
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = makeStatusIcon()
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleProportionallyDown
    item.button?.toolTip = "豆微输入法"

    let menu = NSMenu()
    let status = NSMenuItem(title: BridgeStatus.waiting.title, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSetup), keyEquivalent: ","))
    menu.addItem(
      NSMenuItem(title: "立即切回微信输入法", action: #selector(restoreImmediately), keyEquivalent: "w"))

    let launchItem = NSMenuItem(
      title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    menu.addItem(launchItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "打开运行日志", action: #selector(openLog), keyEquivalent: "l"))
    menu.addItem(NSMenuItem(title: "检查更新", action: #selector(checkForUpdates), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

    item.menu = menu
    statusItem = item
    statusMenuItem = status
    launchAtLoginMenuItem = launchItem
    refreshLaunchAtLoginMenuState()
  }

  /// Keep the menu bar mark simple enough to remain legible at 18pt.
  private func makeStatusIcon() -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    guard
      let symbol = NSImage(
        systemSymbolName: "waveform",
        accessibilityDescription: "豆微输入法"
      ),
      let image = symbol.withSymbolConfiguration(configuration)
    else {
      return NSImage(size: NSSize(width: 18, height: 18))
    }

    image.isTemplate = true
    return image
  }

  private func updateStatus(_ status: BridgeStatus) {
    statusMenuItem?.title = status.title
  }

  @objc private func showSetup() {
    if let setupWindow {
      setupWindow.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      setupModel?.refresh()
      return
    }

    let model = SetupModel(inputSources: inputSources, bridgeController: bridgeController)
    let view = SetupView(model: model) { [weak self] in
      UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
      self?.setupWindow?.orderOut(nil)
      self?.refreshLaunchAtLoginMenuState()
    }
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.title = "豆微输入法"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    setupModel = model
    setupWindow = window
  }

  @objc private func restoreImmediately() {
    bridgeController.restoreImmediately()
  }

  @objc private func toggleLaunchAtLogin() {
    guard let setupModel else {
      showSetup()
      return
    }
    setupModel.setLaunchAtLogin(!setupModel.launchAtLogin)
    refreshLaunchAtLoginMenuState()
  }

  private func refreshLaunchAtLoginMenuState() {
    let model =
      setupModel ?? SetupModel(inputSources: inputSources, bridgeController: bridgeController)
    model.refresh()
    launchAtLoginMenuItem?.state = model.launchAtLogin ? .on : .off
  }

  @objc private func openLog() {
    NSWorkspace.shared.activateFileViewerSelecting([RuntimeLog.shared.fileURL])
  }

  @objc private func checkForUpdates() {
    guard
      let url = URL(
        string: "https://github.com/ChaseMoneyChaseFame/doubao-wetype-bridge/releases/latest")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}
