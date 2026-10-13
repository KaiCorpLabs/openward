import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../src/rust/api/term.dart';
import '../term/frame.dart';
import '../term/palette.dart';
import '../term/renderer.dart';

/// One benchmark run: `workload:mibPerSec:totalMib`, e.g. `fullscreen:0:64`.
final class RunSpec {
  const RunSpec(this.workload, this.mibPerSec, this.totalMib);

  /// `typing:<seconds>` or `<workload>:<MiB/s>:<MiB>`.
  factory RunSpec.parse(String spec) {
    final parts = spec.split(':');
    if (parts[0] == typing) {
      return RunSpec(typing, 0, parts.length > 1 ? double.parse(parts[1]) : 15);
    }
    return RunSpec(
      parts[0],
      parts.length > 1 ? double.parse(parts[1]) : 0,
      parts.length > 2 ? double.parse(parts[2]) : 32,
    );
  }

  /// Keystroke echo workload; [totalMib] is its duration in seconds.
  static const typing = 'typing';

  final String workload;

  /// Feed rate; 0 means as fast as the core accepts it.
  final double mibPerSec;
  final double totalMib;

  @override
  String toString() => workload == typing
      ? 'typing, ${totalMib.toStringAsFixed(0)} s'
      : '$workload @ ${mibPerSec == 0 ? 'max' : '$mibPerSec MiB/s'}, $totalMib MiB';
}

/// Drives a [TermSession] at the display refresh rate and measures the
/// pipeline: core encode, Dart decode, row recording, Flutter build/raster
/// and input-to-paint latency.
class Harness extends ChangeNotifier {
  Harness({
    required TickerProvider vsync,
    this.engine = 'alacritty',
    this.cols = 200,
    this.rows = 50,
    this.scrollback = 10000,
    this.pipeline = const String.fromEnvironment(
      'S1_PIPELINE',
      defaultValue: 'sync',
    ),
  }) : renderer = TerminalRenderer(
         metrics: CellMetrics.measure(devicePixelRatio: _devicePixelRatio()),
         palette: TermPalette.dark,
         mode: RenderMode.values.byName(
           const String.fromEnvironment('S1_RENDERER', defaultValue: 'atlas'),
         ),
         devicePixelRatio: _devicePixelRatio(),
       ) {
    _ticker = vsync.createTicker(_onTick);
  }

  final String engine;
  final int cols;
  final int rows;
  final int scrollback;

  /// `sync`: encode inside the vsync tick and paint in the same refresh.
  /// `async`: encode on a worker; the result is painted one refresh later.
  final String pipeline;
  final TerminalRenderer renderer;
  late final Ticker _ticker;
  TermSession? _session;

  bool running = false;

  /// Aborts a run when no vsync arrives (window hidden or occluded: the
  /// platform stops producing frames, so nothing can be measured).
  Timer? _watchdog;
  final _sinceTick = Stopwatch();
  static const _noVsyncTimeout = Duration(seconds: 5);
  bool _inFlight = false;
  int fedBytes = 0;
  RunSpec? current;
  Map<String, Object?>? lastResult;

  final _latencyUs = <int>[];
  final _decodeUs = <int>[];
  final _recordUs = <int>[];
  final _encodeUs = <int>[];
  final _frameBytes = <int>[];
  final _buildUs = <int>[];
  final _rasterUs = <int>[];
  int _frozen = 0;
  final _wall = Stopwatch();

  /// Samples from the first half second (shader warm-up) are discarded.
  static const _warmupMicros = 500000;
  bool get _warm => _wall.elapsedMicroseconds > _warmupMicros;
  Completer<Map<String, Object?>>? _done;

  Future<void> init() async {
    _session = await createSession(
      engine: engine,
      cols: cols,
      rows: rows,
      scrollback: scrollback,
    );
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  Future<Map<String, Object?>> run(RunSpec spec) async {
    final session = _session!;
    for (final l in [
      _latencyUs,
      _decodeUs,
      _recordUs,
      _encodeUs,
      _frameBytes,
      _buildUs,
      _rasterUs,
    ]) {
      l.clear();
    }
    _frozen = 0;
    renderer.paragraphFallbacks = 0;
    current = spec;
    running = true;
    final startFed = fedBytes;
    _done = Completer();
    if (spec.workload == RunSpec.typing) {
      await session.startTyping(seconds: spec.totalMib, minMs: 60, maxMs: 180);
    } else {
      await session.startWorkload(
        workload: spec.workload,
        cols: cols,
        rows: rows,
        mibPerSec: spec.mibPerSec,
        totalMib: spec.totalMib,
      );
    }
    _wall
      ..reset()
      ..start();
    if (!_ticker.isActive) _ticker.start();
    _sinceTick
      ..reset()
      ..start();
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (running && _sinceTick.elapsed > _noVsyncTimeout) {
        debugPrint('S1 no vsync for $_noVsyncTimeout: is the window visible?');
        _session?.stopWorkload();
        _finish(error: 'no-vsync');
      }
    });
    notifyListeners();
    final result = await _done!.future;
    result['fed_mib'] = (fedBytes - startFed) / 1048576;
    return result;
  }

  void stop() => _session?.stopWorkload();

  /// Writes `<S1_SNAPSHOT_DIR>/<workload>-<renderer>.png` when set.
  Future<void> _saveSnapshot(RunSpec spec) async {
    const dir = String.fromEnvironment('S1_SNAPSHOT_DIR');
    if (dir.isEmpty) return;
    final png = await renderer.snapshotPng();
    if (png == null) return;
    await File('$dir/${spec.workload}-${renderer.mode.name}.png')
        .writeAsBytes(png);
  }

  static double _devicePixelRatio() {
    final views = PlatformDispatcher.instance.views;
    return views.isEmpty ? 2 : views.first.devicePixelRatio;
  }

  /// Refresh rate of the display the app runs on.
  double get refreshHz {
    final views = PlatformDispatcher.instance.views;
    final hz = views.isEmpty ? 0.0 : views.first.display.refreshRate;
    return hz > 0 ? hz : 60;
  }

  void _onTick(Duration _) {
    _sinceTick
      ..reset()
      ..start();
    final session = _session;
    if (session == null || _inFlight) return;
    if (pipeline == 'sync') {
      _onBatch(session.encodeNow());
      return;
    }
    _inFlight = true;
    session.encode().then(
      _onBatch,
      onError: (Object e) {
        _inFlight = false;
        debugPrint('encode failed: $e');
      },
    );
  }

  void _onBatch(FrameBatch batch) {
    _inFlight = false;
    final sw = Stopwatch()..start();
    final frame = decodeFrame(batch.frame);
    _decodeUs.add(sw.elapsedMicroseconds);
    _recordUs.add(renderer.apply(frame));
    _encodeUs.add(batch.encodeMicros);
    _frameBytes.add(batch.frame.length);
    fedBytes = batch.fedBytes.toInt();
    final oldest = batch.oldestInputMicros.toInt();
    if (oldest != 0 && _warm) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _latencyUs.add(nowMicros().toInt() - oldest);
      });
    }
    if (running && !batch.workloadRunning) _finish();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!running || !_warm) return;
    for (final t in timings) {
      _buildUs.add(t.buildDuration.inMicroseconds);
      _rasterUs.add(t.rasterDuration.inMicroseconds);
      if (t.totalSpan.inMilliseconds > 100) _frozen++;
    }
  }

  void _finish({String? error}) {
    if (!running) return;
    _watchdog?.cancel();
    running = false;
    _wall.stop();
    _ticker.stop();
    final spec = current!;
    final seconds = _wall.elapsedMicroseconds / 1e6;
    // Let the last post-frame callbacks and frame timings land.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 1200), () {
        final result = <String, Object?>{
          'kind': 'render',
          'engine': engine,
          'pipeline': pipeline,
          'renderer': renderer.mode.name,
          'atlas_glyphs': renderer.atlasGlyphs,
          'atlas_height_px': renderer.atlasHeightPx,
          'paragraph_fallbacks': renderer.paragraphFallbacks,
          'workload': spec.workload,
          'rate_mib_s': spec.mibPerSec,
          'cols': cols,
          'rows': rows,
          'platform': Platform.operatingSystem,
          'refresh_hz': refreshHz,
          'echo_gate_ms': 1000 / refreshHz + 4,
          'mode': kReleaseMode
              ? 'release'
              : (kProfileMode ? 'profile' : 'debug'),
          'seconds': seconds,
          'frames': _frameBytes.length,
          'fps': _frameBytes.length / seconds,
          'latency_ms': _summary(_latencyUs, 1e3),
          'build_ms': _summary(_buildUs, 1e3),
          'raster_ms': _summary(_rasterUs, 1e3),
          'encode_us': _summary(_encodeUs, 1),
          'decode_us': _summary(_decodeUs, 1),
          'record_us': _summary(_recordUs, 1),
          'frame_bytes_avg': _frameBytes.isEmpty
              ? 0
              : _frameBytes.reduce((a, b) => a + b) / _frameBytes.length,
          'frozen_frames_over_100ms': _frozen,
        };
        lastResult = result;
        notifyListeners();
        if (error != null) result['error'] = error;
        _saveSnapshot(spec)
            .catchError((Object e) => debugPrint('snapshot failed: $e'))
            .whenComplete(() => _done?.complete(result));
      });
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  static Map<String, num> _summary(List<int> samples, num divisor) {
    if (samples.isEmpty) return const {};
    final s = [...samples]..sort();
    num at(double q) => s[((s.length - 1) * q).round()] / divisor;
    return {
      'p50': at(0.5),
      'p95': at(0.95),
      'p99': at(0.99),
      'max': s.last / divisor,
      'n': s.length,
    };
  }

  @override
  void dispose() {
    _session?.stopWorkload();
    _ticker.dispose();
    renderer.dispose();
    super.dispose();
  }
}
