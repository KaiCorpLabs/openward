import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/snippets.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'snippets.dart';
import 'snippets_page.dart';

/// Creates (no `snippet`) or edits a snippet in the side panel. True if
/// something was saved.
Future<bool> showSnippetEditor(
  BuildContext context,
  WidgetRef ref, {
  SnippetView? snippet,
}) => showSidePanel(context, (_) => _SnippetEditor(snippet: snippet));

/// A text field that marks the `{{variables}}` as they are typed.
class _ScriptController extends TextEditingController {
  _ScriptController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (value.composing.isValid && withComposing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return highlightVariables(context, text, style ?? const TextStyle());
  }
}

class _SnippetEditor extends ConsumerStatefulWidget {
  const _SnippetEditor({this.snippet});

  final SnippetView? snippet;

  @override
  ConsumerState<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends ConsumerState<_SnippetEditor> {
  late final SnippetSpec? _old = widget.snippet?.spec;
  late final _label = TextEditingController(text: _old?.label ?? '');
  late final _script = _ScriptController(text: _old?.script ?? '');
  late final Map<String, TextEditingController> _defaults = {
    for (final d in _old?.defaults ?? const <SnippetValue>[])
      d.name: TextEditingController(text: d.value),
  };
  late bool _enter = !(_old?.typeOnly ?? false);
  late SnippetVariables _vars = snippetVariables(script: _script.text);
  String? _error;
  Object? _cause;

  String _snapshot() => [
    _label.text,
    _script.text,
    _enter,
    for (final MapEntry(:key, :value) in _defaults.entries)
      if (value.text.isNotEmpty) '$key=${value.text}',
  ].join('\u0000');

  @override
  void dispose() {
    for (final c in [_label, _script, ..._defaults.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _default(String name) =>
      _defaults.putIfAbsent(name, TextEditingController.new);

  SnippetSpec _spec() => SnippetSpec(
    label: _label.text.trim(),
    script: _script.text,
    defaults: [
      for (final name in _vars.asked)
        if (_default(name).text.isNotEmpty)
          SnippetValue(name: name, value: _default(name).text),
    ],
    typeOnly: !_enter,
  );

  Future<void> _save() async {
    final l = context.l10n;
    _cause = null;
    if (_label.text.trim().isEmpty) {
      return setState(() => _error = l.snippetNeedsName);
    }
    if (_script.text.trim().isEmpty) {
      return setState(() => _error = l.snippetNeedsCommand);
    }
    final app = ref.read(openWardProvider);
    try {
      final old = widget.snippet;
      if (old == null) {
        await app.createSnippet(spec: _spec());
      } else {
        await app.updateSnippet(id: old.id, rev: old.rev, spec: _spec());
      }
      ref.read(snippetsProvider.notifier).refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  /// Deletes it at once; the notice that says so can bring it back.
  Future<void> _delete() async {
    final old = widget.snippet;
    if (old == null) return;
    final l = context.l10n;
    final app = ref.read(openWardProvider);
    final snippets = ref.read(snippetsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.delete(id: old.id);
    } catch (e) {
      return setState(() {
        _error = l.deleteFailed(errorReason(l, e));
        _cause = e;
      });
    }
    snippets.refresh();
    if (mounted) Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.snippetDeleted(old.spec.label)),
        action: SnackBarAction(
          label: l.undo,
          onPressed: () async {
            try {
              await app.createSnippet(spec: old.spec);
            } catch (e) {
              showErrorNotice(messenger, saveErrorText(l, e), e);
            }
            snippets.refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final mono = monoStyle(context, size: 13, color: c.text);
    Widget labelled(String text, Widget field, {String? hint}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(text, style: TextStyle(color: c.textMuted)),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
    return EditorFrame(
      title: widget.snippet == null ? l.newSnippet : l.editSnippet,
      subtitle: l.snippetEditorHint,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      onDelete: widget.snippet == null ? null : _delete,
      snapshot: _snapshot,
      children: [
        labelled(
          l.name,
          TextField(
            key: const ValueKey('snippet.label'),
            controller: _label,
            autofocus: widget.snippet == null,
          ),
        ),
        const SizedBox(height: 16),
        labelled(
          l.command,
          hint: l.commandHint('{{', r'\{{'),
          TextField(
            key: const ValueKey('snippet.script'),
            controller: _script,
            minLines: 4,
            maxLines: 12,
            style: mono.copyWith(height: 1.5),
            onChanged: (text) =>
                setState(() => _vars = snippetVariables(script: text)),
            decoration: InputDecoration(
              hintText: 'sudo systemctl restart {{servicio}}',
              hintStyle: monoStyle(context, size: 13, color: c.textSubtle),
            ),
          ),
        ),
        const SizedBox(height: 16),
        labelled(
          l.askedWhenRun,
          hint: l.askedWhenRunHint,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.sunken,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(ow.shape.radius),
            ),
            child: _vars.asked.isEmpty
                ? Text(
                    l.asksNothing('{{${l.exampleVariable}}}'),
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  )
                : Column(
                    children: [
                      for (final name in _vars.asked)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Pill(name, tone: PillTone.warm),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  key: ValueKey('snippet.default.$name'),
                                  controller: _default(name),
                                  style: mono,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: l.defaultValueOptional,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l.filledInEachPane,
              style: TextStyle(fontSize: 12, color: c.textSubtle),
            ),
            for (final b in const ['host', 'address', 'user', 'port'])
              Pill(b, tone: PillTone.neutral),
          ],
        ),
        const SizedBox(height: 16),
        Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radius),
          ),
          child: SwitchListTile(
            key: const ValueKey('snippet.enter'),
            value: _enter,
            onChanged: (v) => setState(() => _enter = v),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.pressEnterAtTheEnd),
            subtitle: Text(
              l.pressEnterAtTheEndNote,
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Callout(
          tone: Tone.info,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.snippetNoSecrets,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
