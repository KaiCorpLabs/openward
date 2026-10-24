import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../terminal/palette.dart';
import '../terminal/scheme_import.dart';
import '../terminal/schemes.dart';
import '../ui/themes.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Fonts offered for the interface; null keeps the theme's, '' is the
/// system's.
const _uiFonts = [
  'IBM Plex Sans',
  'Instrument Sans',
  'JetBrains Mono',
  'IBM Plex Mono',
  'Martian Mono',
  'Share Tech Mono',
];
const _terminalFonts = [
  'JetBrains Mono',
  'IBM Plex Mono',
  'Martian Mono',
  'Share Tech Mono',
  'VT323',
];

/// A contrast ratio as the language writes decimals: 4,5 or 4.5.
String _ratio(AppLocalizations l, double value) =>
    NumberFormat.decimalPatternDigits(
      locale: l.localeName,
      decimalDigits: 1,
    ).format(value);

/// A theme's name as the gallery shows it: «Nativo (oscuro)».
String themeName(AppLocalizations l, OwTheme t) {
  final family = OwThemes.familyOf(t);
  if (family.light == null || family.dark == null) return family.name;
  return l.themeVariant(
    family.name,
    t.colors.dark ? l.variantDark : l.variantLight,
  );
}

/// Ajustes › Apariencia: which themes, their layers, and what helps to
/// read them.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final preview = _Preview(theme: context.ow);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 900;
        final form = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(l.theme),
            const SizedBox(height: 10),
            const _ThemeChoice(),
            const SizedBox(height: 28),
            const _Layers(),
            const SizedBox(height: 28),
            SectionLabel(l.accessibility),
            const SizedBox(height: 4),
            const _Accessibility(),
            if (!wide) ...[const SizedBox(height: 24), preview],
          ],
        );
        if (!wide) return form;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: form),
            const SizedBox(width: 28),
            SizedBox(width: 320, child: preview),
          ],
        );
      },
    );
  }
}

/// Light, dark or the system's, which theme for each, and the gallery.
class _ThemeChoice extends ConsumerWidget {
  const _ThemeChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    final c = context.ow.colors;
    final now = Theme.of(context).brightness;
    final style = fieldTextStyle(context);
    // The family of the theme in use: a setting may name one of its
    // variants (an older one, or one written by hand).
    String family(Brightness b) {
      final id = resolveTheme(s, b).id;
      return OwThemes.families
          .firstWhere(
            (f) => f.variant(b)?.id == id,
            orElse: () => OwThemes.families.first,
          )
          .id;
    }

    DropdownButton<String> slot(Brightness b) => DropdownButton<String>(
      key: ValueKey('theme.${b.name}'),
      style: style,
      value: family(b),
      items: [
        for (final f in OwThemes.families)
          if (f.variant(b) != null)
            DropdownMenuItem(value: f.id, child: Text(f.name)),
      ],
      onChanged: (id) => notifier.update(
        (s) => b == Brightness.light
            ? s.copyWith(lightTheme: id)
            : s.copyWith(darkTheme: id),
      ),
    );

    // A card sets the theme for the brightness it has; if it only comes in
    // the other one and the mode is fixed, the mode follows.
    void pick(ThemeFamily f) => notifier.update((s) {
      final b = f.variant(now) != null
          ? now
          : (now == Brightness.light ? Brightness.dark : Brightness.light);
      var next = b == Brightness.light
          ? s.copyWith(lightTheme: f.id)
          : s.copyWith(darkTheme: f.id);
      if (b != now && s.theme != ThemeChoice.system) {
        next = next.copyWith(
          theme: b == Brightness.light ? ThemeChoice.light : ThemeChoice.dark,
        );
      }
      return next;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeChoice.system,
                  label: Text(l.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeChoice.light,
                  label: Text(l.themeLight),
                ),
                ButtonSegment(
                  value: ThemeChoice.dark,
                  label: Text(l.themeDark),
                ),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) =>
                  notifier.update((s) => s.copyWith(theme: v.single)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.inLight, style: TextStyle(color: c.textMuted)),
                const SizedBox(width: 8),
                slot(Brightness.light),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.inDark, style: TextStyle(color: c.textMuted)),
                const SizedBox(width: 8),
                slot(Brightness.dark),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in OwThemes.families)
              _FamilyCard(
                family: f,
                brightness: now,
                current:
                    (now == Brightness.light ? s.lightTheme : s.darkTheme) ==
                    f.id,
                inLight: s.lightTheme == f.id,
                inDark: s.darkTheme == f.id,
                onTap: () => pick(f),
              ),
          ],
        ),
      ],
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.brightness,
    required this.current,
    required this.inLight,
    required this.inDark,
    required this.onTap,
  });

  final ThemeFamily family;
  final Brightness brightness;
  final bool current;
  final bool inLight;
  final bool inDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final shown = family.variant(brightness) ?? (family.light ?? family.dark)!;
    final badge = [if (inLight) l.inLight, if (inDark) l.inDark].join(' · ');
    final kinds = family.light != null && family.dark != null
        ? l.lightAndDark
        : family.light != null
        ? l.variantLightOnly
        : l.variantDarkOnly;
    return Semantics(
      button: true,
      selected: current,
      label: family.name,
      child: InkWell(
        key: ValueKey('family.${family.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        child: Container(
          width: 134,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            border: Border.all(color: current ? c.accent : c.control, width: 2),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 60, child: MiniWindow(theme: shown)),
                const SizedBox(height: 6),
                Text(
                  family.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  badge.isEmpty ? kinds : badge,
                  style: TextStyle(
                    fontSize: 12,
                    color: badge.isEmpty ? c.textSubtle : c.accentText,
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

/// A theme's window in miniature: sidebar, terminal and three lines.
class MiniWindow extends StatelessWidget {
  const MiniWindow({super.key, required this.theme});

  final OwTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = theme.colors;
    final t = theme.terminal;
    Widget line(Color color, double width) => FractionallySizedBox(
      widthFactor: width,
      child: Container(height: 3, color: color),
    );
    final inset = theme.shape.insetTerminal;
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: c.window,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(
            theme.shape.radius.clamp(0, 6).toDouble(),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 26),
            Expanded(
              child: Container(
                margin: inset ? const EdgeInsets.all(5) : EdgeInsets.zero,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(inset ? 4 : 0),
                  border: inset ? Border.all(color: c.border) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(t.ansi16[2], 0.6),
                    const SizedBox(height: 4),
                    line(t.foreground, 0.85),
                    const SizedBox(height: 4),
                    line(t.ansi16[4], 0.45),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The layers of the theme on screen: change one, keep the rest.
class _Layers extends ConsumerWidget {
  const _Layers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final base = OwThemes.all[ow.id]!;
    final o = s.overrides[ow.id] ?? const ThemeOverrides();
    final style = fieldTextStyle(context);
    void change(ThemeOverrides Function(ThemeOverrides) f) =>
        notifier.update((s) => s.withOverrides(ow.id, f));

    Widget field(String label, Widget control) => SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.textMuted)),
          const SizedBox(height: 4),
          control,
        ],
      ),
    );

    DropdownButton<String> themes(String? value, ValueChanged<String?> set) =>
        DropdownButton<String>(
          isExpanded: true,
          style: style,
          value: value ?? base.id,
          items: [
            for (final t in OwThemes.all.values)
              DropdownMenuItem(value: t.id, child: Text(themeName(l, t))),
          ],
          onChanged: (id) => set(id == base.id ? null : id),
        );

    DropdownButton<String> fonts(
      String? value,
      List<String> names,
      ValueChanged<String?> set,
    ) {
      const fromTheme = '\u0000theme';
      const other = '\u0000other';
      final custom = value != null && value.isNotEmpty && !names.contains(value)
          ? value
          : null;
      return DropdownButton<String>(
        isExpanded: true,
        style: style,
        value: value ?? fromTheme,
        items: [
          DropdownMenuItem(value: fromTheme, child: Text(l.fontFromTheme)),
          DropdownMenuItem(value: '', child: Text(l.fontSystem)),
          for (final n in [...names, ?custom])
            DropdownMenuItem(
              value: n,
              child: Text(n, style: style.copyWith(fontFamily: n)),
            ),
          DropdownMenuItem(value: other, child: Text(l.fontOther)),
        ],
        onChanged: (v) async {
          if (v == other) {
            final name = await _askFont(context);
            if (name != null) set(name);
          } else {
            set(v == fromTheme ? null : v);
          }
        },
      );
    }

    final schemes = [...knownSchemes, ...s.schemes];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(l.customize(themeName(l, base)))),
            if (!o.isEmpty)
              TextButton(
                onPressed: () => notifier.update(
                  (s) => s.withOverrides(ow.id, (_) => const ThemeOverrides()),
                ),
                child: Text(l.resetTheme),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            l.customizeHint,
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            field(
              l.uiColors,
              themes(
                o.colors,
                (id) => change((o) => o.copyWith(colors: () => id)),
              ),
            ),
            field(
              l.uiFont,
              fonts(
                o.uiFont,
                _uiFonts,
                (f) => change((o) => o.copyWith(uiFont: () => f)),
              ),
            ),
            field(
              l.shape,
              themes(
                o.shape,
                (id) => change((o) => o.copyWith(shape: () => id)),
              ),
            ),
            field(
              l.terminalFont,
              fonts(
                o.terminalFont,
                _terminalFonts,
                (f) => change((o) => o.copyWith(terminalFont: () => f)),
              ),
            ),
            field(
              l.fontSize,
              DropdownButton<double>(
                isExpanded: true,
                style: style,
                value: s.fontSize,
                items: [
                  for (final size in {...Settings.fontSizes, s.fontSize})
                    DropdownMenuItem(
                      value: size,
                      child: Text(l.pixels(size.round())),
                    ),
                ],
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(fontSize: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(l.terminalColors, style: TextStyle(color: c.textMuted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TerminalColors>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: TerminalColors.theme,
                  label: Text(l.terminalAsTheme),
                ),
                ButtonSegment(
                  value: TerminalColors.dark,
                  label: Text(l.terminalAlwaysDark),
                ),
                ButtonSegment(
                  value: TerminalColors.scheme,
                  label: Text(l.terminalScheme),
                ),
              ],
              selected: {o.terminal},
              onSelectionChanged: (v) => change(
                (o) => o.copyWith(
                  terminal: v.single,
                  scheme: v.single == TerminalColors.scheme && o.scheme == null
                      ? () => knownSchemes.first.id
                      : null,
                ),
              ),
            ),
            if (o.terminal == TerminalColors.scheme)
              SizedBox(
                width: 220,
                child: DropdownButton<String>(
                  key: const ValueKey('terminal.scheme'),
                  isExpanded: true,
                  style: style,
                  value: schemes.any((x) => x.id == o.scheme)
                      ? o.scheme
                      : schemes.first.id,
                  items: [
                    for (final x in schemes)
                      DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (id) =>
                      change((o) => o.copyWith(scheme: () => id)),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.file_open_outlined, size: 16),
            label: Text(l.importScheme),
          ),
        ),
        _ContrastWarning(theme: ow),
      ],
    );
  }

  /// An installed font, by name.
  Future<String?> _askFont(BuildContext context) async {
    final l = context.l10n;
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.fontOtherTitle),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: field,
            autofocus: true,
            decoration: InputDecoration(hintText: l.fontOtherHint),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(l.ok),
          ),
        ],
      ),
    );
    field.dispose();
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// A scheme from iTerm2 or Ghostty, kept and put on the theme on screen.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final id = context.ow.id;
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile();
    if (file == null) return;
    TerminalScheme? scheme;
    try {
      final f = File(file.path);
      if (await f.length() < 1 << 20) {
        scheme = parseScheme(file.name, await f.readAsString());
      }
    } catch (_) {
      scheme = null;
    }
    if (scheme == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.importSchemeFailed)));
      return;
    }
    final imported = scheme;
    ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s
              .copyWith(
                schemes: [
                  for (final x in s.schemes)
                    if (x.id != imported.id) x,
                  imported,
                ],
              )
              .withOverrides(
                id,
                (o) => o.copyWith(
                  terminal: TerminalColors.scheme,
                  scheme: () => imported.id,
                ),
              ),
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l.importSchemeDone(imported.name))),
    );
  }
}

/// A warning when the chosen layers leave text below AA.
class _ContrastWarning extends StatelessWidget {
  const _ContrastWarning({required this.theme});

  final OwTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = theme.colors;
    final t = theme.terminal;
    final worst = [
      TermPalette.contrast(c.text, c.window),
      TermPalette.contrast(c.textMuted, c.window),
      TermPalette.contrast(c.textSubtle, c.surface),
      TermPalette.contrast(t.foreground, t.background),
    ].reduce((a, b) => a < b ? a : b);
    if (worst >= 4.5) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Callout(
        tone: Tone.warn,
        padding: const EdgeInsets.all(12),
        child: Text(context.l10n.contrastWarning(_ratio(context.l10n, worst))),
      ),
    );
  }
}

class _Accessibility extends ConsumerWidget {
  const _Accessibility();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    final c = context.ow.colors;
    final style = fieldTextStyle(context);
    Widget row(String label, Widget control, {String? help}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (help != null)
                  Text(
                    help,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
    final percent = (s.textScale * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          l.textSize,
          SizedBox(
            width: 260,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const ValueKey('a11y.textScale'),
                    min: 0.85,
                    max: 1.5,
                    divisions: 13,
                    value: s.textScale.clamp(0.85, 1.5),
                    label: l.percent(percent),
                    onChanged: (v) => notifier.update(
                      (s) => s.copyWith(textScale: (v * 20).round() / 20),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    l.percent(percent),
                    textAlign: TextAlign.right,
                    style: monoStyle(context),
                  ),
                ),
              ],
            ),
          ),
          help: l.textSizeHelp,
        ),
        row(
          l.lineHeight,
          DropdownButton<double>(
            style: style,
            value: s.lineHeight,
            items: [
              for (final h in {...Settings.lineHeights, s.lineHeight})
                DropdownMenuItem(
                  value: h,
                  child: Text(
                    NumberFormat.decimalPatternDigits(
                      locale: l.localeName,
                      decimalDigits: 2,
                    ).format(h),
                  ),
                ),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(lineHeight: v)),
          ),
        ),
        row(
          l.minimumContrast,
          Switch(
            value: s.minimumContrast,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(minimumContrast: v)),
          ),
          help: l.minimumContrastHelp,
        ),
        row(
          l.reduceMotion,
          DropdownButton<MotionChoice>(
            style: style,
            value: s.motion,
            items: [
              DropdownMenuItem(
                value: MotionChoice.system,
                child: Text(l.asSystem),
              ),
              DropdownMenuItem(value: MotionChoice.reduce, child: Text(l.yes)),
              DropdownMenuItem(value: MotionChoice.full, child: Text(l.no)),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(motion: v)),
          ),
        ),
        row(
          l.cursor,
          SegmentedButton<CursorChoice>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CursorChoice.block,
                label: Text(l.cursorBlock),
              ),
              ButtonSegment(value: CursorChoice.bar, label: Text(l.cursorBar)),
              ButtonSegment(
                value: CursorChoice.underline,
                label: Text(l.cursorUnderline),
              ),
            ],
            selected: {s.cursor},
            onSelectionChanged: (v) =>
                notifier.update((s) => s.copyWith(cursor: v.single)),
          ),
          help: l.cursorHelp,
        ),
        row(
          l.cursorBlink,
          Switch(
            value: s.cursorBlink,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(cursorBlink: v)),
          ),
        ),
      ],
    );
  }
}

/// A sample of the terminal as it will look, and how well its text reads.
class _Preview extends ConsumerWidget {
  const _Preview({required this.theme});

  final OwTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final l = context.l10n;
    final c = theme.colors;
    final t = theme.terminal;
    final ratio = s.minimumContrast ? theme.minimumContrast : 1.0;
    Color fg(Color color) =>
        TermPalette.ensureContrast(color, t.background, ratio);
    final base = TextStyle(
      fontFamily: theme.fonts.terminal ?? platformMono,
      fontSize: s.fontSize,
      height: s.lineHeight,
      color: fg(t.foreground),
    );
    TextSpan span(String text, [int? ansi]) => TextSpan(
      text: text,
      style: ansi == null ? null : TextStyle(color: fg(t.ansi16[ansi])),
    );
    final prompt = [
      span('ana@laptop', 2),
      span(':'),
      span('~/app', 4),
      span('\$ '),
    ];
    final contrast = TermPalette.contrast(t.foreground, t.background);
    final passes = contrast >= 4.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l.preview),
        const SizedBox(height: 10),
        // The palette as it is, its contrast said below.
        Container(
          key: const ValueKey('appearance.terminalSample'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.background,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(theme.shape.radiusLarge),
          ),
          child: Text.rich(
            TextSpan(
              style: base,
              children: [
                ...prompt,
                span('ls\n'),
                span('src  tests  ', 4),
                span('deploy.sh', 2),
                span('  README.md\n'),
                ...prompt,
                span('./deploy.sh\n'),
                span(l.sampleWarning, 3),
                span(' ${l.sampleWarningText}\n'),
                span(l.sampleError, 1),
                span(' ${l.sampleErrorText}\n'),
                span('# ${l.sampleComment}\n', 8),
                ...prompt,
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              passes ? Icons.check : Icons.warning_amber_rounded,
              size: 14,
              color: passes ? c.accent : c.warn,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                passes
                    ? l.contrastPasses(_ratio(l, contrast))
                    : l.contrastFails(_ratio(l, contrast)),
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.previewLive,
          style: TextStyle(fontSize: 12, color: c.textSubtle),
        ),
      ],
    );
  }
}
