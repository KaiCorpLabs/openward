import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func awakeFromNib() {
    super.awakeFromNib()
    // Holding a key repeats it, as in a terminal (j and k in vim), instead
    // of offering accents. A setting of the user's own still wins.
    UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
