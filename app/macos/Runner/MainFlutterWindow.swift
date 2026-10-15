import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The app's top bar (lib/window/chrome.dart): the window buttons are
  /// centred in it.
  private let barHeight: CGFloat = 40
  private var channel: FlutterMethodChannel?

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
