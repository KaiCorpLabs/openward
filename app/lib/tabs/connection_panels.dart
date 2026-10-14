// What a tab shows about its connection besides the terminal: progress hop
// by hop, a lost connection coming back, a failure with what to do about
// it, the details of a live connection, and a host key that changed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import 'messages.dart';

TextStyle? _mono(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'Menlo');

/// The route, hop by hop: done, in progress (and what it is doing), or
/// still ahead.
class _RouteSteps extends StatelessWidget {
  const _RouteSteps({required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final stage = c.stage;
    final current = stage?.hop ?? 0;
    final steps = c.route.isEmpty ? [c.label] : c.route;
    Widget row(Widget icon, String text, {String? detail, bool dim = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 20, height: 20, child: Center(child: icon)),
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: dim ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: 8),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          Icon(Icons.laptop, size: 16, color: theme.colorScheme.primary),
          'Este equipo',
        ),
        for (var i = 0; i < steps.length; i++)
          if (i < current)
            row(
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              steps[i],
            )
          else if (i == current && stage != null)
            row(
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              steps[i],
              detail: switch (stage.stage) {
                StageKind.connecting => 'conectando…',
                StageKind.authenticating => 'autenticando…',
                StageKind.openingShell => 'abriendo el shell…',
              },
            )
          else
            row(
              Icon(
                Icons.radio_button_unchecked,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              steps[i],
              dim: true,
            ),
      ],
    );
  }
}

/// Over an empty terminal while the first connection comes up.
class ConnectingCard extends StatelessWidget {
  const ConnectingCard({super.key, required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Conectando con ${controller.label}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _RouteSteps(controller: controller),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Across the top of a terminal whose connection was lost: why, the
/// countdown to the next try, and what to do instead.
class ReconnectBanner extends StatefulWidget {
  const ReconnectBanner({super.key, required this.controller});

  final TerminalController controller;

  @override
  State<ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<ReconnectBanner> {
  late final Timer _tick = Timer.periodic(
    const Duration(milliseconds: 250),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    final r = c.reconnecting;
    final at = c.reconnectAt;
    final String text;
    if (at != null) {
      final left = at.difference(DateTime.now()).inMilliseconds;
      final secs = (left / 1000).ceil().clamp(0, 60);
      final reason = r == null ? '' : failureText(r.reason);
      final why = reason.isEmpty
          ? ''
          : ' (${reason.endsWith('.') ? reason.substring(0, reason.length - 1) : reason})';
      text =
          'Conexión perdida$why. Reconectando en $secs s'
          '${r != null && r.attempt > 1 ? ' · intento ${r.attempt}' : ''}…';
    } else {
      final s = c.stage;
      text = s == null ? 'Reconectando…' : 'Reconectando: ${stageText(s)}';
    }
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem,
              size: 18,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
            if (at != null)
              TextButton(
                onPressed: c.start,
                child: const Text('Reconectar ya'),
              ),
            TextButton(onPressed: c.cancel, child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}

/// Over a terminal that never connected: what went wrong and what can be
/// done.
class FailureCard extends ConsumerWidget {
  const FailureCard({super.key, required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = controller;
    final failure = c.closed?.failure;
    final changed = failure?.kind == FailureKind.hostKeyChanged;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    changed ? Icons.gpp_maybe : Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      changed
                          ? 'La clave de ${failure!.label} ha cambiado'
                          : 'No se ha podido conectar con ${c.label}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(statusText(c)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (changed)
                    TextButton(
                      onPressed: () => showHostKeyChanged(context, ref, c),
                      child: const Text('Revisar la clave…'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: c.start,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The new and the old fingerprints of a host whose key changed; trusting
/// the new one takes an explicit confirmation.
Future<void> showHostKeyChanged(
  BuildContext context,
  WidgetRef ref,
  TerminalController c,
) async {
  final f = c.closed?.failure;
  if (f == null || f.kind != FailureKind.hostKeyChanged) return;
  final trusted = await showDialog<bool>(
    context: context,
    builder: (context) => _HostKeyChangedDialog(failure: f),
  );
  if (trusted != true) return;
  try {
    await ref
        .read(openWardProvider)
        .trustHostKey(host: f.host, port: f.port, key: f.key);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se ha podido guardar la clave: $e')),
      );
    }
    return;
  }
  c.start();
}

class _HostKeyChangedDialog extends StatefulWidget {
  const _HostKeyChangedDialog({required this.failure});

  final FailureView failure;

  @override
  State<_HostKeyChangedDialog> createState() => _HostKeyChangedDialogState();
}

class _HostKeyChangedDialogState extends State<_HostKeyChangedDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.failure;
    final where = f.port == 22 ? f.host : '${f.host}:${f.port}';
    final inOpenSsh = f.previous.any((p) => p.source == KeySourceKind.openSsh);
    return AlertDialog(
      icon: Icon(Icons.gpp_maybe, color: theme.colorScheme.error, size: 32),
      title: Text('La clave de ${f.label} ha cambiado'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$where se presenta con una clave distinta de la que tenías '
              'como buena. Puede que el servidor se haya reinstalado o haya '
              'cambiado de clave, pero también que alguien esté interceptando '
              'la conexión. No sigas sin comprobar la huella nueva con quien '
              'administra el servidor.',
            ),
            const SizedBox(height: 16),
            Text('Antes', style: theme.textTheme.titleSmall),
            for (final p in f.previous)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(p.fingerprint, style: _mono(context)),
                    Text(
                      p.source == KeySourceKind.openWard
                          ? 'guardada en OpenWard'
                          : 'en ~/.ssh/known_hosts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('Ahora (${f.algorithm})', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(f.fingerprint, style: _mono(context)),
            if (inOpenSsh) ...[
              const SizedBox(height: 12),
              Text(
                'OpenWard no modifica ~/.ssh/known_hosts: ssh seguirá '
                'avisando hasta que quites la clave vieja de allí '
                '(ssh-keygen -R ${f.port == 22 ? f.host : '"[${f.host}]:${f.port}"'}).',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('He comprobado la huella nueva'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _checked ? () => Navigator.pop(context, true) : null,
          child: const Text('Confiar en la clave nueva'),
        ),
      ],
    );
  }
}

/// The details of a live connection.
Future<void> showConnectionInfo(BuildContext context, TerminalController c) {
  final k = c.connected;
  if (k == null) return Future.value();
  final where = k.port == 22 ? k.host : '${k.host}:${k.port}';
  final trust = switch (k.trust) {
    TrustKind.known => 'conocida',
    TrustKind.new_ => 'nueva, guardada ahora',
    TrustKind.certified => 'certificada por la CA ${k.ca}',
  };
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      Widget row(String name, String value, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                name,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: SelectableText(value, style: mono ? _mono(context) : null),
            ),
          ],
        ),
      );
      return AlertDialog(
        title: Text(c.label),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Destino', where),
              if (c.route.length > 1)
                row('Ruta', ['este equipo', ...c.route].join(' → ')),
              row(
                'Intercambio',
                k.postQuantum ? '${k.kex} (poscuántico)' : k.kex,
                mono: true,
              ),
              if (!k.postQuantum)
                Padding(
                  padding: const EdgeInsets.only(left: 140, bottom: 4),
                  child: Text(
                    'El servidor no ofrece un intercambio poscuántico '
                    '(mlkem768x25519; OpenSSH lo trae desde la 10.0).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              row('Cifrado', k.cipher, mono: true),
              row('Clave del host', k.hostKeyAlgorithm, mono: true),
              row('Huella', k.fingerprint, mono: true),
              row('Confianza', trust),
              row('Tiempo', '${k.connectMs.round()} ms'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: k.fingerprint));
              Navigator.pop(context);
            },
            child: const Text('Copiar huella'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}
