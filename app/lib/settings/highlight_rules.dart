// Ajustes › Terminal › Resaltado: the rules that paint words and addresses
// in color, the app's and the user's, each with its switch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../terminal/highlight.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// A rule's name: the app's words for its own, the user's for theirs.
String highlightName(AppLocalizations l, HighlightRule r) => switch (r.id) {
  'error' => l.highlightError,
  'warning' => l.highlightWarning,
  'ok' => l.highlightOk,
  'ip' => l.highlightIp,
  'mac' => l.highlightMac,
  _ => r.name.isEmpty ? r.pattern : r.name,
};

/// The palette colors a rule can take, by name: the normal six and their
/// bright ones.
List<(int, String)> highlightColors(AppLocalizations l) => [
  (1, l.colorRed),
  (3, l.colorYellow),
  (2, l.colorGreen),
  (6, l.colorCyan),
  (4, l.colorBlue),
  (5, l.colorMagenta),
  (9, l.colorBrightRed),
  (11, l.colorBrightYellow),
  (10, l.colorBrightGreen),
  (14, l.colorBrightCyan),
  (12, l.colorBrightBlue),
  (13, l.colorBrightMagenta),
];

/// The list of rules, under the switch that turns them all on or off.
class HighlightRules extends ConsumerWidget {
  const HighlightRules({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    final ow = context.ow;
    final rules = s.highlightRules;
    void save(List<HighlightRule> next) =>
        notifier.update((s) => s.copyWith(highlightRules: next));
    Future<void> edit([HighlightRule? rule]) async {
      final made = await showDialog<HighlightRule>(
        context: context,
        builder: (_) => _RuleDialog(rule: rule),
      );
      if (made == null) return;
      save([
        for (final r in rules) r.id == made.id ? made : r,
        if (!rules.any((r) => r.id == made.id)) made,
      ]);
    }

    return Opacity(
      opacity: s.highlight ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rules)
            Padding(
              key: ValueKey('highlight.${r.id}'),
              padding: const EdgeInsets.symmetric(vertical: OwSpace.s1),
              child: Row(
                children: [
                  _Swatch(color: ow.terminal.ansi16[r.color]),
                  const SizedBox(width: OwSpace.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(highlightName(l, r)),
                        if (!r.builtIn)
                          Text(
                            r.pattern,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(
                              context,
                              size: 12,
                              color: ow.colors.textSubtle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.highlightEdit,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: s.highlight ? () => edit(r) : null,
                  ),
                  if (!r.builtIn)
                    IconButton(
                      tooltip: l.highlightRemove,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: s.highlight
                          ? () => save([
                              for (final x in rules)
                                if (x.id != r.id) x,
                            ])
                          : null,
                    ),
                  Switch(
                    key: ValueKey('highlight.${r.id}.on'),
                    value: r.enabled,
                    onChanged: s.highlight
                        ? (v) => save([
                            for (final x in rules)
                              x.id == r.id ? x.copyWith(enabled: v) : x,
                          ])
                        : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: OwSpace.s2),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('highlight.add'),
                onPressed: s.highlight ? edit : null,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.highlightAdd),
              ),
              const Spacer(),
              if (!_same(rules, defaultHighlights))
                TextButton(
                  onPressed: s.highlight ? () => save(defaultHighlights) : null,
                  child: Text(l.highlightReset),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _same(List<HighlightRule> a, List<HighlightRule> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(context.ow.shape.radiusSmall),
      border: Border.all(color: context.ow.colors.border),
    ),
  );
}

/// A rule of the user's to make, or one to change (the app's keep their
/// words: only their color changes).
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({this.rule});

  final HighlightRule? rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _pattern = TextEditingController(text: widget.rule?.pattern ?? '');
  late int _color = widget.rule?.color ?? 3;
  late bool _case = widget.rule?.caseSensitive ?? false;

  bool get _builtIn => widget.rule?.builtIn ?? false;

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  void _save() {
    final pattern = _pattern.text.trim();
    if (!_builtIn && !HighlightRule.valid(pattern)) return;
    final old = widget.rule;
    Navigator.of(context).pop(
      old == null
          ? HighlightRule(
              id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
              name: _name.text.trim(),
              pattern: pattern,
              color: _color,
              caseSensitive: _case,
            )
          : old.copyWith(
              name: _builtIn ? null : _name.text.trim(),
              pattern: _builtIn ? null : pattern,
              color: _color,
              caseSensitive: _builtIn ? null : _case,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final pattern = _pattern.text.trim();
    final bad = pattern.isNotEmpty && !HighlightRule.valid(pattern);
    return AlertDialog(
      title: Text(
        widget.rule == null
            ? l.highlightNewTitle
            : highlightName(l, widget.rule!),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_builtIn) ...[
              TextField(
                key: const ValueKey('highlight.name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: l.highlightName),
              ),
              const SizedBox(height: OwSpace.s5),
              TextField(
                key: const ValueKey('highlight.pattern'),
                controller: _pattern,
                style: monoStyle(context, size: 13),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: l.highlightPattern,
                  hintText: r'\b(timeout|retry)\b',
                  helperText: l.highlightPatternHelp,
                  helperMaxLines: 3,
                  errorText: bad ? l.highlightPatternBad : null,
                ),
              ),
              CheckboxListTile(
                value: _case,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.highlightCase),
                onChanged: (v) => setState(() => _case = v ?? false),
              ),
            ],
            const SizedBox(height: OwSpace.s3),
            Text(
              l.highlightColor,
              style: TextStyle(
                fontSize: OwText.small,
                color: ow.colors.textMuted,
              ),
            ),
            const SizedBox(height: OwSpace.s3),
            Wrap(
              spacing: OwSpace.s3,
              runSpacing: OwSpace.s3,
              children: [
                for (final (i, name) in highlightColors(l))
                  Semantics(
                    selected: i == _color,
                    button: true,
                    label: name,
                    child: Tooltip(
                      message: name,
                      child: InkWell(
                        key: ValueKey('highlight.color.$i'),
                        onTap: () => setState(() => _color = i),
                        borderRadius: BorderRadius.circular(
                          ow.shape.radiusSmall,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(OwSpace.s1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              ow.shape.radiusSmall,
                            ),
                            border: Border.all(
                              color: i == _color
                                  ? ow.colors.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: _Swatch(
                            color: ow.terminal.ansi16[i],
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: OwSpace.s3),
            Text(
              l.highlightColorNote,
              style: TextStyle(
                fontSize: OwText.small,
                color: ow.colors.textSubtle,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('highlight.save'),
          onPressed: _builtIn || HighlightRule.valid(pattern) ? _save : null,
          child: Text(l.save),
        ),
      ],
    );
  }
}
