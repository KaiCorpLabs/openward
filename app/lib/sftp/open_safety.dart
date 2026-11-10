// A remote file opened here comes from the server: its name, its
// contents and whether it runs are the server's to choose. So the copy is
// marked as come from outside, as a browser marks a download, it loses
// the bit that would let it run, and the types the system runs rather
// than opens are asked about first.

import 'dart:io';

/// The types that each system runs, or installs, when told to open them:
/// not opened in a program but run as one. With no execute bit (taken
/// from the copy) a script or an AppImage no longer runs, so these are the
/// ones that still would.
const _runs = {
  'windows': {
    'appref-ms',
    'application',
    'appx',
    'appxbundle',
    'bat',
    'chm',
    'cmd',
    'com',
    'cpl',
    'diagcab',
    'exe',
    'hta',
    'inf',
    'jar',
    'js',
    'jse',
    'library-ms',
    'lnk',
    'msc',
    'msi',
    'msix',
    'msixbundle',
    'msp',
    'mst',
    'pif',
    'ps1',
    'psd1',
    'psm1',
    'py',
    'pyw',
    'reg',
    'scf',
    'scr',
    'settingcontent-ms',
    'url',
    'vbe',
    'vbs',
    'wsf',
    'wsh',
  },
  'macos': {
    'command',
    'fileloc',
    'jar',
    'jnlp',
    'mpkg',
    'pkg',
    'terminal',
    'tool',
  },
  'linux': {
    'appimage',
    'bin',
    'deb',
    'desktop',
    'flatpakref',
    'jar',
    'rpm',
    'run',
    'sh',
  },
};

/// The extension of `name` when the system `os` (as
/// [Platform.operatingSystem]) runs that type instead of opening it;
/// null for one that opens. Windows drops the dots and spaces a name ends
/// in, so `x.exe.` is `x.exe` there.
String? runsWhenOpened(String name, {String? os}) {
  final system = os ?? Platform.operatingSystem;
  var n = name.toLowerCase();
  if (system == 'windows') n = n.replaceFirst(RegExp(r'[. ]+$'), '');
  final dot = n.lastIndexOf('.');
  if (dot <= 0) return null;
  final ext = n.substring(dot + 1);
  return (_runs[system] ?? const {}).contains(ext) ? ext : null;
}

/// Marks the copy at `path` as come from outside, as a browser would, and
/// takes away its execute bits: macOS asks before running it
/// (`com.apple.quarantine`), Windows opens it in Protected View or warns
/// (`Zone.Identifier`, zone 3: Internet). Before its time and size are
/// taken: on Windows the mark changes them. Each part is done if it can
/// be; the file opens anyway.
Future<void> markFromOutside(String path) async {
  if (Platform.isWindows) {
    try {
      await File('$path:Zone.Identifier')
          .writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n', flush: true);
    } on FileSystemException {
      // Not NTFS (a FAT disk): it has nowhere to go.
    }
    return;
  }
  final mode = (await File(path).stat()).mode & 0x1ff;
  if (mode & 0x49 != 0) {
    // dart:io has no chmod.
    await Process.run('chmod', [(mode & ~0x49).toRadixString(8), path]);
  }
  if (Platform.isMacOS) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // As Safari and Chrome write it: flags, time in hex, who brought it.
    await Process.run('/usr/bin/xattr', [
      '-w',
      'com.apple.quarantine',
      '0081;${now.toRadixString(16)};OpenWard;',
      path,
    ]);
  }
}
