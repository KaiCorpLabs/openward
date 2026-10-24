// The environment mark: the picker, its preview and the dialog that
// makes one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../src/rust/api/vault.dart';
import '../../ui/environment.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// The marks to choose from: none, the four of every install, the one in
/// use if it is another, and «Other…» to make one. A preview below.
class EnvPicker extends StatelessWidget {
  const EnvPicker({super.key, required this.chosen, required this.onChanged});

  /// Null: no mark.
  final EnvironmentView? chosen;
  final ValueChanged<EnvironmentView?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final presets = envPresets(l);
    // One of the four made in another language is that one here.
    final mark = switch (chosen) {
      final m? => shownEnv(l, m),
      null => null,
    };
    final options = <EnvironmentView?>[
      null,
      ...presets,
      if (mark != null && !presets.contains(mark)) mark,
    ];
    Widget option(EnvironmentView? env) {
      final on = env == mark;
      final colors = env == null ? null : envColors(c, env.color);
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: InkWell(
            key: ValueKey('env.${env?.short ?? 'none'}'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => onChanged(env),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: OwSpace.s5),
              decoration: BoxDecoration(
                color: on ? c.accentSoft : null,
                border: Border.all(color: on ? c.accent : c.control),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors?.fg,
                      border: colors == null
                          ? Border.all(color: c.textSubtle)
                          : null,
                      borderRadius: BorderRadius.circular(
                        context.ow.shape.radiusSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      env?.name ?? l.envNone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    env?.short ?? l.envNoneNote,
                    // On the chosen one's fill, the subtle gray does not read.
                    style: monoStyle(
                      context,
                      size: 12,
                      color: on ? c.accentText : c.textSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final env in options)
                  SizedBox(width: w, child: option(env)),
                SizedBox(
                  width: w,
                  child: OutlinedButton.icon(
                    key: const ValueKey('env.other'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () async {
                      final made = await showEnvDialog(context, mark);
                      if (made != null) onChanged(made);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      l.envOther,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (mark != null) ...[
          const SizedBox(height: 10),
          _EnvPreview(env: mark),
        ],
      ],
    );
  }
}

/// How the mark looks: a tab and the top of its terminal.
class _EnvPreview extends StatelessWidget {
  const _EnvPreview({required this.env});

  final EnvironmentView env;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final line = envColors(c, env.color).fg;
    return Semantics(
      label: l.envPreview(shownEnv(l, env).name),
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.window,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.only(left: OwSpace.s5),
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  OwSpace.s5,
                  OwSpace.s3,
                  OwSpace.s5,
                  OwSpace.s3,
                ),
                decoration: BoxDecoration(
                  color: ow.terminal.background,
                  border: Border(top: BorderSide(color: line, width: 2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(Status.connected, size: 7),
                    const SizedBox(width: 8),
                    Text(
                      l.envPreviewHost,
                      style: const TextStyle(fontSize: OwText.body),
                    ),
                    const SizedBox(width: 6),
                    EnvChip(env),
                  ],
                ),
              ),
            ),
            Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(
                OwSpace.s6,
                OwSpace.s5,
                OwSpace.s5,
                0,
              ),
              decoration: BoxDecoration(
                color: ow.terminal.background,
                border: Border(top: BorderSide(color: line, width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'deploy@${l.envPreviewHost}:~\$',
                      style: monoStyle(
                        context,
                        size: 12,
                        color: ow.terminal.foreground,
                      ),
                    ),
                  ),
                  EnvChip(env, big: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mark of one's own: its name, short name and color.
Future<EnvironmentView?> showEnvDialog(
  BuildContext context,
  EnvironmentView? from,
) => showDialog<EnvironmentView>(
  context: context,
  builder: (_) => _EnvDialog(from: from),
);

class _EnvDialog extends StatefulWidget {
  const _EnvDialog({this.from});

  final EnvironmentView? from;

  @override
  State<_EnvDialog> createState() => _EnvDialogState();
}

class _EnvDialogState extends State<_EnvDialog> {
  late final _name = TextEditingController(text: widget.from?.name ?? '');
  late final _short = TextEditingController(text: widget.from?.short ?? '');
  late String _color = widget.from?.color ?? 'green';

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final short = _short.text.trim();
    Navigator.pop(
      context,
      EnvironmentView(
        name: name,
        short: short.isEmpty ? name.toLowerCase() : short,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    // Esc also from a field, which would keep it otherwise.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l.envDialogTitle),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('envDialog.name'),
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.envName),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('envDialog.short'),
                controller: _short,
                maxLength: 12,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.envShort,
                  helperText: l.envShortHelp,
                ),
              ),
              const SizedBox(height: 12),
              Text(l.envColor, style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in envColorNames)
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: name == _color,
                      label: envColorName(l, name),
                      child: Tooltip(
                        message: envColorName(l, name),
                        child: InkWell(
                          key: ValueKey('envDialog.color.$name'),
                          borderRadius: BorderRadius.circular(
                            context.ow.shape.radius,
                          ),
                          onTap: () => setState(() => _color = name),
                          child: Container(
                            width: 30,
                            height: 30,
                            padding: const EdgeInsets.all(OwSpace.s1),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: name == _color
                                    ? c.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(
                                context.ow.shape.radius,
                              ),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: envColors(c, name).fg,
                                borderRadius: BorderRadius.circular(
                                  context.ow.shape.radiusSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_name.text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: EnvChip(
                    EnvironmentView(
                      name: _name.text.trim(),
                      short: _short.text.trim().isEmpty
                          ? _name.text.trim().toLowerCase()
                          : _short.text.trim(),
                      color: _color,
                    ),
                    big: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('envDialog.ok'),
            onPressed: _name.text.trim().isEmpty ? null : _done,
            child: Text(l.envUse),
          ),
        ],
      ),
    );
  }
}
