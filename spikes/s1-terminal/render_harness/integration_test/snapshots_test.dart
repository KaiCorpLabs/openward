// Spike S1.6: screenshots to compare engines and renderers side by side.
//
//   fvm flutter test integration_test/snapshots_test.dart -d macos \
//     --dart-define=S1_SPIKE_DIR=$PWD/.. \
//     --dart-define=S1_SNAPSHOT_DIR=/tmp/s1-snapshots
//
// For every case, each engine is fed the same bytes and the screen is drawn
// with each renderer into <case>-<engine>-<renderer>.png. Cases: a box
// drawing and text sheet, the vttest screens listed below, every stop of
// the real-programs capture and each corpus recording halfway through.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:render_harness/src/rust/api/term.dart';
import 'package:render_harness/src/rust/frb_generated.dart';
import 'package:render_harness/term/frame.dart';
import 'package:render_harness/term/palette.dart';
import 'package:render_harness/term/renderer.dart';

const _spikeDir = String.fromEnvironment('S1_SPIKE_DIR');

/// Device pixel ratio to render at; Retina-class by default, whatever the
/// test window has.
final double _dpr = double.parse(
  const String.fromEnvironment('S1_SNAPSHOT_DPR', defaultValue: '2'),
);
const _outDir = String.fromEnvironment(
  'S1_SNAPSHOT_DIR',
  defaultValue: '/tmp/s1-snapshots',
);

/// vttest screens worth looking at (labels from vttest.ref.jsonl).
const _vttestScreens = [
  'main',
  '2 #14', // DEC line drawing with attributes
  '3 #0', // character sets
  '11.3.2.9 #0', // cursor movement within left/right margins
  '11.6.2 #0', // ISO 6429 color pattern
  '11.6.9 #0', // SGR 22-27
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  Future<void> shoot(String name, List<int> bytes, int cols, int rows) async {
    for (final engine in engineNames()) {
      final session = await createSession(
        engine: engine,
        cols: cols,
        rows: rows,
        scrollback: 1000,
      );
      await session.feed(data: bytes);
      final frame = decodeFrame(session.encodeNow().frame);
      for (final mode in RenderMode.values) {
        final renderer = TerminalRenderer(
          metrics: CellMetrics.measure(devicePixelRatio: _dpr),
          palette: TermPalette.dark,
          mode: mode,
          devicePixelRatio: _dpr,
        );
        renderer.apply(frame);
        final png = await renderer.snapshotPng(pixelRatio: _dpr);
        renderer.dispose();
        await File('$_outDir/$name-$engine-${mode.name}.png')
            .writeAsBytes(png!);
      }
      session.dispose();
    }
  }

  setUp(() => Directory(_outDir).createSync(recursive: true));

  testWidgets('box drawing and text sheet', (tester) async {
    await shoot('sheet', utf8.encode(_sheet()), 100, 30);
  });

  /// Screens of a conformance capture (corpus/conformance/<name>.*), all
  /// of them or those whose label is in [labels].
  Future<void> shootCapture(String name, {List<String>? labels}) async {
    final dir = '$_spikeDir/corpus/conformance';
    final raw = File('$dir/$name.out').readAsBytesSync();
    var cols = 80, rows = 24;
    for (final line in File('$dir/$name.ref.jsonl').readAsLinesSync()) {
      final r = jsonDecode(line) as Map<String, Object?>;
      final label = r['label'] as String?;
      if (label == null) {
        cols = r['cols'] as int;
        rows = r['rows'] as int;
        continue;
      }
      if (labels != null && !labels.contains(label)) continue;
      final offset = r['offset'] as int;
      final file = '$name-${label.replaceAll(RegExp(r'[ #.]+'), '_')}';
      await shoot(file, raw.sublist(0, offset), cols, rows);
    }
  }

  testWidgets('vttest screens', (tester) async {
    await shootCapture('vttest', labels: _vttestScreens);
  });

  testWidgets('real programs', (tester) async {
    await shootCapture('apps');
  });

  testWidgets('each corpus recording halfway through', (tester) async {
    final dir = Directory('$_spikeDir/corpus/casts');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.cast')) continue;
      final lines = f.readAsLinesSync();
      final header = jsonDecode(lines.first) as Map<String, Object?>;
      final term = header['term'] as Map<String, Object?>?;
      final cols = (header['width'] ?? term?['cols']) as int;
      final rows = (header['height'] ?? term?['rows']) as int;
      // Recordings end after the program quits: take the middle instead.
      final events = [
        for (final l in lines.skip(1)) jsonDecode(l) as List<Object?>,
      ];
      final out = BytesBuilder(copy: false);
      for (final e in events.take(events.length ~/ 2)) {
        if (e[1] == 'o') out.add(utf8.encode(e[2] as String));
      }
      final name = f.uri.pathSegments.last.replaceAll('.cast', '');
      await shoot('cast-$name', out.takeBytes(), cols, rows);
    }
  });
}

/// Box drawing, blocks, Powerline and styled text on one screen.
String _sheet() {
  final b = StringBuffer('\x1b[2J\x1b[H');
  b.write('Box drawing U+2500–U+257F:\r\n');
  for (var row = 0; row < 8; row++) {
    for (var i = 0; i < 16; i++) {
      b.write(String.fromCharCode(0x2500 + row * 16 + i));
      b.write(' ');
    }
    b.write('\r\n');
  }
  b.write('Blocks U+2580–U+259F: ');
  for (var i = 0x2580; i <= 0x259F; i++) {
    b.write(String.fromCharCode(i));
  }
  b.write('\r\n\r\n');
  // Joined shapes: the joins across cells are what fonts get wrong.
  const boxes = [
    '┌──────┬──────┐  ╔══════╦══════╗  ┏━━━━━━┳━━━━━━┓  ╭──────╮',
    '│ abc  │ def  │  ║ abc  ║ def  ║  ┃ abc  ┃ def  ┃  │ arc  │',
    '├──────┼──────┤  ╠══════╬══════╣  ┣━━━━━━╋━━━━━━┫  ╰──────╯',
    '│ ghi  │ jkl  │  ║ ghi  ║ jkl  ║  ┃ ghi  ┃ jkl  ┃  ╒══╤══╕',
    '└──────┴──────┘  ╚══════╩══════╝  ┗━━━━━━┻━━━━━━┛  ╘══╧══╛',
  ];
  for (final l in boxes) {
    b.write('$l\r\n');
  }
  b.write('\r\n████▓▓▓▓▒▒▒▒░░░░  ▁▂▃▄▅▆▇█  ▏▎▍▌▋▊▉█  ┄┄┄ ┈┈┈ ╌╌╌ ┆┊╎\r\n\r\n');
  b.write(
    '\x1b[44;37m user@host \x1b[34;42m\ue0b0\x1b[30m ~/src \x1b[32;49m\ue0b0\x1b[0m '
    '\ue0b1 \ue0b2 \ue0b3\r\n\r\n',
  );
  // Text: regular, bold, dim, italic, underline, inverse and colors.
  b.write(
    'Regular  The quick brown fox jumps over the lazy dog 0123456789\r\n',
  );
  b.write(
    '\x1b[1mBold     The quick brown fox jumps over the lazy dog 0123456789\x1b[0m\r\n',
  );
  b.write(
    '\x1b[2mDim      The quick brown fox jumps over the lazy dog 0123456789\x1b[0m\r\n',
  );
  b.write(
    '\x1b[3mItalic   The quick brown fox jumps over the lazy dog 0123456789\x1b[0m\r\n',
  );
  b.write('\x1b[4mUnder\x1b[0m    \x1b[7m inverse \x1b[0m ');
  for (var c = 0; c < 8; c++) {
    b.write('\x1b[3${c}m█\x1b[9${c}m█');
  }
  b.write('\x1b[0m\r\n');
  b.write(
    'Code     fn main() { let x = [1, 2]; println!("{x:?}"); } // ~!@#\$%^&*\r\n',
  );
  b.write('Unicode  café naïve 日本語 한국어 Ελληνικά العربية 🙂👍🏽\r\n');
  return b.toString();
}
