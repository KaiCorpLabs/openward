import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

import 'editor/form.dart';
import 'editor/settings_fields.dart';
import 'editor/rows.dart';
import 'editor/frame.dart';

export 'editor/environment_fields.dart' show showEnvDialog;
export 'editor/form.dart' show FieldProblem, agentSocketExample;
export 'editor/frame.dart' show EditorFrame;
export 'editor/rows.dart' show EditorFieldRow, editorLabelWidth;

/// Creates (no `id`) or edits a host, in a panel on the right of the
/// window. True if something was saved. A new host may start from a
/// `draft` (an address typed in the quick connection, say).
Future<bool> showHostEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? groupId,
  HostSpec? draft,
}) => showSidePanel(
  context,
  (_) => _HostEditor(id: id, groupId: groupId, draft: draft),
);

/// Creates (no `id`) or edits a group. True if something was saved.
Future<bool> showGroupEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? parentId,
}) => showSidePanel(context, (_) => _GroupEditor(id: id, parentId: parentId));

/// A panel on the right of the window, as editors open. True if it
/// closed saying something was saved.
Future<bool> showSidePanel(
  BuildContext context,
  WidgetBuilder builder, {
  double width = 560,
}) async {
  final ow = context.ow;
  final still = MediaQuery.of(context).disableAnimations;
  final saved = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: ow.colors.scrim,
    transitionDuration: still ? Duration.zero : OwMotion.normal,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        // In a small window it leaves a strip of the window to click out.
        width: math.min(width, MediaQuery.sizeOf(context).width - 48),
        height: double.infinity,
        child: Material(
          color: ow.colors.raised,
          shape: Border(left: BorderSide(color: ow.colors.control)),
          elevation: 12,
          child: builder(context),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
  return saved ?? false;
}

/// Group names with their path, for pickers: `prod / eu`.
List<(String, String)> _groupChoices(Library library, {String? excluding}) {
  final out = <(String, String)>[];
  void walk(String? parent, String prefix) {
    for (final g in library.groupsIn(parent)) {
      if (g.id == excluding) continue;
      final name = prefix.isEmpty ? g.name : '$prefix / ${g.name}';
      out.add((g.id, name));
      walk(g.id, name);
    }
  }

  walk(null, '');
  return out;
}

class _HostEditor extends ConsumerStatefulWidget {
  const _HostEditor({this.id, this.groupId, this.draft});

  final String? id;
  final String? groupId;
  final HostSpec? draft;

  @override
  ConsumerState<_HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends ConsumerState<_HostEditor> {
  late final HostDetail? _detail = widget.id == null
      ? null
      : ref.read(openWardProvider).host(id: widget.id!);
  late final HostSpec _spec =
      _detail?.spec ??
      widget.draft ??
      HostSpec(label: '', address: '', groupId: widget.groupId);
  late final _label = TextEditingController(text: _spec.label);
  late final _address = TextEditingController(text: _spec.address);
  final _labelFocus = FocusNode();
  final _addressFocus = FocusNode();
  late final List<String> _tags = [..._spec.tags];
  late final _notes = TextEditingController(text: _spec.notes ?? '');
  late final _settings = SettingsForm(_spec.settings);
  late String? _group = _spec.groupId;
  late bool _favorite = _spec.favorite;

  /// Chosen by hand; null leaves it to what connecting tells.
  late String? _systemCode = _spec.systemCode;
  String? _error;
  Object? _cause;

  /// Typing takes the field's problem away, and its red with it.
  void _edited(String field) {
    if (_settings.errorOn(field) != null) {
      setState(() => _settings.edited(field));
    }
  }

  String _snapshot() => [
    _label.text,
    _address.text,
    ..._tags,
    _notes.text,
    _group,
    _favorite,
    _systemCode,
    _settings.signature,
  ].join('\u0000');

  @override
  void dispose() {
    for (final c in [_label, _address, _notes]) {
      c.dispose();
    }
    _labelFocus.dispose();
    _addressFocus.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _save({bool connect = false}) async {
    final l = context.l10n;
    final label = _label.text.trim();
    final address = _address.text.trim();
    final FieldProblem? problem = label.isEmpty
        ? (field: 'label', text: l.hostNeedsName)
        : address.isEmpty
        ? (field: 'address', text: l.missingAddress)
        : _settings.validate(l);
    _cause = null;
    _settings.problem.value = problem;
    if (problem != null) {
      setState(() => _error = problem.text);
      switch (problem.field) {
        case 'label':
          _labelFocus.requestFocus();
        case 'address':
          _addressFocus.requestFocus();
      }
      return;
    }
    final spec = HostSpec(
      label: label,
      address: address,
      groupId: _group,
      tags: _tags,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      settings: _settings.toSpec(),
      favorite: _favorite,
      systemCode: _systemCode,
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      final String id;
      if (d == null) {
        id = await app.createHost(spec: spec);
      } else {
        // What changed meanwhile (connecting learned its system) and
        // what was changed here go together.
        await app.updateHost(id: d.id, rev: d.rev, spec: spec, base: _spec);
        id = d.id;
      }
      if (connect) {
        ref.read(libraryProvider.notifier).refresh();
        final host = ref.read(libraryProvider).host(id);
        if (host != null) ref.read(tabsProvider.notifier).openHost(host);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final groups = _groupChoices(library);
    final groupName = _group == null ? null : library.group(_group!)?.name;
    final mono = monoStyle(context, size: 13, color: context.ow.colors.text);
    return EditorFrame(
      title: _detail == null ? l.newHostTitle : l.editHostTitle,
      subtitle: [
        if (_spec.label.isNotEmpty) _spec.label,
        if (groupName != null) l.inGroup(groupName),
      ].join(' · ').ifEmpty,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      onSaveAndConnect: () => _save(connect: true),
      snapshot: _snapshot,
      children: [
        // One grid: the label on the left, as in the settings below.
        EditorSection(l.sectionGeneral),
        EditorFieldRow(
          l.name,
          TextField(
            key: const ValueKey('host.label'),
            controller: _label,
            focusNode: _labelFocus,
            autofocus: true,
            onChanged: (_) => _edited('label'),
            decoration: InputDecoration(errorText: _settings.errorOn('label')),
          ),
        ),
        EditorFieldRow(
          l.address,
          TextField(
            key: const ValueKey('host.address'),
            controller: _address,
            focusNode: _addressFocus,
            onChanged: (_) => _edited('address'),
            style: mono,
            decoration: InputDecoration(
              hintText: l.addressHint,
              errorText: _settings.errorOn('address'),
            ),
          ),
        ),
        EditorFieldRow(
          l.group,
          DropdownButtonFormField<String?>(
            style: fieldTextStyle(context),
            key: const ValueKey('host.group'),
            initialValue: _group,
            items: [
              DropdownMenuItem(value: null, child: Text(l.noGroup)),
              for (final (id, name) in groups)
                DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: (v) => setState(() => _group = v),
          ),
        ),
        EditorFieldRow(l.tags, TagsField(tags: _tags)),
        FavoriteRow(
          favorite: _favorite,
          onChanged: (v) => setState(() => _favorite = v),
        ),
        const SizedBox(height: 6),
        SettingsFields(
          form: _settings,
          hosts: [
            for (final h in library.hosts)
              if (h.id != widget.id) (h.id, h.label),
          ],
          groupId: _group,
          connectionTitle: l.sectionConnection,
          // Told by the form: the mark chosen there shows here at once.
          system: ListenableBuilder(
            listenable: _settings,
            builder: (context, _) => SystemBlock(
              told: _detail?.system,
              chosen: _systemCode,
              env:
                  _settings.envMark ??
                  (_settings.setHere.contains('environment')
                      ? null
                      : _group == null
                      ? null
                      : library.group(_group!)?.environment),
              onChanged: (code) => setState(() => _systemCode = code),
            ),
          ),
        ),
        const SizedBox(height: 8),
        EditorFieldRow(
          l.notes,
          TextField(controller: _notes, minLines: 2, maxLines: 5),
        ),
      ],
    );
  }
}

class _GroupEditor extends ConsumerStatefulWidget {
  const _GroupEditor({this.id, this.parentId});

  final String? id;
  final String? parentId;

  @override
  ConsumerState<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends ConsumerState<_GroupEditor> {
  late final GroupDetail? _detail = widget.id == null
      ? null
      : ref.read(openWardProvider).group(id: widget.id!);
  late final GroupSpec _spec =
      _detail?.spec ?? GroupSpec(name: '', parentId: widget.parentId);
  late final _name = TextEditingController(text: _spec.name);
  final _nameFocus = FocusNode();
  late final _settings = SettingsForm(_spec.settings);
  late String? _parent = _spec.parentId;
  String? _error;
  Object? _cause;

  void _edited(String field) {
    if (_settings.errorOn(field) != null) {
      setState(() => _settings.edited(field));
    }
  }

  String _snapshot() =>
      [_name.text, _parent, _settings.signature].join('\u0000');

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim();
    final FieldProblem? problem = name.isEmpty
        ? (field: 'name', text: l.groupNeedsName)
        : _settings.validate(l);
    _settings.problem.value = problem;
    if (problem?.field == 'name') _nameFocus.requestFocus();
    _cause = null;
    if (problem != null) return setState(() => _error = problem.text);
    final spec = GroupSpec(
      name: name,
      parentId: _parent,
      settings: _settings.toSpec(),
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      if (d == null) {
        await app.createGroup(spec: spec);
      } else {
        await app.updateGroup(id: d.id, rev: d.rev, spec: spec);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = isVaultError(e, VaultErrorKind.cycle)
            ? l.groupInsideItself
            : saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    return EditorFrame(
      title: _detail == null ? l.newGroupTitle : l.editGroupTitle,
      subtitle: _spec.name.isEmpty ? null : _spec.name,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      snapshot: _snapshot,
      children: [
        EditorSection(l.sectionGeneral),
        EditorFieldRow(
          l.name,
          TextField(
            key: const ValueKey('group.name'),
            controller: _name,
            focusNode: _nameFocus,
            autofocus: true,
            onChanged: (_) => _edited('name'),
            decoration: InputDecoration(errorText: _settings.errorOn('name')),
          ),
        ),
        EditorFieldRow(
          l.inside,
          DropdownButtonFormField<String?>(
            style: fieldTextStyle(context),
            initialValue: _parent,
            items: [
              DropdownMenuItem(value: null, child: Text(l.noParent)),
              for (final (id, name) in _groupChoices(
                library,
                excluding: widget.id,
              ))
                DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: (v) => setState(() => _parent = v),
          ),
        ),
        const SizedBox(height: 6),
        SettingsFields(
          form: _settings,
          hosts: [for (final h in library.hosts) (h.id, h.label)],
          groupId: _parent,
          connectionTitle: l.groupSettingsSection,
          inheritors: widget.id == null ? null : library.countUnder(widget.id!),
        ),
      ],
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
