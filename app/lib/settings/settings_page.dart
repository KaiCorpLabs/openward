import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../core/version.dart';
import '../l10n/l10n.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

enum _Section { general, appearance, terminal }

/// Settings, in a tab of their own. They take effect as they change;
/// there is nothing to save.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  var _section = _Section.general;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                for (final s in _Section.values)
                  _NavItem(
                    text: switch (s) {
                      _Section.general => l.settingsGeneral,
                      _Section.appearance => l.settingsAppearance,
                      _Section.terminal => l.settingsTerminal,
                    },
                    selected: s == _section,
                    onTap: () => setState(() => _section = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: switch (_section) {
                    _Section.general => const _General(),
                    _Section.appearance => const _Appearance(),
                    _Section.terminal => const _Terminal(),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? c.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? c.text : c.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A setting: its name and what it does on the left, the control on the
/// right.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.control, this.help});

  final String label;
  final Widget control;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (help != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      help!,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          control,
        ],
      ),
    );
  }
}

class _General extends ConsumerWidget {
  const _General();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    final c = context.ow.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: l.language,
          control: DropdownButton<Language>(
            style: fieldTextStyle(context),
            value: s.language,
            items: [
              DropdownMenuItem(
                value: Language.system,
                child: Text(l.languageSystem),
              ),
              // Each language in its own words.
              const DropdownMenuItem(
                value: Language.es,
                child: Text('Español'),
              ),
              const DropdownMenuItem(
                value: Language.en,
                child: Text('English'),
              ),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(language: v)),
          ),
        ),
        if (isApple)
          _Row(
            label: l.optionAsAlt,
            help: l.optionAsAltHelp,
            control: Switch(
              value: s.optionAsAlt,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(optionAsAlt: v)),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          l.aboutVersion(appVersion),
          style: TextStyle(fontSize: 12, color: c.textSubtle),
        ),
      ],
    );
  }
}

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: l.theme,
          help: l.themeHelp,
          control: SegmentedButton<ThemeChoice>(
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
              ButtonSegment(value: ThemeChoice.dark, label: Text(l.themeDark)),
            ],
            selected: {s.theme},
            onSelectionChanged: (v) =>
                notifier.update((s) => s.copyWith(theme: v.single)),
          ),
        ),
      ],
    );
  }
}

class _Terminal extends ConsumerWidget {
  const _Terminal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    // Thousands apart with a thin space, as both languages accept: 10 000.
    String lines(int n) =>
        '$n'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: l.fontSize,
          control: DropdownButton<double>(
            style: fieldTextStyle(context),
            value: s.fontSize,
            items: [
              for (final size in {...Settings.fontSizes, s.fontSize})
                DropdownMenuItem(
                  value: size,
                  child: Text(l.pixels(size.round())),
                ),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(fontSize: v)),
          ),
        ),
        _Row(
          label: l.scrollback,
          help: l.scrollbackHelp,
          control: DropdownButton<int>(
            style: fieldTextStyle(context),
            value: s.scrollback,
            items: [
              for (final n in {...Settings.scrollbacks, s.scrollback})
                DropdownMenuItem(
                  value: n,
                  child: Text(l.scrollbackLines(lines(n))),
                ),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(scrollback: v)),
          ),
        ),
      ],
    );
  }
}
