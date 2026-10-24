// The «Snippets» page: every snippet with what it sends and asks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../tabs/tabs.dart';
import '../ui/tokens.dart';
import '../ui/page.dart';
import '../ui/widgets.dart';
import '../window/shortcuts.dart';
import 'snippet_editor.dart';
import 'snippets.dart';

class SnippetsPage extends ConsumerStatefulWidget {
  const SnippetsPage({super.key});

  @override
  ConsumerState<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends ConsumerState<SnippetsPage> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(SnippetView s) {
    final f = _filter.text.trim().toLowerCase();
    return f.isEmpty ||
        s.spec.label.toLowerCase().contains(f) ||
        s.spec.script.toLowerCase().contains(f);
  }

  /// Runs `s` in a terminal tab: the one picked, brought to the front
  /// (this page goes away with it).
  Future<void> _runIn(SnippetView s, int tabIndex) async {
    final root = Navigator.of(context, rootNavigator: true).context;
    final container = ProviderScope.containerOf(context);
    container.read(tabsProvider.notifier).select(tabIndex);
    await WidgetsBinding.instance.endOfFrame;
    if (root.mounted) await runSnippet(root, container, s);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final all = ref.watch(snippetsProvider);
    final shown = all.where(_matches).toList();
    final shortcut = keysFor('⌘⇧S', '${l.ctrlShiftPrefix}S');
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: pagePadding,
        children: [
          OwPageHeader(
            title: l.snippets,
            intro: l.snippetsIntro('{{${l.bracesWord}}}'),
            action: FilledButton.icon(
              key: const ValueKey('snippets.new'),
              onPressed: () => showSnippetEditor(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l.newSnippet),
            ),
          ),
          const SizedBox(height: 16),
          if (all.isEmpty)
            OwEmptyState(
              icon: Icons.text_snippet_outlined,
              title: l.noSnippets,
              body: l.noSnippetsBody('{{${l.bracesWord}}}'),
            )
          else ...[
            OwFilterField(
              controller: _filter,
              hint: l.filterSnippets,
              onChanged: (_) => setState(() {}),
              count: l.snippetsCount(all.length),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              OwEmptyState.noMatch(
                filter: _filter.text.trim(),
                onClear: () => setState(_filter.clear),
              )
            else
              OwDataTable(
                widths: _widths,
                headings: [l.name, l.command, l.asks, l.onSend, ''],
                hideBelow: const [null, null, 640, 540, null],
                rows: [for (final s in shown) _row(context, s)],
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textSubtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.snippetsHowToRun(shortcut),
                  style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _widths = [1.2, 2.6, 1.1, 0.85, 0.7];

  Widget _row(BuildContext context, SnippetView s) {
    final c = context.ow.colors;
    final l = context.l10n;
    final lines = s.spec.script.split('\n');
    final tabs = ref.watch(tabsProvider).tabs;
    final terminals = [
      for (final (i, t) in tabs.indexed)
        if (t is SessionTab && t.controller != null)
          (i, t.controller!.displayTitle),
    ];
    return OwTableRow(
      inkKey: ValueKey('snippet.${s.spec.label}'),
      onTap: () => showSnippetEditor(context, ref, snippet: s),
      widths: _widths,
      cells: [
        Text(
          s.spec.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightedScript(lines.first, maxLines: 1),
            if (lines.length > 1)
              Text(
                l.linesCount(lines.length),
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
          ],
        ),
        VariableChips(s.variables),
        Text(
          s.spec.typeOnly ? l.typeOnly : l.withEnter,
          style: TextStyle(color: s.spec.typeOnly ? c.textMuted : c.text),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<int>(
            key: ValueKey('snippet.run.${s.spec.label}'),
            enabled: terminals.isNotEmpty,
            tooltip: terminals.isEmpty ? l.openATerminalFirst : l.runIn,
            onSelected: (i) => _runIn(s, i),
            itemBuilder: (_) => [
              for (final (i, title) in terminals)
                PopupMenuItem(value: i, child: Text(title)),
            ],
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: OwSpace.s5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: c.control),
                borderRadius: BorderRadius.circular(context.ow.shape.radius),
              ),
              child: Text(
                l.runEllipsis,
                style: TextStyle(
                  fontSize: OwText.small,
                  color: terminals.isEmpty ? c.textSubtle : c.accentText,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A script in the terminal font, with its `{{variables}}` marked.
class HighlightedScript extends StatelessWidget {
  const HighlightedScript(this.script, {super.key, this.maxLines});

  final String script;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Text.rich(
      highlightVariables(context, script, monoStyle(context, color: c.text)),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// `script` as spans, its variables in the warm color.
TextSpan highlightVariables(
  BuildContext context,
  String script,
  TextStyle base,
) {
  final warm = base.copyWith(color: context.ow.colors.warn);
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in snippetVariable.allMatches(script)) {
    if (m.start > at) spans.add(TextSpan(text: script.substring(at, m.start)));
    spans.add(TextSpan(text: m.group(0), style: warm));
    at = m.end;
  }
  if (at < script.length) spans.add(TextSpan(text: script.substring(at)));
  return TextSpan(style: base, children: spans);
}
