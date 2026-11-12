import Cocoa
import FlutterMacOS

private final class VaultPrivacyCover: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func keyDown(with event: NSEvent) {}
  override func mouseDown(with event: NSEvent) {}
}

class MainFlutterWindow: NSWindow {
  /// The app's top bar (lib/window/chrome.dart): the window buttons are
  /// centred in it.
  private let barHeight: CGFloat = 40
  private var channel: FlutterMethodChannel?
  private var securityChannel: FlutterMethodChannel?
  private var privacyCover: NSView?
  private var privacyPending = false
  private var securityReady = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // A sidebar and an 80-column terminal fit; size and place are
    // remembered between runs.
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.contentMinSize = NSSize(width: 760, height: 480)
    self.center()
    self.setFrameAutosaveName("OpenWard")

    // The app draws its own top bar: the content goes under a transparent
    // title bar, which keeps only the window buttons. Dragging and
    // double-clicking that bar come back through the channel.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    // AppKit would move the window from any press under the title bar,
    // tabs included, so a tab dragged to a pane dragged the window too.
    // The app decides: its empty bar asks for a drag through the channel.
    self.isMovable = false

    let channel = FlutterMethodChannel(
      name: "openward/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "drag":
        if let event = NSApp.currentEvent { self.performDrag(with: event) }
        result(nil)
      case "doubleClick":
        self.titleBarDoubleClick()
        result(nil)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    let security = FlutterMethodChannel(name: "openward/security", binaryMessenger: flutterViewController.engine.binaryMessenger)
    security.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "ready":
        self.securityReady = true
        if self.privacyPending { security.invokeMethod("suspend", arguments: nil) }
        result(nil)
      case "privacyReady":
        self.privacyCover?.removeFromSuperview()
        self.makeFirstResponder(self.contentViewController?.view)
        self.privacyCover = nil
        self.privacyPending = false
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    self.securityChannel = security
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(self, selector: #selector(redactForSystemLock), name: NSWorkspace.willSleepNotification, object: nil)
    workspace.addObserver(self, selector: #selector(redactForSystemLock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    // Screen lock is distinct from ordinary app deactivation (including Touch ID).
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(redactForSystemLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didEnterFullScreen),
      name: NSWindow.didEnterFullScreenNotification, object: self)
    center.addObserver(
      self, selector: #selector(didExitFullScreen),
      name: NSWindow.didExitFullScreenNotification, object: self)
    center.addObserver(
      self, selector: #selector(layoutWindowButtons),
      name: NSWindow.didResizeNotification, object: self)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    layoutWindowButtons()
  }

  @objc private func redactForSystemLock() {
    privacyPending = true
    if privacyCover == nil, let content = contentView {
      let cover = VaultPrivacyCover(frame: content.bounds)
      cover.wantsLayer = true
      cover.layer?.backgroundColor = NSColor.black.cgColor
      cover.autoresizingMask = [.width, .height]
      content.addSubview(cover, positioned: .above, relativeTo: nil)
      privacyCover = cover
      makeFirstResponder(cover)
      content.displayIfNeeded()
    }
    if securityReady { securityChannel?.invokeMethod("suspend", arguments: nil) }
  }

  /// Closing the window quits (it is the only one), so it goes the way
  /// ⌘Q does: through the app, which asks first when that cuts off open
  /// sessions, transfers or tunnels.
  override func performClose(_ sender: Any?) {
    NSApp.terminate(sender)
  }

  /// What the user set for a double click on a title bar (System
  /// Settings › Desktop & Dock): zoom unless they said otherwise.
  private func titleBarDoubleClick() {
    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize": miniaturize(nil)
    case "None": break
    default: zoom(nil)
    }
  }

  @objc private func didEnterFullScreen() {
    channel?.invokeMethod("fullScreen", arguments: true)
  }

  @objc private func didExitFullScreen() {
    channel?.invokeMethod("fullScreen", arguments: false)
    layoutWindowButtons()
  }

  /// The three window buttons, vertically centred in the top bar instead
  /// of the standard title bar. AppKit lays them out again on resize and
  /// on leaving full screen, so this runs after those too.
  @objc private func layoutWindowButtons() {
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let container = close.superview?.superview
    else { return }
    var bar = container.frame
    bar.size.height = barHeight
    bar.origin.y = frame.height - barHeight
    container.frame = bar
    let spacing = mini.frame.minX - close.frame.minX
    let y = (barHeight - close.frame.height) / 2
    for (i, button) in [close, mini, zoom].enumerated() {
      button.setFrameOrigin(NSPoint(x: 16 + CGFloat(i) * spacing, y: y))
    }
  }
}
