// A serial port's settings, and the port itself picked from this
// computer's: for a host's editor and for opening one by hand.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address.dart' show defaultSerialLine;
import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/app.dart';
import '../../src/rust/api/vault.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// The speeds a port is usually set to; another one stays as it is.
const serialBauds = [
  300,
  1200,
  2400,
  4800,
  9600,
  19200,
  38400,
  57600,
  115200,
  230400,
  460800,
  921600,
];

extension SerialLineChange on SerialLineSpec {
  SerialLineSpec copyWith({
    int? baud,
    int? dataBits,
    ParityKind? parity,
    int? stopBits,
    FlowKind? flow,
  }) => SerialLineSpec(
    baud: baud ?? this.baud,
    dataBits: dataBits ?? this.dataBits,
    parity: parity ?? this.parity,
    stopBits: stopBits ?? this.stopBits,
    flow: flow ?? this.flow,
  );

  /// `8N1`, `7E2`.
  String get frame =>
      '$dataBits${switch (parity) {
        ParityKind.none => 'N',
        ParityKind.odd => 'O',
        ParityKind.even => 'E',
      }}$stopBits';
}

/// «9600 baudios, 8N1, sin control de flujo».
String serialSummary(AppLocalizations l, SerialLineSpec s) =>
    l.serialSummary(s.baud, s.frame, switch (s.flow) {
      FlowKind.none => l.serialSummaryNoFlow,
      FlowKind.software => 'XON/XOFF',
      FlowKind.hardware => 'RTS/CTS',
    });

/// What a serial port is called on this system, for a hint.
String get serialPortExample => Platform.isWindows
    ? 'COM3'
    : Platform.isMacOS
    ? '/dev/cu.usbserial-…'
    : '/dev/ttyUSB0';

/// Speed, data bits, parity, stop bits and flow control.
class SerialLineFields extends StatelessWidget {
  const SerialLineFields({
    super.key,
    required this.line,
    required this.onChanged,
    this.autofocus = false,
  });

  final SerialLineSpec line;
  final ValueChanged<SerialLineSpec> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = fieldTextStyle(context);
    Widget pick<T>(
      String key,
      String label,
      T value,
      List<(T, String)> choices,
      ValueChanged<T> changed, {
      bool focus = false,
    }) => DropdownButtonFormField<T>(
      key: ValueKey('serial.$key'),
      style: style,
      autofocus: focus,
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final (v, text) in choices)
          DropdownMenuItem(value: v, child: Text(text)),
      ],
      onChanged: (v) {
        if (v != null) changed(v);
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pick<int>(
          'baud',
          l.serialBaud,
          line.baud,
          [
            for (final b in {...serialBauds, line.baud}.toList()..sort())
              (b, l.serialBaudUnit(b)),
          ],
          (b) => onChanged(line.copyWith(baud: b)),
          focus: autofocus,
        ),
        const SizedBox(height: OwSpace.s5),
        Row(
          children: [
            Expanded(
              child: pick<int>('dataBits', l.serialDataBits, line.dataBits, [
                for (final b in [5, 6, 7, 8]) (b, '$b'),
              ], (b) => onChanged(line.copyWith(dataBits: b))),
            ),
            const SizedBox(width: OwSpace.s5),
            Expanded(
              child: pick<ParityKind>('parity', l.serialParity, line.parity, [
                (ParityKind.none, l.parityNone),
                (ParityKind.odd, l.parityOdd),
                (ParityKind.even, l.parityEven),
              ], (p) => onChanged(line.copyWith(parity: p))),
            ),
            const SizedBox(width: OwSpace.s5),
            Expanded(
              child: pick<int>('stopBits', l.serialStopBits, line.stopBits, [
                (1, '1'),
                (2, '2'),
              ], (b) => onChanged(line.copyWith(stopBits: b))),
            ),
          ],
        ),
        const SizedBox(height: OwSpace.s5),
        pick<FlowKind>('flow', l.serialFlow, line.flow, [
          (FlowKind.none, l.flowNone),
          (FlowKind.software, l.flowSoftware),
          (FlowKind.hardware, l.flowHardware),
        ], (f) => onChanged(line.copyWith(flow: f))),
      ],
    );
  }
}

/// The port, typed or picked from this computer's (looked for each time
/// the list opens: a cable plugged in a moment ago is there).
class SerialPortField extends ConsumerWidget {
  const SerialPortField({
    super.key,
    required this.controller,
    this.focusNode,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? errorText;
  final bool autofocus;
  final VoidCallback? onChanged;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    final ports = await ref.read(openWardProvider).serialPorts();
    if (!context.mounted || box == null) return;
    final at = box.localToGlobal(Offset(0, box.size.height));
    final chosen = await showMenu<SerialPortView>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + box.size.width, 0),
      constraints: BoxConstraints(minWidth: box.size.width),
      items: [
        if (ports.isEmpty)
          PopupMenuItem(enabled: false, child: Text(l.serialPortsNone)),
        for (final p in ports)
          PopupMenuItem(
            value: p,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.path, style: monoStyle(context, size: OwText.body)),
                if (p.description.isNotEmpty)
                  Text(
                    p.description,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: context.ow.colors.textSubtle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    if (chosen != null) {
      controller.text = chosen.path;
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return TextField(
      key: const ValueKey('serial.port'),
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: (_) => onChanged?.call(),
      style: monoStyle(
        context,
        size: OwText.body,
        color: context.ow.colors.text,
      ),
      decoration: InputDecoration(
        hintText: serialPortExample,
        errorText: errorText,
        // The list opens under the whole field: this widget's own box.
        suffixIcon: IconButton(
          key: const ValueKey('serial.ports'),
          tooltip: l.serialPortsTooltip,
          icon: const Icon(Icons.usb),
          onPressed: () => _pick(context, ref),
        ),
      ),
    );
  }
}

/// The settings a port opened by hand starts with.
SerialLineSpec get lastSerialLine => _lastSerialLine;
SerialLineSpec _lastSerialLine = defaultSerialLine;

/// Remembers `line` for the next port opened by hand, while the app runs.
void rememberSerialLine(SerialLineSpec line) => _lastSerialLine = line;
