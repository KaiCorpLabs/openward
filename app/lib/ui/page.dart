// The pieces every page of the Library is made of: its header, what it
// says when it has nothing to show, its filter, its table and the small
// buttons in a row. One place, so the pages look and read alike.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'focus_ring.dart';
import 'tokens.dart';
import 'widgets.dart' show FocusOutline, smallButtonText;

/// Pages of the Library: the room around them.
const pagePadding = EdgeInsets.fromLTRB(28, 24, 28, 24);

/// A page's top: its title, a header for screen readers; what it is for;
/// and its main action, on the right.
class OwPageHeader extends StatelessWidget {
  const OwPageHeader({super.key, required this.title, this.intro, this.action});

  final String title;
  final String? intro;
  final Widget? action;

  /// The intro's measure: lines a reader can follow.
  static const introWidth = 680.0;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: introWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (intro case final intro?) ...[
                    const SizedBox(height: 4),
                    Text(intro, style: TextStyle(color: c.textMuted)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (action case final action?) ...[const SizedBox(width: 16), action],
      ],
    );
  }
}

/// What a page or a list says with nothing to show: why, and what to do.
class OwEmptyState extends StatelessWidget {
  const OwEmptyState({
    super.key,
    required IconData this.icon,
    required String this.title,
    this.body,
    this.action,
  }) : filter = null,
       onClear = null;

  /// A filter that leaves nothing: says so, with a way back to everything.
  const OwEmptyState.noMatch({
    super.key,
    required String this.filter,
    required VoidCallback this.onClear,
  }) : icon = null,
       title = null,
       body = null,
       action = null;

  final IconData? icon;
  final String? title;
  final String? body;
  final Widget? action;
  final String? filter;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final none = filter != null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: none ? 32 : 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              none ? Icons.search_off : icon,
              size: none ? 28 : 36,
              color: c.textSubtle,
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: none,
              child: Text(
                none ? l.noMatches(filter!) : title!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (body case final body?) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted),
                ),
              ),
            ],
            if (none) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onClear, child: Text(l.clearFilter)),
            ] else if (action case final action?) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// The filter above a list.
class OwFilterField extends StatelessWidget {
  const OwFilterField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.width = 360,
    this.style,
    this.count,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  /// What is typed, when it is not words (addresses, in the mono font).
  final TextStyle? style;

  /// How many there are, after it; both give way in a narrow window.
  final String? count;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      style: style ?? const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: c.textSubtle),
        prefixIcon: Icon(Icons.search, size: 16, color: c.textSubtle),
      ),
    );
    final count = this.count;
    if (count == null) return SizedBox(width: width, child: field);
    return Row(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: field,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

/// A table of the Library: its headings in small capitals on the sunken
/// color, then its rows, each with a hairline above. `widths` are the
/// columns' shares.
class OwDataTable extends StatelessWidget {
  const OwDataTable({
    super.key,
    required this.widths,
    required this.headings,
    required this.rows,
    this.hideBelow,
  });

  final List<double> widths;
  final List<String> headings;
  final List<Widget> rows;

  /// For each column, the table's width under which it goes: the less
  /// needed ones first, in a small window. Null keeps it always.
  final List<double?>? hideBelow;

  /// A row's cells, in the table's columns (those that fit).
  static Widget cells(List<double> widths, List<Widget> cells) =>
      _Cells(widths, cells);

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: c.textSubtle,
    );
    return LayoutBuilder(
      builder: (context, box) => _Columns(
        shown: [
          for (var i = 0; i < widths.length; i++)
            switch (hideBelow?.elementAtOrNull(i)) {
              final below? => box.maxWidth >= below,
              null => true,
            },
        ],
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          ),
          child: Column(
            children: [
              Container(
                color: c.sunken,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: cells(widths, [
                  for (final h in headings) Text(h.toUpperCase(), style: head),
                ]),
              ),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

/// Which columns of the table around fit.
class _Columns extends InheritedWidget {
  const _Columns({required this.shown, required super.child});

  final List<bool> shown;

  static List<bool>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Columns>()?.shown;

  @override
  bool updateShouldNotify(_Columns old) => !listEquals(old.shown, shown);
}

class _Cells extends StatelessWidget {
  const _Cells(this.widths, this.cells);

  final List<double> widths;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final shown = _Columns.of(context);
    final kept = [
      for (var i = 0; i < cells.length; i++)
        if (shown == null || i >= shown.length || shown[i]) i,
    ];
    return Row(
      children: [
        for (final i in kept)
          Expanded(
            flex: (widths[i] * 100).round(),
            child: Padding(
              padding: EdgeInsets.only(right: i == kept.last ? 0 : 12),
              child: cells[i],
            ),
          ),
      ],
    );
  }
}

/// A row of an [OwDataTable], pressed to open what it is.
class OwTableRow extends StatelessWidget {
  const OwTableRow({
    super.key,
    required this.widths,
    required this.cells,
    this.onTap,
    this.inkKey,
    this.color,
  });

  final List<double> widths;
  final List<Widget> cells;
  final VoidCallback? onTap;

  /// Behind the row: one just added, say.
  final Color? color;

  /// For the tests, on what is pressed.
  final Key? inkKey;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: color,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: OwDataTable.cells(widths, cells),
    );
    if (onTap == null) return row;
    return FocusOutline(
      radius: 0,
      child: InkWell(key: inkKey, onTap: onTap, child: row),
    );
  }
}

/// The small buttons of a row or a notice: 28 px high, their text 12 px,
/// with the focus ring. `line` is their border.
ButtonStyle compactButtonStyle(
  BuildContext context, {
  Color? foreground,
  Color? background,
  Color? line,
}) {
  final c = context.ow.colors;
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 28),
    visualDensity: VisualDensity.standard,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    textStyle: smallButtonText(context),
    foregroundColor: foreground,
    backgroundColor: background,
  ).copyWith(
    side: ringedSide(c, side: BorderSide(color: line ?? c.control)),
  );
}
