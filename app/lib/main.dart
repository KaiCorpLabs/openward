import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/rust/api/app.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  final app = await OpenWard.open(dataDir: dir.path);
  runApp(OpenWardApp(app: app));
}

/// Placeholder until milestone A3 (window, host sidebar, tabs): the saved
/// hosts, and importing ~/.ssh/config.
class OpenWardApp extends StatefulWidget {
  const OpenWardApp({super.key, required this.app});

  final OpenWard app;

  @override
  State<OpenWardApp> createState() => _OpenWardAppState();
}

class _OpenWardAppState extends State<OpenWardApp> {
  String? _status;

  Future<void> _import() async {
    final report = await widget.app.importSshConfig();
    setState(() => _status =
        '${report.created} importados, ${report.skipped} ya estaban, '
        '${report.warnings.length} avisos');
  }

  @override
  Widget build(BuildContext context) {
    final hosts = widget.app.hosts();
    return MaterialApp(
      title: 'OpenWard',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('OpenWard'),
          actions: [
            TextButton(
              onPressed: _import,
              child: const Text('Importar ~/.ssh/config'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_status != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_status!)),
            Expanded(
              child: ListView(
                children: [
                  for (final h in hosts)
                    ListTile(
                      title: Text(h.label),
                      subtitle: Text('${h.user}@${h.address}:${h.port}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
