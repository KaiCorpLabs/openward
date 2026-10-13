import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/vault.dart';

/// Imports `~/.ssh/config` and shows what came in and what did not.
Future<void> importSshConfig(BuildContext context, WidgetRef ref) async {
  final ImportReport report;
  try {
    report = await ref.read(openWardProvider).importSshConfig();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se ha podido importar: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _ReportDialog(report: report),
  );
}

String _summary(ImportReport r) {
  if (r.created == 0 && r.skipped == 0) {
    return 'No hay hosts en ~/.ssh/config (o no existe).';
  }
  final parts = [
    if (r.created > 0)
      r.created == 1 ? '1 host nuevo' : '${r.created} hosts nuevos',
    if (r.skipped > 0)
      r.skipped == 1
          ? '1 ya estaba importado y no se ha tocado'
          : '${r.skipped} ya estaban importados y no se han tocado',
  ];
  return '${parts.join('; ')}. Están en el grupo «~/.ssh/config».';
}

String _warning(ImportWarning w) {
  final at = w.line > 0 ? ' (${_short(w.file)}:${w.line})' : '';
  return switch (w.kind) {
    ImportWarningKind.unsupported => '${w.subject}: no se importa$at.',
    ImportWarningKind.match =>
      'Bloque Match$at: OpenWard no lo evalúa y sus líneas se han saltado.',
    ImportWarningKind.badValue =>
      'Valor no válido en ${w.subject}$at: ${w.detail}.',
    ImportWarningKind.stricter =>
      'StrictHostKeyChecking no$at: se importa como «aceptar nuevas»; una '
          'clave que cambia nunca se acepta sin preguntar.',
    ImportWarningKind.includeTooDeep => 'Include anidado demasiado hondo$at.',
    ImportWarningKind.unreadable =>
      'No se ha podido leer ${_short(w.file)}: ${w.subject}.',
    ImportWarningKind.jumpLossy =>
      '${w.subject} salta por ${w.detail}, que no es un host importado: '
          'se guarda como dirección, sin sus claves ni su ruta.',
  };
}

String _short(String path) {
  final i = path.lastIndexOf('/.ssh/');
  return i < 0 ? path : '~${path.substring(i)}';
}

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.report});

  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Importar ~/.ssh/config'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_summary(report)),
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'No todo se ha podido traer:',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final w in report.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• ${_warning(w)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
