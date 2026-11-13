import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// What this device can do that another cannot. The phones (Android, iOS)
/// run the same app as the desktop; what they lack is said here, once, and
/// the pages hide it rather than fail (docs/plan/movil.md).
abstract final class Device {
  /// A phone or a tablet: Android or iOS.
  static bool get mobile =>
      debugMobile ?? (Platform.isAndroid || Platform.isIOS);

  /// Tests on the desktop try the phone's layout and limits with this.
  @visibleForTesting
  static bool? debugMobile;

  /// A shell of this device in a tab: no PTY on iOS, and Android's own
  /// shell is not what an SSH client is for.
  static bool get localTerminal => !mobile;

  /// Serial ports: USB on Android is a later phase; iOS has none.
  static bool get serialPorts => !mobile;

  /// FIDO2 security keys over USB HID. Phones reach them over NFC or USB,
  /// which nothing here speaks yet.
  static bool get securityKeys => !mobile;

  /// Programs of this device: ProxyCommand, `mosh-client`, an editor to
  /// open a remote file with, Finder or Explorer. Phones run none.
  static bool get runsPrograms => !mobile;

  /// An agent of the system (`SSH_AUTH_SOCK`, Pageant, 1Password).
  static bool get systemAgent => !mobile;

  /// A folder of this device the user browses (SFTP's left pane, `~/.ssh`,
  /// key files referred to by their path). On phones files come in through
  /// the system's picker and are copied, so they are imported instead.
  static bool get userFiles => !mobile;

  /// A dialog to choose where to save. On phones the file goes to the
  /// app's own documents, which Files (iOS) shows.
  static bool get saveDialog => !mobile;

  /// Other programs' settings on this device (PuTTY, MobaXterm, Termius…).
  static bool get installedPrograms => !mobile;

  /// Secure Enclave keys: macOS, and iOS with the same API.
  static bool get secureEnclave =>
      !Platform.isAndroid && (Platform.isMacOS || Platform.isIOS);
}

/// The phone's layout: one thing on the screen at a time, the hosts in a
/// drawer and the tabs in a list. Tablets wide enough keep the desktop's.
bool compactLayout(BuildContext context) =>
    Device.mobile && MediaQuery.sizeOf(context).width < 720;

/// Taps for what the desktop does with a double click (connect, open a
/// folder), and long presses for its right click.
bool get touchFirst => Device.mobile;
