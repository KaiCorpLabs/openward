// The side panel every editor sits in, and the host's own blocks: the
// favorite and the system.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/vault.dart';
import '../../ui/confirm.dart';
import '../../ui/environment.dart';
import '../../ui/keep_focus.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

import 'rows.dart';

/// The panel: title, the form, and the buttons that close it.
/// An editor in a side panel: a title, what it edits, and save.
class EditorFrame extends StatefulWidget {
  const EditorFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.error,
    required this.onSave,
    required this.children,
    this.onSaveAndConnect,
    this.saveAndConnectLabel,
    this.onDelete,
    this.saveLabel,
    this.saveEnabled = true,
    this.snapshot,
    this.errorCause,
  });

  final String title;
  final String? subtitle;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback? onSaveAndConnect;

  /// The second way to save; "save and connect" by default.
  final String? saveAndConnectLabel;
  final VoidCallback? onDelete;
  final List<Widget> children;

  /// The main button's text; "Save" by default.
  final String? saveLabel;
  final bool saveEnabled;

  /// What the form says now. Closing without saving after it changed asks
  /// first: Esc, Cancel, the close button or a click outside the panel.
  final String Function()? snapshot;

  /// What [error] came from, when it came from the core: «Detalles»
  /// shows its own words.
  final Object? errorCause;

  @override
  State<EditorFrame> createState() => _EditorFrameState();
}

class _EditorFrameState extends State<EditorFrame> {
  /// The form as it opened.
  String? _opened;

  @override
  void initState() {
    super.initState();
    _opened = widget.snapshot?.call();
  }

  void save() {
    if (widget.saveEnabled) widget.onSave();
  }

  /// Closes without saving: at once if nothing changed, else if the user
  /// says to discard the changes.
  Future<void> _leave() async {
    final changed = widget.snapshot != null && widget.snapshot!() != _opened;
    if (changed) {
      final l = context.l10n;
      final discard = await confirmAction(
        context,
        title: l.discardChangesTitle,
        body: l.discardChangesBody,
        action: l.discardChanges,
        danger: true,
      );
      if (!discard) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final EditorFrame(
      :title,
      :subtitle,
      :error,
      :onSave,
      :onSaveAndConnect,
      :saveAndConnectLabel,
      :onDelete,
      :children,
      :saveLabel,
      :saveEnabled,
    ) = widget;
    // Every way out but saving comes here (a click outside the panel
    // too): saving pops the route itself.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      // A focused field that goes away (a setting back to inheriting)
      // would leave Esc and ⌘↩ hearing nothing.
      child: KeepFocus(
        debugLabel: 'EditorFrame',
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): save,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                save,
            // Also with the cursor in a field, which would keep Esc otherwise.
            const SingleActivator(LogicalKeyboardKey.escape): _leave,
          },
          child: FocusTraversalGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    OwSpace.s12,
                    OwSpace.s9,
                    OwSpace.s8,
                    OwSpace.s8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: OwText.heading,
                                ),
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: OwSpace.s1),
                                child: Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: OwText.small,
                                    color: c.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l.close,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _leave,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      OwSpace.s12,
                      OwSpace.s8,
                      OwSpace.s8,
                      OwSpace.s8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      OwSpace.s12,
                      0,
                      OwSpace.s8,
                      OwSpace.s4,
                    ),
                    child: Row(
                      children: [
                        // Said as it appears, also where the field is.
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              style: TextStyle(color: c.danger),
                            ),
                          ),
                        ),
                        if (widget.errorCause case final cause?)
                          TextButton(
                            key: const ValueKey('editor.errorDetails'),
                            onPressed: () => showErrorDetails(context, cause),
                            child: Text(l.details),
                          ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    OwSpace.s8,
                    OwSpace.s6,
                    OwSpace.s12,
                    OwSpace.s6,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      if (onDelete != null)
                        TextButton(
                          onPressed: onDelete,
                          style: TextButton.styleFrom(
                            foregroundColor: c.danger,
                          ),
                          child: Text(l.delete),
                        ),
                      if (onSaveAndConnect != null)
                        TextButton(
                          onPressed: onSaveAndConnect,
                          child: Text(saveAndConnectLabel ?? l.saveAndConnect),
                        ),
                      const Spacer(),
                      OutlinedButton(onPressed: _leave, child: Text(l.cancel)),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: saveEnabled ? onSave : null,
                        child: Text(saveLabel ?? l.save),
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
}

/// «Favorito»: up in the sidebar, in the rail and on the start page.
class FavoriteRow extends StatelessWidget {
  const FavoriteRow({
    super.key,
    required this.favorite,
    required this.onChanged,
  });

  final bool favorite;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    return Padding(
      padding: const EdgeInsets.only(
        left: editorLabelWidth,
        right: editorResetWidth,
      ),
      child: MergeSemantics(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radius),
          ),
          child: InkWell(
            key: const ValueKey('host.favorite'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => onChanged(!favorite),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OwSpace.s5,
                vertical: OwSpace.s3,
              ),
              child: Row(
                children: [
                  Icon(
                    favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: favorite ? c.warn : c.textSubtle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: l.favorite,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          TextSpan(
                            text: ' · ${l.favoriteNote}',
                            style: TextStyle(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Checkbox(
                    value: favorite,
                    onChanged: (v) => onChanged(v ?? false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the server runs: its logo, what told it, and the systems to choose
/// one by hand.
class SystemBlock extends StatelessWidget {
  const SystemBlock({
    super.key,
    required this.told,
    required this.chosen,
    required this.env,
    required this.onChanged,
  });

  /// What connecting told, or what was chosen before.
  final SystemView? told;

  /// Chosen by hand in this editor (or before); null: what connecting tells.
  final String? chosen;
  final EnvironmentView? env;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final t = told;
    final detected = t != null && t.kind != SystemKind.manual ? t : null;
    final code = chosen ?? detected?.code;
    final name = chosen != null
        ? systemName(l, chosen!)
        : detected == null
        ? null
        : detected.name.isEmpty
        ? systemName(l, detected.code)
        : detected.name;
    final how = chosen != null
        ? Text(
            l.systemManual,
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          )
        : detected == null
        ? Text(
            l.systemNotYet,
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: detected.kind == SystemKind.osRelease
                      ? l.systemByOsRelease
                      : l.systemByBanner,
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: detected.evidence,
                  style: monoStyle(context, size: 12, color: c.text),
                ),
              ],
            ),
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          );
    return Padding(
      padding: const EdgeInsets.only(right: editorResetWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: editorLabelWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SystemBadge(code: code, env: env, size: 38),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? l.systemUnknownYet,
                      key: const ValueKey('system.name'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    how,
                    if (chosen != null)
                      TextButton(
                        key: const ValueKey('system.detect'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () => onChanged(null),
                        child: Text(l.systemDetectAgain),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: editorLabelWidth),
            child: Semantics(
              label: l.systemIcon,
              container: true,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final s in systemCodes)
                    Tooltip(
                      message: systemName(l, s),
                      child: Semantics(
                        button: true,
                        selected: s == code,
                        label: systemName(l, s),
                        onTap: () => onChanged(s),
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey('system.$s'),
                          borderRadius: BorderRadius.circular(
                            context.ow.shape.radius,
                          ),
                          onTap: () => onChanged(s),
                          child: Container(
                            padding: const EdgeInsets.all(OwSpace.s1),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: s == code
                                    ? c.accent
                                    : Colors.transparent,
                              ),
                              borderRadius: BorderRadius.circular(
                                context.ow.shape.radius,
                              ),
                            ),
                            child: SystemBadge(
                              code: s,
                              env: s == code ? env : null,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
