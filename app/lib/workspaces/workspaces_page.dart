// The «Espacios de trabajo» page: layouts of tabs and panes saved by name,
// to open again, bring up to date with what is open, rename or delete.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/workspaces.dart';
import '../tabs/tabs.dart';
import '../ui/announcer.dart';
import '../ui/tokens.dart';
import 'workspaces.dart';

/// "Guardar como espacio de trabajo": names the open tabs and saves them.
/// Returns the name saved, or null.
Future<String?> saveWorkspaceDialog(BuildContext context, WidgetRef ref) async {
  final state = ref.read(tabsProvider);
  final tabs = captureTabs(state);
  if (tabs.isEmpty) return null;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _SaveWorkspace(tabs: tabs),
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return null;
  final saved = await runAction(
    context,
    () => ref
        .read(openWardProvider)
        .createWorkspace(spec: captureWorkspace(state, name)),
  );
  ref.read(workspacesProvider.notifier).refresh();
  return saved ? name.trim() : null;
}

class _SaveWorkspace extends ConsumerStatefulWidget {
  const _SaveWorkspace({required this.tabs});

  final List<WorkspaceTabSpec> tabs;

  @override
  ConsumerState<_SaveWorkspace> createState() => _SaveWorkspaceState();
}

class _SaveWorkspaceState extends ConsumerState<_SaveWorkspace> {
  late final _name = TextEditingController(text: _suggested());

  String _suggested() {
    final l = context.l10n;
    final taken = ref.read(workspacesProvider).map((w) => w.spec.name).toSet();
    for (var i = 1; ; i++) {
      final name = l.workspaceNumbered(i);
      if (!taken.contains(name)) return name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final sessions = widget.tabs.fold(0, (n, t) => n + tabTargets(t).length);
    return AlertDialog(
      title: Text(l.saveWorkspaceTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.saveWorkspaceIntro, style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 16),
            Text(l.name, style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('workspace.name'),
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Text(
              workspaceSummary(l, widget.tabs.length, sessions),
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            const SizedBox(height: 6),
            _TabChips(tabs: widget.tabs),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('workspace.save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// A workspace's tabs, each with what it connects to.
class _TabChips extends ConsumerWidget {
  const _TabChips({required this.tabs});

  final List<WorkspaceTabSpec> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tabs)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.sunken,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(ow.shape.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  t.sftp != null
                      ? Icons.folder_outlined
                      : tabTargets(t).length > 1
                      ? Icons.vertical_split_outlined
                      : Icons.terminal,
                  size: 13,
                  color: c.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  t.title ??
                      tabTargets(t)
                          .map((x) => targetLabel(l, ref, x))
                          .join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class WorkspacesPage extends ConsumerStatefulWidget {
  const WorkspacesPage({super.key});

  @override
  ConsumerState<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends ConsumerState<WorkspacesPage> {
  String? _note;
  String? _error;

  void _say(String note) {
    setState(() {
      _note = note;
      _error = null;
    });
    announce(context, note);
  }

  Future<void> _save() async {
    final name = await saveWorkspaceDialog(context, ref);
    if (name != null && mounted) _say(context.l10n.workspaceSaved(name));
  }

  Future<void> _update(WorkspaceView w) async {
    final l = context.l10n;
    final state = ref.read(tabsProvider);
    try {
      await ref
          .read(openWardProvider)
          .updateWorkspace(
            id: w.id,
            rev: w.rev,
            spec: captureWorkspace(state, w.spec.name),
          );
      ref.read(workspacesProvider.notifier).refresh();
      _say(l.workspaceUpdated(w.spec.name));
    } catch (e) {
      setState(() => _error = saveErrorText(l, e));
    }
  }

  Future<void> _rename(WorkspaceView w) async {
    final l = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: w.spec.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == w.spec.name) {
      return;
    }
    try {
      await ref
          .read(openWardProvider)
          .renameWorkspace(id: w.id, rev: w.rev, name: name);
      ref.read(workspacesProvider.notifier).refresh();
    } catch (e) {
      setState(() => _error = saveErrorText(l, e));
    }
  }

  Future<void> _delete(WorkspaceView w) async {
    final l = context.l10n;
    final c = context.ow.colors;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteWorkspaceTitle(w.spec.name)),
        content: Text(l.deleteWorkspaceBody),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('workspace.delete.confirm'),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await runAction(
      context,
      () => ref.read(openWardProvider).delete(id: w.id),
      failed: (l, e) => l.deleteFailed(errorReason(l, e)),
    );
    ref.read(workspacesProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final all = ref.watch(workspacesProvider);
    final open = captureTabs(ref.watch(tabsProvider));
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.workspaces,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        l.workspacesIntro,
                        style: TextStyle(color: c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Greyed out, it says why.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('workspaces.save'),
                    onPressed: open.isEmpty ? null : _save,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: Text(l.saveOpenTabs),
                  ),
                  if (open.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l.saveTabsNeedsTabs,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_note != null || _error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error ?? _note!,
                style: TextStyle(
                  color: _error != null ? c.danger : c.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.dashboard_outlined, size: 36, color: c.textSubtle),
                  const SizedBox(height: 12),
                  Text(
                    l.noWorkspaces,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.noWorkspacesBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textMuted),
                  ),
                ],
              ),
            )
          else
            for (final w in all) _card(context, w, canUpdate: open.isNotEmpty),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WorkspaceView w, {
    required bool canUpdate,
  }) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Container(
      key: ValueKey('workspace.${w.spec.name}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.spec.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  workspaceSummary(l, w.spec.tabs.length, w.sessions),
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 8),
                _TabChips(tabs: w.spec.tabs),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: ValueKey('workspace.open.${w.spec.name}'),
            onPressed: () => openWorkspace(ref, w),
            child: Text(l.open),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            key: ValueKey('workspace.menu.${w.spec.name}'),
            tooltip: l.moreActions,
            icon: Icon(Icons.more_horiz, size: 18, color: c.textMuted),
            onSelected: (v) => switch (v) {
              'update' => _update(w),
              'rename' => _rename(w),
              _ => _delete(w),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'update',
                enabled: canUpdate,
                child: Text(l.updateWithOpenTabs),
              ),
              PopupMenuItem(value: 'rename', child: Text(l.rename)),
              PopupMenuItem(
                value: 'delete',
                child: Text(l.delete, style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A new name for a workspace; the field lives as long as the dialog.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _field = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.renameWorkspace),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: const ValueKey('workspace.rename'),
          controller: _field,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: Text(l.save),
        ),
      ],
    );
  }
}
