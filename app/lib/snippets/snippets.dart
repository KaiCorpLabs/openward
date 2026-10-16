import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The saved snippets, by name.
class SnippetsNotifier extends Notifier<List<SnippetView>> {
  @override
  List<SnippetView> build() => ref.read(openWardProvider).snippets();

  void refresh() => state = ref.read(openWardProvider).snippets();
}

final snippetsProvider = NotifierProvider<SnippetsNotifier, List<SnippetView>>(
  SnippetsNotifier.new,
);

/// `{{name}}`, as the core reads them (an escaped `\{{` is not one).
final snippetVariable = RegExp(
  r'(?<!\\)\{\{\s*([\p{L}_][\p{L}\p{N}_-]*)\s*\}\}',
  unicode: true,
);

/// Where a snippet goes from the front tab: its active pane and, while
/// broadcasting, the other panes that receive.
List<TerminalController> snippetTargets(ProviderContainer ref) {
  final tab = ref.read(tabsProvider).current;
  if (tab is! SessionTab) return const [];
  final active = tab.controller;
  if (active == null || active.isDisposed) return const [];
  return [
    active,
    for (final c in tab.panes.mirrorsOf(active))
      if (!c.isDisposed) c,
  ];
}

/// The values a pane fills in itself: its host, address, user and port.
Map<String, String> builtinValues(ProviderContainer ref, TerminalController c) {
  final host = c.hostId == null
      ? null
      : ref.read(libraryProvider).host(c.hostId!);
  final t = c.target;
  final localUser =
      Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '';
  return {
    'host': c.label,
    'address': host?.address ?? t?.address ?? 'localhost',
    'user': host?.user ?? t?.user ?? localUser,
    'port': '${host?.port ?? t?.port ?? (c.isLocal ? '' : 22)}',
  };
}

String renderFor(
  ProviderContainer ref,
  SnippetView s,
  TerminalController c,
  Map<String, String> asked,
) => renderSnippet(
  script: s.spec.script,
  values: [
    for (final e in {...builtinValues(ref, c), ...asked}.entries)
      SnippetValue(name: e.key, value: e.value),
  ],
);

/// Sends `s` to the front tab: the panes that receive while broadcasting,
/// or the active one. Asks first for its variables and, with more than
/// one pane, says where it goes. `typeOnly` leaves it without Enter.
/// `context` must outlive a change of tab (the root navigator's).
Future<void> runSnippet(
  BuildContext context,
  ProviderContainer ref,
  SnippetView s, {
  bool? typeOnly,
}) async {
  final targets = snippetTargets(ref);
  if (targets.isEmpty) return;
  final only = typeOnly ?? s.spec.typeOnly;
  var values = const <String, String>{};
  if (s.variables.asked.isNotEmpty || targets.length > 1) {
    final answered = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _RunDialog(snippet: s, targets: targets, typeOnly: only),
      useRootNavigator: true,
    );
    if (answered == null) return;
    values = answered;
  }
  for (final c in targets) {
    if (c.isDisposed) continue;
    final text = renderFor(ref, s, c, values);
    if (only) {
      c.session.paste(text: text, allowUnsafe: true);
    } else {
      c.session.text(text: '$text\n');
    }
  }
  targets.first.focusTerminal?.call();
}

/// What a snippet asks for, and the command each pane gets.
class _RunDialog extends StatefulWidget {
  const _RunDialog({
    required this.snippet,
    required this.targets,
    required this.typeOnly,
  });

  final SnippetView snippet;
  final List<TerminalController> targets;
  final bool typeOnly;

  @override
  State<_RunDialog> createState() => _RunDialogState();
}

class _RunDialogState extends State<_RunDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final name in widget.snippet.variables.asked)
      name: TextEditingController(
        text: widget.snippet.spec.defaults
            .where((d) => d.name == name)
            .firstOrNull
            ?.value,
      ),
  };

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => {
    for (final e in _fields.entries)
      if (e.value.text.isNotEmpty) e.key: e.value.text,
  };

  void _send() => Navigator.pop(context, _values);

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final many = widget.targets.length > 1;
    final values = _values;
    final ref = ProviderScope.containerOf(context);
    Widget preview(TerminalController t) {
      final text = renderFor(ref, widget.snippet, t, values);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (many)
              SizedBox(
                width: 90,
                child: Text(
                  t.displayTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
            Expanded(
              child: Text(
                text,
                style: monoStyle(context, size: 12, color: c.text),
              ),
            ),
          ],
        ),
      );
    }

    final names = _fields.keys.toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      },
      child: AlertDialog(
        title: Text(l.runSnippetTitle(widget.snippet.spec.label)),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (names.isNotEmpty) ...[
                  Text(
                    l.runSnippetHint,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                  const SizedBox(height: 12),
                  for (final (i, name) in names.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        key: ValueKey('snippet.var.$name'),
                        controller: _fields[name],
                        autofocus: i == 0,
                        style: monoStyle(context, size: 13, color: c.text),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => i == names.length - 1
                            ? _send()
                            : FocusScope.of(context).nextFocus(),
                        decoration: InputDecoration(
                          labelText: name,
                          labelStyle: monoStyle(
                            context,
                            size: 13,
                            color: c.warn,
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (many) ...[
                      Icon(Icons.podcasts, size: 14, color: c.warn),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        many
                            ? l.runSnippetBroadcast(widget.targets.length)
                            : l.runSnippetIn(widget.targets.first.displayTitle),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: many ? c.warn : c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.sunken,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(ow.shape.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final t in widget.targets) preview(t)],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.typeOnly ? l.snippetTypeOnlyNote : l.snippetWithEnter,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('snippet.send'),
            style: many
                ? FilledButton.styleFrom(
                    backgroundColor: c.warn,
                    foregroundColor: c.window,
                  )
                : null,
            onPressed: _send,
            child: Text(
              many ? l.sendToPanes(widget.targets.length) : l.sendAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chips for a snippet's variables: asked ones warm, the session's grey.
class VariableChips extends StatelessWidget {
  const VariableChips(this.variables, {super.key});

  final SnippetVariables variables;

  @override
  Widget build(BuildContext context) {
    if (variables.asked.isEmpty && variables.builtins.isEmpty) {
      return Text('—', style: TextStyle(color: context.ow.colors.textSubtle));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final v in variables.asked) Pill(v, tone: PillTone.warm),
        for (final v in variables.builtins) Pill(v, tone: PillTone.neutral),
      ],
    );
  }
}
