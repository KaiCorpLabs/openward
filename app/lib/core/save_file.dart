import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'platform.dart';

const _channel = MethodChannel('openward/files');

/// Where a file the app makes (a backup, the recovery kit, a key, a log)
/// is written: what the user chose on the desktop; on a phone, a copy of
/// its own, handed to the system's "save to" sheet by [finish].
class SaveTarget {
  SaveTarget._(this.path, this.name, this._staged);

  /// Where to write it now.
  final String path;

  /// Its name, as suggested.
  final String name;
  final bool _staged;

  /// What to tell the user where it went: the path on the desktop; on a
  /// phone, the name (the system's sheet said where).
  String get shown => _staged ? name : path;

  /// On a phone, shows the system's sheet to save the file (Files on iOS,
  /// the document picker on Android) and deletes the app's copy, saved or
  /// not. False when the user cancelled there. On the desktop, nothing.
  Future<bool> finish() async {
    if (!_staged) return true;
    try {
      return await _channel.invokeMethod<bool>('export', {
            'path': path,
            'name': name,
          }) ??
          false;
    } finally {
      await _forget();
    }
  }

  /// Gives up: on a phone, the app's copy goes.
  Future<void> cancel() => _staged ? _forget() : Future.value();

  Future<void> _forget() async {
    try {
      await File(path).parent.delete(recursive: true);
    } on FileSystemException {
      /* Already gone. */
    }
  }
}

/// Asks where to save `suggestedName`. On a phone nothing is asked yet:
/// the file is written in the app's caches, and [SaveTarget.finish] asks.
Future<SaveTarget?> chooseSave(
  String suggestedName, {
  List<XTypeGroup> types = const [],
}) async {
  if (Device.saveDialog) {
    final to = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: types,
    );
    return to == null ? null : SaveTarget._(to.path, suggestedName, false);
  }
  final tmp = await getTemporaryDirectory();
  final id = Random.secure().nextInt(1 << 32).toRadixString(16);
  final dir = await Directory('${tmp.path}/export-$id').create(recursive: true);
  return SaveTarget._('${dir.path}/$suggestedName', suggestedName, true);
}

/// A file of this device saved where the user chooses, through the
/// system's sheet: SFTP's local files on a phone.
Future<bool> exportFile(String path) async {
  try {
    return await _channel.invokeMethod<bool>('export', {
          'path': path,
          'name': path.split(Platform.pathSeparator).last,
        }) ??
        false;
  } on MissingPluginException {
    return false;
  }
}

/// Opens a file of the user's. On a phone with no filter: iOS asks for
/// type identifiers the desktop's extensions lack, and both copy the file
/// for the app, so its path is only good for reading it now.
Future<XFile?> pickFile({List<XTypeGroup> types = const []}) =>
    openFile(acceptedTypeGroups: Device.mobile ? const [] : types);
