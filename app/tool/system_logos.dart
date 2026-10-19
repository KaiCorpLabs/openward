// Writes lib/ui/system_logos.dart: the outline of each system's logo, from
// a fixed version of Simple Icons (CC0 1.0; the logos are their owners'
// trademarks). From app/:
//
//   dart run tool/system_logos.dart
//
// A system whose logo is not here (a code from a newer version, macOS and
// Windows) keeps its monogram or the neutral icon of ui/environment.dart.

import 'dart:convert';
import 'dart:io';

const version = '16.34.0';

/// The system's code (openward-app::system) and its Simple Icons slug.
const slugs = {
  'deb': 'debian',
  'rpi': 'raspberrypi',
  'ubu': 'ubuntu',
  'mint': 'linuxmint',
  'pop': 'popos',
  'elem': 'elementary',
  'zor': 'zorin',
  'kali': 'kalilinux',
  'fed': 'fedora',
  'rhel': 'redhat',
  'cent': 'centos',
  'rock': 'rockylinux',
  'alma': 'almalinux',
  'alp': 'alpinelinux',
  'arch': 'archlinux',
  'manj': 'manjaro',
  'endv': 'endeavouros',
  'suse': 'opensuse',
  'nix': 'nixos',
  'gent': 'gentoo',
  'void': 'voidlinux',
  'owrt': 'openwrt',
  'bsd': 'freebsd',
  'obsd': 'openbsd',
  'nbsd': 'netbsd',
  'lnx': 'linux',
};

/// Only what a path's data can hold: what comes from outside goes into a
/// Dart string literal.
final _pathData = RegExp(r'^[MmLlHhVvCcSsQqTtAaZz0-9.,\-\s]+$');

Future<void> main() async {
  final client = HttpClient();
  final out = StringBuffer()
    ..writeln('// Written by tool/system_logos.dart from Simple Icons $version')
    ..writeln(
      '// (CC0 1.0); do not edit. The logos are their owners\' trademarks,',
    )
    ..writeln('// shown only to tell what system a server runs.')
    ..writeln()
    ..writeln('/// Each system\'s logo, as SVG path data in a 24×24 box.')
    ..writeln('const systemLogos = <String, String>{');
  for (final MapEntry(key: code, value: slug) in slugs.entries) {
    final url = Uri.parse(
      'https://cdn.jsdelivr.net/npm/simple-icons@$version/icons/$slug.svg',
    );
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('$url: ${response.statusCode}');
    }
    final svg = await response.transform(utf8.decoder).join();
    if (!svg.contains('viewBox="0 0 24 24"')) {
      throw Exception('$slug: not a 24×24 box');
    }
    final paths = RegExp(r'<path d="([^"]+)"').allMatches(svg).toList();
    if (paths.length != 1) throw Exception('$slug: ${paths.length} paths');
    final d = paths.single.group(1)!;
    if (!_pathData.hasMatch(d)) throw Exception('$slug: unexpected path data');
    // As dart format leaves it.
    out
      ..writeln('  // $slug')
      ..writeln("  '$code': '$d',");
  }
  out.writeln('};');
  client.close();
  await File('lib/ui/system_logos.dart').writeAsString(out.toString());
  stdout.writeln('lib/ui/system_logos.dart: ${slugs.length} logos');
}
