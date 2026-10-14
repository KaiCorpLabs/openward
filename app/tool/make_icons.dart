// Draws the app icon and writes every size the platforms want:
//
//   fvm flutter test tool/make_icons.dart
//
// A shield (the "ward") with a prompt on a dark rounded square, on the
// macOS icon grid (an 824 px body on a 1024 px canvas). Regenerate after
// changing the drawing; the PNGs and the .ico are committed.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF12161B);

void _paint(Canvas c, double size) {
  c.scale(size / 1024);
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(100, 100, 824, 824),
    const Radius.circular(185),
  );
  c.drawRRect(
    body.shift(const Offset(0, 10)),
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
  );
  c.drawRRect(
    body,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF262E36), _ink],
      ).createShader(body.outerRect),
  );
  final shield = Path()
    ..moveTo(512, 232)
    ..cubicTo(596, 286, 684, 300, 756, 296)
    ..lineTo(756, 516)
    ..cubicTo(756, 650, 652, 744, 512, 806)
    ..cubicTo(372, 744, 268, 650, 268, 516)
    ..lineTo(268, 296)
    ..cubicTo(340, 300, 428, 286, 512, 232)
    ..close();
  c.drawPath(
    shield,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF45D6BF), Color(0xFF1E8F7E)],
      ).createShader(const Rect.fromLTWH(268, 232, 488, 574)),
  );
  final pen = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 58
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  c.drawPath(
    Path()
      ..moveTo(388, 424)
      ..lineTo(478, 506)
      ..lineTo(388, 588),
    pen,
  );
  c.drawLine(const Offset(532, 588), const Offset(640, 588), pen);
}

Future<Uint8List> _png(int size) async {
  final recorder = ui.PictureRecorder();
  _paint(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// An .ico whose entries are PNGs (Windows Vista and later).
Uint8List _ico(Map<int, Uint8List> pngs) {
  final header = BytesBuilder();
  final images = BytesBuilder();
  final count = pngs.length;
  final data = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, count, Endian.little);
  header.add(data.buffer.asUint8List());
  var offset = 6 + 16 * count;
  for (final MapEntry(key: size, value: png) in pngs.entries) {
    final entry = ByteData(16)
      ..setUint8(0, size >= 256 ? 0 : size)
      ..setUint8(1, size >= 256 ? 0 : size)
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

void main() {
  test('app icons', () async {
    const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      File('$mac/app_icon_$size.png').writeAsBytesSync(await _png(size));
    }
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
      _ico({
        for (final s in [16, 24, 32, 48, 64, 128, 256]) s: await _png(s),
      }),
    );
    // For the Linux .desktop entry and the docs.
    File('linux/openward.png').writeAsBytesSync(await _png(512));
  });
}
