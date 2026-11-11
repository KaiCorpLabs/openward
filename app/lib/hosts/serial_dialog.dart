// Opening a serial port by hand: the port, its settings, and a tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../tabs/tabs.dart';
import '../ui/tokens.dart';
import 'editor/serial_fields.dart';

/// Asks for a port and its settings, and opens it in a new tab. The first
/// USB port there is comes chosen; the settings, those of the last one.
Future<void> showSerialOpen(BuildContext context, WidgetRef ref) =>
    showDialog<void>(context: context, builder: (_) => const _SerialOpen());

class _SerialOpen extends ConsumerStatefulWidget {
  const _SerialOpen();

  @override
  ConsumerState<_SerialOpen> createState() => _SerialOpenState();
}

class _SerialOpenState extends ConsumerState<_SerialOpen> {
  final _port = TextEditingController();
  var _line = lastSerialLine;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(openWardProvider).serialPorts().then((ports) {
      if (!mounted || _port.text.isNotEmpty || ports.isEmpty) return;
      setState(() => _port.text = ports.first.path);
    });
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  void _open() {
    final path = _port.text.trim();
    if (path.isEmpty) {
      setState(() => _error = context.l10n.serialPortMissing);
      return;
    }
    rememberSerialLine(_line);
    ref
        .read(tabsProvider.notifier)
        .openAddress(QuickTarget.serialPort(path, _line));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    return AlertDialog(
      icon: Icon(Icons.cable, color: c.textMuted),
      title: Text(l.serialOpenTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.serialOpenNote,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
            const SizedBox(height: OwSpace.s6),
            SerialPortField(
              controller: _port,
              autofocus: true,
              errorText: _error,
              onChanged: () {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: OwSpace.s6),
            SerialLineFields(
              line: _line,
              onChanged: (v) => setState(() => _line = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('serial.open'),
          onPressed: _open,
          child: Text(l.open),
        ),
      ],
    );
  }
}
