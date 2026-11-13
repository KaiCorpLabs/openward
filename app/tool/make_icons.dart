// Packages the approved Umbral artwork; never redraws the old shield.
// From app/: fvm flutter test --no-pub tool/make_icons.dart
// Desktop (macOS, Windows, Linux) and phones (iOS AppIcon, Android launcher).
// Sources and integration notes: ../../assets/brand/umbral/README.md.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _brand = '../assets/brand/umbral';
const _sizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024];
const _macSizes = [16, 32, 64, 128, 256, 512, 1024];
const _icoSizes = [16, 24, 32, 48, 64, 128, 256];

class _Artwork {
  const _Artwork(this.master, this.mark, this.background);

  final ui.Image master;
  final ui.Image mark;
  final Color background;

  void dispose() {
    master.dispose();
    mark.dispose();
  }
}

Future<ui.Image> _load(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  if (image.width != 1024 || image.height != 1024) {
    image.dispose();
    throw FormatException('Expected a 1024 x 1024 Umbral source: $path');
  }
  return image;
}

Future<_Artwork> _artwork(String appearance) async {
  final light = appearance == 'light';
  final mark = light ? 'positive' : 'teal';
  return _Artwork(
    await _load('$_brand/masters/umbral-$appearance-1024.png'),
    await _load('$_brand/png/$mark/umbral-$mark-1024.png'),
    light ? const Color(0xFFF3F0EA) : const Color(0xFF12161B),
  );
}

void _paint(Canvas c, _Artwork art, int size) {
  c.scale(size / 1024);
  // Keep OpenWard's existing macOS grid: 824 px body, 100 px inset.
  // The masters are opaque squares. macOS does not mask them for us.
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(100, 100, 824, 824),
    const Radius.circular(185),
  );
  if (size >= 64) {
    c.drawRRect(
      body.shift(const Offset(0, 10)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }
  c.save();
  c.clipRRect(body, doAntiAlias: true);
  final paint = Paint()..filterQuality = FilterQuality.high;
  const source = Rect.fromLTWH(0, 0, 1024, 1024);
  if (size <= 32) {
    // Use the approved flat mark at its original canvas scale. This gives
    // the opening and detached chevron more room than the dimensional mark.
    c.drawColor(art.background, BlendMode.srcOver);
    c.drawImageRect(art.mark, source, source, paint);
  } else {
    c.drawImageRect(art.master, source, body.outerRect, paint);
  }
  c.restore();
}

Future<Uint8List> _png(_Artwork art, int size) async {
  final recorder = ui.PictureRecorder();
  _paint(Canvas(recorder), art, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// An .ico whose entries are PNGs (Windows Vista and later).
Uint8List _ico(Map<int, Uint8List> pngs) {
  final header = BytesBuilder();
  final images = BytesBuilder();
  final data = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, pngs.length, Endian.little);
  header.add(data.buffer.asUint8List());
  var offset = 6 + 16 * pngs.length;
  for (final MapEntry(key: size, value: png) in pngs.entries) {
    final entry = ByteData(16)
      ..setUint8(0, size == 256 ? 0 : size)
      ..setUint8(1, size == 256 ? 0 : size)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    header.add(entry.buffer.asUint8List());
    images.add(png);
    offset += png.length;
  }
  return Uint8List.fromList([...header.takeBytes(), ...images.takeBytes()]);
}

Future<void> _write(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

Future<void> _icns(String appearance, Map<int, Uint8List> pngs) async {
  // This is a local inspection export. Xcode builds the app's AppIcon.icns
  // from AppIcon.appiconset; it does not consume this file.
  if (!Platform.isMacOS) return;
  final iconset = 'build/branding/umbral-$appearance.iconset';
  for (final size in [16, 32, 128, 256, 512]) {
    await _write('$iconset/icon_${size}x$size.png', pngs[size]!);
    await _write('$iconset/icon_${size}x$size@2x.png', pngs[size * 2]!);
  }
  final result = await Process.run('iconutil', [
    '--convert',
    'icns',
    '--output',
    'build/branding/umbral-$appearance.icns',
    iconset,
  ]);
  if (result.exitCode != 0) {
    throw StateError('iconutil failed: ${result.stderr}');
  }
}

/// iOS: the opaque master, full bleed (iOS rounds it), as each slot of
/// AppIcon.appiconset asks; the smallest from the flat mark, as on the
/// desktop.
Future<Uint8List> _iosPng(_Artwork art, int size) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder)..scale(size / 1024);
  final paint = Paint()..filterQuality = FilterQuality.high;
  const square = Rect.fromLTWH(0, 0, 1024, 1024);
  if (size <= 40) {
    c.drawColor(art.background, BlendMode.srcOver);
    c.drawImageRect(art.mark, square, square, paint);
  } else {
    c.drawImageRect(art.master, square, square, paint);
  }
  return _render(recorder, size);
}

/// Android's adaptive icon: the flat mark alone, on a 108 dp canvas whose
/// middle 66 dp the launcher always shows; the background is a color.
Future<Uint8List> _androidForeground(ui.Image mark, int size) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder)..scale(size / 108);
  // The mark's 1024 canvas keeps its own clear space: on 72 dp, its
  // silhouette stays inside the 66 dp safe circle.
  c.drawImageRect(
    mark,
    const Rect.fromLTWH(0, 0, 1024, 1024),
    const Rect.fromLTWH(18, 18, 72, 72),
    Paint()..filterQuality = FilterQuality.high,
  );
  return _render(recorder, size);
}

Future<Uint8List> _render(ui.PictureRecorder recorder, int size) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Android densities: the legacy 48 dp icon and the 108 dp adaptive layer.
const _androidDensities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

Future<void> _phones() async {
  final art = await _artwork('dark');
  final mono = await _load('$_brand/png/positive/umbral-positive-1024.png');
  try {
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final slots =
        (jsonDecode(await File('$ios/Contents.json').readAsString())
                as Map<String, dynamic>)['images']
            as List<dynamic>;
    for (final slot in slots.cast<Map<String, dynamic>>()) {
      final points = double.parse((slot['size'] as String).split('x').first);
      final scale = double.parse((slot['scale'] as String).replaceAll('x', ''));
      final size = (points * scale).round();
      await _write('$ios/${slot['filename']}', await _iosPng(art, size));
    }
    const res = 'android/app/src/main/res';
    for (final MapEntry(key: density, value: k) in _androidDensities.entries) {
      await _write(
        '$res/mipmap-$density/ic_launcher.png',
        await _png(art, (48 * k).round()),
      );
      await _write(
        '$res/mipmap-$density/ic_launcher_foreground.png',
        await _androidForeground(art.mark, (108 * k).round()),
      );
      await _write(
        '$res/mipmap-$density/ic_launcher_monochrome.png',
        await _androidForeground(mono, (108 * k).round()),
      );
    }
  } finally {
    art.dispose();
    mono.dispose();
  }
}

void main() {
  test('package Umbral app icons', () async {
    for (final appearance in ['dark', 'light']) {
      final art = await _artwork(appearance);
      final pngs = <int, Uint8List>{};
      try {
        for (final size in _sizes) {
          final png = await _png(art, size);
          pngs[size] = png;
          await _write('build/branding/$appearance/app_icon_$size.png', png);
        }
      } finally {
        art.dispose();
      }
      final ico = _ico({for (final size in _icoSizes) size: pngs[size]!});
      await _write('build/branding/umbral-$appearance.ico', ico);
      await _icns(appearance, pngs);
      // Graphite is the selected default on every desktop platform.
      // Keep light as an export, without adding an appearance-switching feature.
      if (appearance == 'dark') {
        const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
        for (final size in _macSizes) {
          await _write('$mac/app_icon_$size.png', pngs[size]!);
        }
        await _write('windows/runner/resources/app_icon.ico', ico);
        await _write('linux/openward.png', pngs[512]!);
      }
    }
  });

  test('package Umbral phone icons', _phones);
}
