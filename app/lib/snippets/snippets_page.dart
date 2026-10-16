// The «Snippets» page: every snippet with what it sends and asks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
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
    final theme = Theme.of(context);
    final all = ref.watch(snippetsProvider);
    final shown = all.where(_matches).toList();
    final shortcut = isApple ? '⌘⇧S' : 'Ctrl+Shift+S';
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.snippets,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.snippetsIntro('{{${l.bracesWord}}}'),
                      style: TextStyle(color: c.textMuted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('snippets.new'),
                onPressed: () => showSnippetEditor(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.newSnippet),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.terminal, size: 36, color: c.textSubtle),
                  const SizedBox(height: 12),
                  Text(
                    l.noSnippets,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      l.noSnippetsBody('{{${l.bracesWord}}}'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                SizedBox(
                  width: 360,
                  height: 34,
                  child: TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.filterSnippets,
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: c.textSubtle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l.snippetsCount(all.length),
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _table(context, shown),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textSubtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.snippetsHowToRun(shortcut),
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _widths = [1.2, 2.6, 1.1, 0.85, 0.7];

  Widget _cells(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: (_widths[i] * 100).round(),
          child: Padding(
            padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : 12),
            child: cells[i],
          ),
        ),
    ],
  );

  Widget _table(BuildContext context, List<SnippetView> rows) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: c.textSubtle,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        children: [
          Container(
            color: c.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _cells([
              for (final h in [l.name, l.command, l.asks, l.onSend, ''])
                Text(h.toUpperCase(), style: head),
            ]),
          ),
          for (final s in rows) _row(context, s),
        ],
      ),
    );
  }

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
    return InkWell(
      key: ValueKey('snippet.${s.spec.label}'),
      onTap: () => showSnippetEditor(context, ref, snippet: s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: _cells([
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
                  style: TextStyle(fontSize: 11, color: c.textSubtle),
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
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: c.control),
                  borderRadius: BorderRadius.circular(context.ow.shape.radius),
                ),
                child: Text(
                  l.runEllipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: terminals.isEmpty ? c.textSubtle : c.accentText,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
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
