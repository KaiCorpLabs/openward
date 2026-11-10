// The rows the editors are made of: a setting, a plain field, the jump
// chain, the tags, a section.

import 'package:flutter/material.dart';

import '../../core/address.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/vault.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// «Advanced»: folds the settings that are changed less often, and says
/// how many of them are set here.
class AdvancedToggle extends StatelessWidget {
  const AdvancedToggle({
    super.key,
    required this.open,
    required this.setHere,
    required this.onTap,
    this.list,
  });

  final bool open;
  final int setHere;
  final VoidCallback onTap;

  /// What is under it, when not SSH's.
  final String? list;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(
        top: OwSpace.s1,
        bottom: OwSpace.s6,
        right: editorResetWidth,
      ),
      child: Semantics(
        button: true,
        expanded: open,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('settings.advanced'),
              borderRadius: BorderRadius.circular(ow.shape.radius),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: OwSpace.s6,
                  vertical: OwSpace.s5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: c.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.advanced,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Expanded(
                      child: Text(
                        ' · ${list ?? l.advancedList}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: OwText.small,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                    if (setHere > 0)
                      Text(
                        l.advancedSetHere(setHere),
                        style: TextStyle(
                          fontSize: OwText.small,
                          color: c.accentText,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One setting: its own editor when set here; otherwise the inherited
/// value in a dashed box that says where it comes from, and a click on it
/// sets it here. Set here, ↺ goes back to inheriting.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.field,
    required this.label,
    required this.isSet,
    required this.editor,
    required this.inherited,
    required this.origin,
    required this.note,
    required this.onChange,
    required this.onClear,
    this.mono = false,
    this.noteAction,
  });

  /// Its name in the vault, for its keys.
  final String field;
  final String label;
  final bool isSet;
  final Widget editor;
  final String inherited;

  /// Where the inherited value comes from: «Del grupo prod».
  final String origin;

  /// Set here: what it would inherit otherwise.
  final String note;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final bool mono;

  /// A link under it: «Editar la identidad».
  final (String, VoidCallback)? noteAction;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    Widget link((String, VoidCallback) action) => InkWell(
      onTap: action.$2,
      child: Text(
        action.$1,
        style: TextStyle(
          fontSize: OwText.small,
          color: c.text,
          decoration: TextDecoration.underline,
          decorationColor: c.textSubtle,
        ),
      ),
    );
    final inheritedBox = Tooltip(
      message: l.setHereHint,
      waitDuration: OwMotion.hint,
      child: Semantics(
        button: true,
        label: '$label: $inherited',
        hint: '$origin. ${l.setHereHint}',
        // It hides the InkWell's own: the action goes here.
        onTap: onChange,
        excludeSemantics: true,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('setting.$field'),
              borderRadius: BorderRadius.circular(ow.shape.radius),
              mouseCursor: SystemMouseCursors.text,
              onTap: onChange,
              child: CustomPaint(
                painter: _DashedBorder(c.control, ow.shape.radius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OwSpace.s5,
                    vertical: OwSpace.s4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          inherited,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mono
                              ? monoStyle(context, size: 13)
                              : TextStyle(color: c.textMuted),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          origin,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: OwText.small,
                            color: c.textSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: OwSpace.s5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: editorLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: OwSpace.s4),
              child: Text(label, style: TextStyle(color: c.textMuted)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSet) editor else inheritedBox,
                if (isSet)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: OwSpace.s2,
                      left: OwSpace.s1,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: c.accentText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: OwText.small,
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        if (noteAction case final action?) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: OwText.small,
                              color: c.textSubtle,
                            ),
                          ),
                          link(action),
                        ],
                      ],
                    ),
                  )
                else if (noteAction case final action?)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: OwSpace.s2,
                      left: OwSpace.s1,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: link(action),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: editorResetWidth,
            child: isSet
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: OwSpace.s1,
                      left: OwSpace.s2,
                    ),
                    child: IconButton(
                      key: ValueKey('setting.$field.reset'),
                      tooltip: l.inheritAgain,
                      icon: const Icon(Icons.undo, size: 17),
                      onPressed: onClear,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The width of the labels on the left, the same in every row; what is
/// under the fields of an [EditorFieldRow] starts past it.
const double editorLabelWidth = 132;

/// The column of ↺ on the right.
const double editorResetWidth = 44;

/// A field with its label on the left, aligned with the settings below.
/// Editors without inherited settings (identities) need no room for ↺.
class EditorFieldRow extends StatelessWidget {
  const EditorFieldRow(this.label, this.field, {super.key, this.reset = true});

  final String label;
  final Widget field;
  final bool reset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: OwSpace.s5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: editorLabelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: OwSpace.s4),
            child: Text(
              label,
              style: TextStyle(color: context.ow.colors.textMuted),
            ),
          ),
        ),
        Expanded(child: field),
        if (reset) const SizedBox(width: editorResetWidth),
      ],
    ),
  );
}

/// One line on how inheriting reads: dashed is inherited, solid is set
/// here, ↺ inherits again; the order of inheritance behind the (i).
class InheritLegend extends StatelessWidget {
  const InheritLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final small = TextStyle(fontSize: OwText.small, color: c.textMuted);
    Widget swatch({required bool dashed}) => SizedBox(
      width: 18,
      height: 11,
      child: dashed
          ? CustomPaint(painter: _DashedBorder(c.textSubtle, 3))
          : DecoratedBox(
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.textSubtle),
                borderRadius: BorderRadius.circular(
                  context.ow.shape.radiusSmall,
                ),
              ),
            ),
    );
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(text, style: small),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: OwSpace.s6),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                item(swatch(dashed: true), l.legendInherited),
                item(swatch(dashed: false), l.legendSetHere),
                item(
                  Icon(Icons.undo, size: 13, color: c.textMuted),
                  l.legendInheritAgain,
                ),
              ],
            ),
          ),
          Tooltip(
            message: l.connectionHint,
            child: Semantics(
              label: l.connectionHint,
              child: Icon(Icons.info_outline, size: 16, color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded, dashed outline: an inherited value, not one set here.
class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// The hops in order, each removable, and ways to add one: a saved host or
/// an address.
class JumpChain extends StatelessWidget {
  const JumpChain({
    super.key,
    required this.jumps,
    required this.hosts,
    required this.address,
    required this.label,
    required this.onChanged,
  });

  final List<JumpSpec> jumps;
  final List<(String, String)> hosts;
  final TextEditingController address;
  final String Function(JumpSpec) label;
  final VoidCallback onChanged;

  void _addAddress() {
    final j = parseJumpAddress(address.text);
    if (j == null) return;
    jumps.add(j);
    address.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.jumpThrough,
          style: TextStyle(fontSize: OwText.small, color: c.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < jumps.length; i++) ...[
              if (i > 0)
                Icon(Icons.arrow_forward, size: 14, color: c.textSubtle),
              InputChip(
                label: Text(label(jumps[i])),
                avatar: Icon(
                  jumps[i].hostId != null ? Icons.dns_outlined : Icons.lan,
                  size: 14,
                ),
                onDeleted: () {
                  jumps.removeAt(i);
                  onChanged();
                },
              ),
            ],
            if (jumps.isEmpty)
              Text(
                l.noJumpsYet,
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          style: fieldTextStyle(context),
          key: ValueKey(jumps.length),
          decoration: InputDecoration(hintText: l.addSavedHost),
          items: [
            for (final (id, name) in hosts)
              DropdownMenuItem(value: id, child: Text(name)),
          ],
          onChanged: (id) {
            if (id == null) return;
            jumps.add(JumpSpec(hostId: id));
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: address,
          decoration: InputDecoration(
            hintText: l.orAnAddress,
            suffixIcon: IconButton(
              tooltip: l.add,
              icon: const Icon(Icons.add, size: 16),
              onPressed: _addAddress,
            ),
          ),
          onSubmitted: (_) => _addAddress(),
        ),
      ],
    );
  }
}

/// Tags as chips, with a field to add more (Enter or a comma).
class TagsField extends StatefulWidget {
  const TagsField({super.key, required this.tags});

  final List<String> tags;

  @override
  State<TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<TagsField> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add(String text) {
    final tags = text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !widget.tags.contains(t));
    setState(() {
      widget.tags.addAll(tags);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final l = context.l10n;
    return InputDecorator(
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(
          horizontal: OwSpace.s3,
          vertical: OwSpace.s3,
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in widget.tags)
            Container(
              padding: const EdgeInsets.only(left: OwSpace.s3),
              decoration: BoxDecoration(
                color: ow.colors.accentSoft,
                borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: ow.colors.accentText,
                    ),
                  ),
                  IconButton(
                    tooltip: l.removeTag(t),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 12,
                    color: ow.colors.accentText,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => widget.tags.remove(t)),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
            child: TextField(
              key: const ValueKey('host.tags'),
              controller: _field,
              decoration: InputDecoration(
                hintText: l.addTag,
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                // 28 high: a target like the rest.
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: OwSpace.s2,
                  vertical: OwSpace.s4,
                ),
              ),
              onChanged: (v) {
                if (v.contains(',')) _add(v);
              },
              onSubmitted: _add,
            ),
          ),
        ],
      ),
    );
  }
}

class EditorSection extends StatelessWidget {
  const EditorSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: OwSpace.s4, bottom: OwSpace.s6),
    child: SectionLabel(title),
  );
}
