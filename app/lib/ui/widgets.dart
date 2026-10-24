import 'package:flutter/material.dart';

import 'focus_ring.dart';
import 'tokens.dart';

/// A small button's text: 12 px in the interface's font. A button style's
/// own text style replaces the theme's instead of merging with it, so it
/// names the font too.
TextStyle smallButtonText(BuildContext context) =>
    TextStyle(fontFamily: context.ow.fonts.ui, fontSize: 12);

/// How a host or a tab is doing. Each one has its own shape as well as its
/// color, so it does not depend on telling colors apart.
enum Status { idle, connecting, connected, warning, failed }

/// A small mark for a [Status]: a ring when idle, a filled dot when
/// connected, half-filled while connecting, a filled square on trouble.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 8, this.onAccent});

  final Status status;
  final double size;

  /// Drawn on an accent background (a selected row): white marks.
  final Color? onAccent;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final color =
        onAccent ??
        switch (status) {
          Status.idle => c.textSubtle,
          Status.connecting => c.warn,
          Status.connected => c.accent,
          Status.warning => c.warn,
          Status.failed => c.danger,
        };
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _DotPainter(status, color)),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.status, this.color);

  final Status status;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    switch (status) {
      case Status.idle:
        canvas.drawCircle(center, r - 0.75, ring);
      case Status.connected:
        canvas.drawCircle(center, r, fill);
      case Status.connecting:
        canvas.drawCircle(center, r - 0.75, ring);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          -1.5708,
          3.1416,
          true,
          fill,
        );
      case Status.warning || Status.failed:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(size.width / 4),
          ),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.status != status || old.color != color;
}

enum PillTone { accent, warm, neutral }

/// A short tag on a row.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.accent});

  final String text;
  final PillTone tone;

  /// Tags keep their color everywhere: picked from the text.
  factory Pill.tag(String text) => Pill(
    text,
    tone: text.codeUnits.fold(0, (a, b) => a + b).isEven
        ? PillTone.accent
        : PillTone.warm,
  );

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final (fg, bg) = switch (tone) {
      PillTone.accent => (c.accentText, c.accentSoft),
      PillTone.warm => (c.tagWarm, c.tagWarmSoft),
      PillTone.neutral => (c.textMuted, c.sunken),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          ow.shape.pills ? 999 : ow.shape.radiusSmall,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(fontSize: 12, color: fg, height: 1.3),
      ),
    );
  }
}

/// The small upper-case title of a group of things.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.keepCase = false,
  });

  /// The text is the user's (a group's name): as written, not in capitals.
  final bool keepCase;

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final fonts = ow.fonts;
    final serif = fonts.serifLabels && fonts.display != null;
    // Small capitals, or (Papel) the display face in italics.
    final style = serif
        ? TextStyle(
            fontFamily: fonts.display,
            fontStyle: FontStyle.italic,
            fontSize: 16,
            color: ow.colors.text,
          )
        : Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ow.colors.textSubtle,
            fontFamily: fonts.label ?? fonts.ui,
            fontSize: 12,
            letterSpacing: keepCase ? 0 : (fonts.label != null ? 1 : 0.6),
            fontWeight: keepCase ? FontWeight.w600 : null,
          );
    return Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(
            child: Text(
              serif || keepCase ? text : text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: style?.copyWith(
                fontFamily: ow.fonts.mono,
                fontStyle: FontStyle.normal,
                fontSize: 12,
                color: ow.colors.textSubtle,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// A keyboard shortcut as a key cap: ⌘K.
class KeyCap extends StatelessWidget {
  const KeyCap(this.keys, {super.key});

  final String keys;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: ow.colors.control),
          borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
        ),
        child: Text(
          keys,
          style: TextStyle(
            fontFamily: ow.fonts.mono,
            fontSize: 12,
            color: ow.colors.textSubtle,
          ),
        ),
      ),
    );
  }
}

/// The text of fields and menus: body size, never Material's title style.
TextStyle fieldTextStyle(BuildContext context) =>
    TextStyle(fontSize: 13, color: context.ow.colors.text);

/// Monospace text for addresses and fingerprints.
TextStyle monoStyle(BuildContext context, {double size = 12, Color? color}) {
  final ow = context.ow;
  return TextStyle(
    fontFamily: ow.fonts.mono,
    fontSize: size,
    color: color ?? ow.colors.textMuted,
  );
}

/// A message in a colored box: what is wrong, or what needs a look.
enum Tone { info, warn, danger }

class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.tone,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 16),
  });

  final Tone tone;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final (bg, line) = switch (tone) {
      Tone.info => (c.infoSoft, c.infoLine),
      Tone.warn => (c.warnSoft, c.warnLine),
      Tone.danger => (c.dangerSoft, c.dangerLine),
    };
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: child,
    );
  }
}

/// A ring around something while the keyboard is on it (or inside it):
/// rows of lists and tables, which have no outline of their own. Not
/// drawn for mouse clicks.
class FocusOutline extends StatefulWidget {
  const FocusOutline({super.key, required this.child, this.radius});

  final Widget child;

  /// The corner radius; the theme's by default.
  final double? radius;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final keyboard = KeyboardMode.active.value;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _focused && keyboard
            ? BoxDecoration(
                border: Border.all(color: ow.colors.accent, width: 2),
                borderRadius: BorderRadius.circular(
                  widget.radius ?? ow.shape.radius + 2,
                ),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}

/// A height that holds a line of text: `base` at the usual size, more as
/// the text grows.
double heightForText(BuildContext context, double base) =>
    base * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
