import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'snippets.dart';

/// ⌘⇧S in a terminal: find a snippet and send it there. Nothing in front
/// of a tab that is not a terminal.
Future<void> showSnippetPalette(BuildContext context) async {
  final ref = ProviderScope.containerOf(context);
  final targets = snippetTargets(ref);
  if (targets.isEmpty) return;
  ref.read(snippetsProvider.notifier).refresh();
  final picked = await showDialog<(SnippetView, bool)>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _Palette(where: targets.first.displayTitle),
  );
  if (picked == null || !context.mounted) {
    targets.first.focusTerminal?.call();
    return;
  }
  await runSnippet(context, ref, picked.$1, typeOnly: picked.$2 ? true : null);
}

class _Palette extends ConsumerStatefulWidget {
  const _Palette({required this.where});

  final String where;

  @override
  ConsumerState<_Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<_Palette> {
  final _query = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<SnippetView> _shown() {
    final q = _query.text.trim().toLowerCase();
    final all = ref.watch(snippetsProvider);
    if (q.isEmpty) return all;
    return [
      for (final s in all)
        if (s.spec.label.toLowerCase().contains(q) ||
            s.spec.script.toLowerCase().contains(q))
          s,
    ];
  }

  KeyEventResult _key(FocusNode _, KeyEvent e, List<SnippetView> shown) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    // Also with the cursor in the search, which would keep Esc otherwise.
    if (k == LogicalKeyboardKey.escape) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      if (shown.isEmpty) return KeyEventResult.handled;
      final step = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _selected = (_selected + step) % shown.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (shown.isNotEmpty) {
        final alt = HardwareKeyboard.instance.isAltPressed;
        Navigator.pop(context, (
          shown[_selected.clamp(0, shown.length - 1)],
          alt,
        ));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final shown = _shown();
    final mono = monoStyle(context, size: 12);
    Widget hint(String keys, String text) => Padding(
      padding: const EdgeInsets.only(right: OwSpace.s7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: keys, style: mono),
            TextSpan(text: ' $text'),
          ],
        ),
        style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
      ),
    );
    final alt = isApple ? '⌥↩' : 'Alt+↩';
    return Align(
      alignment: const Alignment(0, -0.75),
      child: Material(
        color: c.raised,
        elevation: 16,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.control),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge + 2),
        ),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(OwSpace.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  onKeyEvent: (n, e) => _key(n, e, shown),
                  child: TextField(
                    key: const ValueKey('snippets.query'),
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() => _selected = 0),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: l.findASnippet,
                      prefixIcon: Icon(
                        Icons.text_snippet_outlined,
                        size: 16,
                        color: c.accentText,
                      ),
                      suffixText: l.inWhere(widget.where),
                      suffixStyle: TextStyle(
                        fontSize: OwText.small,
                        color: c.textSubtle,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 4),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(OwSpace.s7),
                    child: Text(
                      ref.read(snippetsProvider).isEmpty
                          ? l.noSnippetsYet
                          : l.noSnippetMatches,
                      style: TextStyle(color: c.textMuted),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (i, s) in shown.indexed)
                        _item(
                          context,
                          s,
                          i == _selected.clamp(0, shown.length - 1),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OwSpace.s5,
                    OwSpace.s4,
                    OwSpace.s3,
                    OwSpace.s2,
                  ),
                  child: Row(
                    children: [
                      // With large text, the hints go on to a second line.
                      Expanded(
                        child: Wrap(
                          runSpacing: 2,
                          children: [
                            hint('↑↓', l.paletteChoose),
                            hint('↩', l.paletteRun),
                            hint(alt, l.paletteTypeOnly),
                            hint('Esc', l.close.toLowerCase()),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          ref
                              .read(tabsProvider.notifier)
                              .openPage(PageKind.snippets);
                        },
                        style: TextButton.styleFrom(
                          textStyle: smallButtonText(context),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(l.manageSnippets),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, SnippetView s, bool selected) {
    final ow = context.ow;
    final c = ow.colors;
    final first = s.spec.script.split('\n').first;
    return Material(
      color: selected ? c.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(ow.shape.radius),
      child: InkWell(
        key: ValueKey('palette.${s.spec.label}'),
        borderRadius: BorderRadius.circular(ow.shape.radius),
        onTap: () => Navigator.pop(context, (s, false)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OwSpace.s5,
            vertical: OwSpace.s4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.spec.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 12, color: c.textSubtle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              for (final v in s.variables.asked)
                Padding(
                  padding: const EdgeInsets.only(left: OwSpace.s2),
                  child: Pill(v, tone: PillTone.warm),
                ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: OwSpace.s4),
                  child: Text('↩', style: TextStyle(color: c.textSubtle)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
