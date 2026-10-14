import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings.dart';
import 'core/version.dart';
import 'terminal/keys.dart';

/// Settings take effect as they change; there is nothing to save.
Future<void> showSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _SettingsDialog(),
);

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    // Thousands apart with a space: 10 000.
    String lines(int n) =>
        '$n'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
    Widget row(String label, Widget control, {String? help}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (help != null)
                  Text(
                    help,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
    return AlertDialog(
      title: const Text('Ajustes'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(
              'Tema',
              SegmentedButton<ThemeChoice>(
                segments: const [
                  ButtonSegment(
                    value: ThemeChoice.system,
                    label: Text('Sistema'),
                  ),
                  ButtonSegment(value: ThemeChoice.dark, label: Text('Oscuro')),
                  ButtonSegment(value: ThemeChoice.light, label: Text('Claro')),
                ],
                selected: {s.theme},
                onSelectionChanged: (v) =>
                    notifier.update((s) => s.copyWith(theme: v.single)),
              ),
            ),
            row(
              'Tamaño de letra',
              DropdownButton<double>(
                value: s.fontSize,
                items: [
                  for (final size in {...Settings.fontSizes, s.fontSize})
                    DropdownMenuItem(
                      value: size,
                      child: Text('${size.round()} px'),
                    ),
                ],
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(fontSize: v)),
              ),
            ),
            row(
              'Historial',
              DropdownButton<int>(
                value: s.scrollback,
                items: [
                  for (final n in {...Settings.scrollbacks, s.scrollback})
                    DropdownMenuItem(
                      value: n,
                      child: Text('${lines(n)} líneas'),
                    ),
                ],
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(scrollback: v)),
              ),
              help: 'Para las pestañas nuevas.',
            ),
            if (isApple)
              row(
                'Opción como Alt',
                Switch(
                  value: s.optionAsAlt,
                  onChanged: (v) =>
                      notifier.update((s) => s.copyWith(optionAsAlt: v)),
                ),
                help:
                    'Opción envía Esc + tecla, como esperan emacs y readline, '
                    'en vez de escribir símbolos como @ o €.',
              ),
          ],
        ),
      ),
      actions: [
        Text(
          'OpenWard $appVersion',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
