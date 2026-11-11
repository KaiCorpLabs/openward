// A snippet on several hosts at once: a new tab with a pane per host, each
// over the connection that is up already if there is one, the snippet run
// in each as its shell comes up. Each pane shows its host's result.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../hosts/host_actions.dart' show hostAddress;
import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../terminal/visible_text.dart';
import '../ui/tokens.dart';
import 'snippets.dart';

/// At most this many panes in one tab.
const runOnHostsMax = 16;

/// Asks on which hosts (and the snippet's values), then runs it there.
Future<void> showRunOnHosts(
  BuildContext context,
  ProviderContainer container,
  SnippetView s,
) async {
  final picked = await showDialog<List<_ApprovedHost>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _HostsDialog(snippet: s),
  );
  if (picked == null) return;
  _runApprovedHosts(container, s, picked);
}

typedef _ApprovedHost = ({HostView host, String text});

/// Only the immutable commands displayed before the user approved them.
void _runApprovedHosts(
  ProviderContainer container,
  SnippetView s,
  List<_ApprovedHost> commands,
) {
  if (commands.isEmpty) return;
  final tabs = container.read(tabsProvider.notifier);
  final panes = <Pane>[];
  for (final command in commands.take(runOnHostsMax)) {
    final c = tabs.startSession(host: command.host, reuse: true);
    c.sendWhenUp = (text: command.text, enter: !s.spec.typeOnly);
    panes.add(Pane(c));
  }
  final root = gridOf(panes);
  tabs.addTabs([SessionTab.withPanes(Panes.of(root, active: panes.first))]);
}

/// `panes` as rows of the same height, of as many columns as rows (or
/// one more), all the same width.
PaneNode gridOf(List<Pane> panes) {
  final cols = math.sqrt(panes.length).ceil();
  PaneNode line(List<PaneNode> nodes, Axis axis) => nodes.length == 1
      ? nodes.single
      : PaneSplit(
          axis,
          nodes.first,
          line(nodes.sublist(1), axis),
          1 / nodes.length,
        );
  final rows = <PaneNode>[
    for (var i = 0; i < panes.length; i += cols)
      line(panes.sublist(i, math.min(i + cols, panes.length)), Axis.horizontal),
  ];
  return line(rows, Axis.vertical);
}

class _HostsDialog extends ConsumerStatefulWidget {
  const _HostsDialog({required this.snippet});

  final SnippetView snippet;

  @override
  ConsumerState<_HostsDialog> createState() => _HostsDialogState();
}

class _HostsDialogState extends ConsumerState<_HostsDialog> {
  final _filter = TextEditingController();
  final Set<String> _chosen = {};
  Map<String, String> _shownValues = {};
  List<_ApprovedHost> _shownCommands = [];
  late final Map<String, TextEditingController> _values = {
    for (final name in widget.snippet.variables.asked)
      name: TextEditingController(),
  };

  @override
  void dispose() {
    _filter.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The hosts a snippet can go to: those reached over a network.
  List<HostView> get _hosts {
    final library = ref.watch(libraryProvider);
    String group(HostView h) =>
        h.groupId == null ? '' : library.group(h.groupId!)?.name ?? '';
    return [
      for (final h in library.hosts)
        if (h.protocol != ProtocolKind.serial) h,
    ]..sort((a, b) {
      final g = group(a).toLowerCase().compareTo(group(b).toLowerCase());
      return g != 0
          ? g
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  bool _matches(HostView h) {
    final f = _filter.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    final library = ref.read(libraryProvider);
    final group = h.groupId == null
        ? ''
        : library.group(h.groupId!)?.name ?? '';
    return h.label.toLowerCase().contains(f) ||
        h.address.toLowerCase().contains(f) ||
        group.toLowerCase().contains(f) ||
        h.tags.any((t) => t.toLowerCase().contains(f));
  }

  void _send() {
    final values = {for (final e in _values.entries) e.key: e.value.text};
    if (!mapEquals(values, _shownValues)) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(_shownCommands);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final library = ref.watch(libraryProvider);
    final hosts = _hosts;
    final shown = hosts.where(_matches).toList();
    final chosen = hosts.where((h) => _chosen.contains(h.id)).toList();
    final tooMany = chosen.length > runOnHostsMax;
    _shownValues = {for (final e in _values.entries) e.key: e.value.text};
    _shownCommands = [
      for (final h in chosen)
        (
          host: h,
          text: renderSnippet(
            script: widget.snippet.spec.script,
            values: [
              for (final e in {
                ...builtinValuesForHost(h),
                ..._shownValues,
              }.entries)
                SnippetValue(name: e.key, value: e.value),
            ],
          ),
        ),
    ];
    return AlertDialog(
      title: Text(l.runOnHostsTitle(visibleName(widget.snippet.spec.label))),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.runOnHostsNote,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
            const SizedBox(height: OwSpace.s5),
            for (final MapEntry(:key, :value) in _values.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: OwSpace.s4),
                child: TextField(
                  key: ValueKey('runOnHosts.value.$key'),
                  controller: value,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: key),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('runOnHosts.filter'),
                    controller: _filter,
                    autofocus: _values.isEmpty,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: l.runOnHostsFilter,
                    ),
                  ),
                ),
                const SizedBox(width: OwSpace.s3),
                TextButton(
                  key: const ValueKey('runOnHosts.all'),
                  onPressed: shown.isEmpty
                      ? null
                      : () => setState(
                          () => _chosen.addAll(shown.map((h) => h.id)),
                        ),
                  child: Text(l.runOnHostsAll),
                ),
                TextButton(
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => setState(_chosen.clear),
                  child: Text(l.runOnHostsNone),
                ),
              ],
            ),
            const SizedBox(height: OwSpace.s2),
            Expanded(
              child: ListView(
                children: [
                  for (final h in shown)
                    CheckboxListTile(
                      key: ValueKey('runOnHosts.host.${h.label}'),
                      dense: true,
                      value: _chosen.contains(h.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(visibleName(h.label)),
                      subtitle: Text(
                        visibleName(
                          [
                            hostAddress(h),
                            if (h.groupId != null)
                              ?library.group(h.groupId!)?.name,
                          ].join(' · '),
                        ),
                      ),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _chosen.add(h.id)
                            : _chosen.remove(h.id),
                      ),
                    ),
                ],
              ),
            ),
            if (chosen.isNotEmpty && !tooMany) ...[
              Text(l.snippetReviewHelp),
              const SizedBox(height: OwSpace.s2),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final command in _shownCommands)
                        snippetCommandPreview(
                          context,
                          SnippetCommand(
                            destination:
                                '${command.host.label} · ${hostAddress(command.host)}',
                            text: command.text,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (tooMany)
              Text(
                l.runOnHostsMax(runOnHostsMax),
                style: TextStyle(fontSize: OwText.small, color: c.warn),
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
          key: const ValueKey('runOnHosts.run'),
          onPressed: chosen.isEmpty || tooMany ? null : _send,
          child: Text(l.runOnHostsAction(chosen.length)),
        ),
      ],
    );
  }
}
