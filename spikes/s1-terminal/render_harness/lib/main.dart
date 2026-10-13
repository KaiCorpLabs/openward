// Spike S1.4: render harness. See docs/spikes/S1-terminal.md.
//
// Interactive: pick a workload and rate, press Start.
// Unattended: --dart-define=S1_AUTORUN=fullscreen:0:64,sgr-log:4:16 runs each
// spec, prints one `S1RESULT {json}` line per run and exits.

import 'dart:convert';
import 'dart:io' show exit;

import 'package:flutter/material.dart';

import 'bench/harness.dart';
import 'src/rust/api/term.dart';
import 'src/rust/frb_generated.dart';
import 'term/renderer.dart';

const _autorun = String.fromEnvironment('S1_AUTORUN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const HarnessApp());
}

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenWard S1 render harness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const HarnessPage(),
    );
  }
}

class HarnessPage extends StatefulWidget {
  const HarnessPage({super.key});

  @override
  State<HarnessPage> createState() => _HarnessPageState();
}

class _HarnessPageState extends State<HarnessPage>
    with SingleTickerProviderStateMixin {
  late final Harness _harness = Harness(vsync: this);
  final List<String> _workloads = workloadNames();
  String _workload = 'fullscreen';
  double _rate = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _harness.addListener(() => setState(() {}));
    _harness.init().then((_) {
      setState(() => _ready = true);
      if (_autorun.isNotEmpty) _runAutomatically();
    });
  }

  Future<void> _runAutomatically() async {
    for (final spec in _autorun.split(',').where((s) => s.isNotEmpty)) {
      final result = await _harness.run(RunSpec.parse(spec));
      // ignore: avoid_print
      print('S1RESULT ${jsonEncode(result)}');
    }
    exit(0);
  }

  @override
  void dispose() {
    _harness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _harness.running;
    return Scaffold(
      appBar: AppBar(
        title: const Text('S1 · render harness'),
        actions: [
          DropdownButton<String>(
            value: _workload,
            items: [
              for (final w in _workloads)
                DropdownMenuItem(value: w, child: Text(w)),
            ],
            onChanged: running ? null : (w) => setState(() => _workload = w!),
          ),
          const SizedBox(width: 12),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0, label: Text('máx')),
              ButtonSegment(value: 1, label: Text('1 MiB/s')),
              ButtonSegment(value: 8, label: Text('8 MiB/s')),
            ],
            selected: {_rate},
            onSelectionChanged: running
                ? null
                : (s) => setState(() => _rate = s.first),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: !_ready
                ? null
                : running
                ? _harness.stop
                : () => _harness.run(RunSpec(_workload, _rate, 32)),
            child: Text(running ? 'Stop' : 'Start'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TerminalView(
              renderer: _harness.renderer,
              cols: _harness.cols,
              rows: _harness.rows,
            ),
          ),
          _Stats(harness: _harness),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.harness});

  final Harness harness;

  @override
  Widget build(BuildContext context) {
    final r = harness.lastResult;
    final text = harness.running
        ? 'Ejecutando ${harness.current}… '
              '${(harness.fedBytes / 1048576).toStringAsFixed(1)} MiB enviados'
        : r == null
        ? '${harness.cols}×${harness.rows} · ${harness.engine}'
        : 'fps ${(r['fps'] as num).toStringAsFixed(0)} · '
              'latencia p95 ${_fmt(r['latency_ms'])} ms · '
              'raster p95 ${_fmt(r['raster_ms'])} ms · '
              'build p95 ${_fmt(r['build_ms'])} ms · '
              'record p95 ${_fmt(r['record_us'])} µs · '
              'congelados ${r['frozen_frames_over_100ms']}';
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black,
      child: Text(
        text,
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
      ),
    );
  }

  static String _fmt(Object? summary) {
    final p95 = (summary as Map?)?['p95'] as num?;
    return p95 == null ? '–' : p95.toStringAsFixed(1);
  }
}
