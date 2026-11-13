import Flutter
import UIKit

/// Speaks the two channels the desktop runners speak:
/// - `openward/security`: when the device locks, the vault locks too
///   ("suspend"), as on a system lock on the desktop; and the app switcher's
///   snapshot is taken of a plain cover, never of a terminal.
/// - `openward/sessions`: with sessions open, the app asks iOS for the time
///   it gives to finish in the background. iOS suspends the sockets after
///   that; the sessions then reconnect, and tmux resumes them
///   (ARCHITECTURE §3.7).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var security: FlutterMethodChannel?
  private var securityReady = false
  private var suspendPending = false
  private var sessions = 0
  private var background: UIBackgroundTaskIdentifier = .invalid
  private var covers: [ObjectIdentifier: UIView] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(deviceWillLock),
      name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidEnterBackground(_:)),
      name: UIScene.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneWillEnterForeground(_:)),
      name: UIScene.willEnterForegroundNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let security = FlutterMethodChannel(name: "openward/security", binaryMessenger: messenger)
    security.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "ready":
        self.securityReady = true
        if self.suspendPending { security.invokeMethod("suspend", arguments: nil) }
        result(nil)
      case "privacyReady":
        self.suspendPending = false
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    self.security = security
    let files = FlutterMethodChannel(name: "openward/files", binaryMessenger: messenger)
    files.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "export",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else { return result(FlutterMethodNotImplemented) }
      self.export(URL(fileURLWithPath: path), result: result)
    }
    let sessions = FlutterMethodChannel(name: "openward/sessions", binaryMessenger: messenger)
    sessions.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "count":
        self.sessions = (call.arguments as? Int) ?? 0
        if self.sessions == 0 { self.endBackground() }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Only with a passcode: without one, iOS never locks the data.
  @objc private func deviceWillLock() {
    suspendPending = true
    if securityReady { security?.invokeMethod("suspend", arguments: nil) }
  }

  @objc private func sceneDidEnterBackground(_ note: Notification) {
    guard let scene = note.object as? UIWindowScene else { return }
    for window in scene.windows where covers[ObjectIdentifier(window)] == nil {
      let cover = UIView(frame: window.bounds)
      cover.backgroundColor = .black
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(cover)
      covers[ObjectIdentifier(window)] = cover
    }
    if sessions > 0 && background == .invalid {
      background = UIApplication.shared.beginBackgroundTask(withName: "OpenWard sessions") {
        [weak self] in self?.endBackground()
      }
    }
  }

  @objc private func sceneWillEnterForeground(_ note: Notification) {
    guard let scene = note.object as? UIWindowScene else { return }
    for window in scene.windows {
      covers.removeValue(forKey: ObjectIdentifier(window))?.removeFromSuperview()
    }
    endBackground()
  }

  /// "Save to Files": the system's sheet takes a copy of the file where
  /// the user says. True once saved; false when cancelled.
  private func export(_ url: URL, result: @escaping FlutterResult) {
    guard let top = topController() else { return result(false) }
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    let delegate = ExportDelegate { [weak self] saved in
      self?.exporting = nil
      result(saved)
    }
    exporting = delegate
    picker.delegate = delegate
    top.present(picker, animated: true)
  }

  private var exporting: ExportDelegate?

  private func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive } ??
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func endBackground() {
    guard background != .invalid else { return }
    UIApplication.shared.endBackgroundTask(background)
    background = .invalid
  }
}

private final class ExportDelegate: NSObject, UIDocumentPickerDelegate {
  let done: (Bool) -> Void
  init(done: @escaping (Bool) -> Void) { self.done = done }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    done(true)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    done(false)
  }
}
