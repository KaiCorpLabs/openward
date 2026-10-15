import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings.dart';
import '../hosts/import_ssh_config.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../terminal/keys.dart';
import '../ui/themes.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/chrome.dart';

/// The guide on the first run, with nothing saved yet: bring the hosts of
/// `~/.ssh/config`, choose how the app looks, and the shortcuts to start.
/// Skipping it, or finishing, marks it done for good.
class FirstRun extends ConsumerStatefulWidget {
  const FirstRun({super.key});

  @override
  ConsumerState<FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends ConsumerState<FirstRun> {
  int _step = 0;
  List<ImportPreview>? _previews;
  List<String> _only = const [];
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(openWardProvider)
        .previewSshConfig(file: ref.read(sshConfigFileProvider))
        .then((p) => mounted ? setState(() => _previews = p) : null)
        .catchError((_) => mounted ? setState(() => _previews = []) : null);
  }

  void _done() {
    // The library first: the window shows hosts as soon as the guide goes.
    ref.read(libraryProvider.notifier).refresh();
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(welcomed: true));
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final report = await ref
          .read(openWardProvider)
          .importSshConfig(file: ref.read(sshConfigFileProvider), only: _only);
      if (mounted && report.warnings.isNotEmpty) {
        await showImportReport(context, report);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importFailed('$e'))),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final steps = [l.stepImport, l.stepAppearance, l.stepReady];
    return Scaffold(
      backgroundColor: c.window,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: topBarHeight,
            child: Row(
              children: [
                const Expanded(child: WindowDragArea()),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton(
                    onPressed: _done,
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    child: Text(l.skipGuide),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Stepper(steps: steps, current: _step),
                      const SizedBox(height: 20),
                      ...switch (_step) {
                        0 => _importStep(context, theme),
                        1 => _appearanceStep(context, theme),
                        _ => _readyStep(context, theme),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _importStep(BuildContext context, ThemeData theme) {
    final l = context.l10n;
    final c = context.ow.colors;
    final previews = _previews;
    final found = previews != null && previews.isNotEmpty;
    return [
      Semantics(
        header: true,
        child: Text(l.welcomeTitle, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: 8),
      if (previews == null)
        const LinearProgressIndicator()
      else
        Text(
          found
              ? '${l.importFound(previews.length)} ${l.importKeepsFile}'
              : l.welcomeNoConfig,
          style: TextStyle(color: c.textMuted, height: 1.5),
        ),
      if (found) ...[
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: ImportPicker(
            previews: previews,
            onChanged: (only) => setState(() => _only = only),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l.importIntoGroup,
          style: TextStyle(fontSize: 12, color: c.textSubtle),
        ),
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
              found ? l.importLater : '',
              style: TextStyle(fontSize: 12, color: c.textSubtle),
            ),
          ),
          if (found) ...[
            OutlinedButton(
              onPressed: () => setState(() => _step = 1),
              child: Text(l.notNow),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _only.isEmpty || _importing ? null : _import,
              child: Text(l.importN(_only.length)),
            ),
          ] else
            FilledButton(
              onPressed: previews == null
                  ? null
                  : () => setState(() => _step = 1),
              child: Text(l.next),
            ),
        ],
      ),
    ];
  }

  List<Widget> _appearanceStep(BuildContext context, ThemeData theme) {
    final l = context.l10n;
    final c = context.ow.colors;
    final choice = ref.watch(settingsProvider.select((s) => s.theme));
    void choose(ThemeChoice t) =>
        ref.read(settingsProvider.notifier).update((s) => s.copyWith(theme: t));
    return [
      Semantics(
        header: true,
        child: Text(
          l.appearanceStepTitle,
          style: theme.textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 8),
      Text(l.appearanceStepBody, style: TextStyle(color: c.textMuted)),
      const SizedBox(height: 18),
      Row(
        children: [
          for (final (t, name, themes) in [
            (
              ThemeChoice.system,
              l.themeSystem,
              [OwThemes.papel, OwThemes.grafito],
            ),
            (ThemeChoice.light, l.themeLight, [OwThemes.papel]),
            (ThemeChoice.dark, l.themeDark, [OwThemes.grafito]),
          ]) ...[
            if (t != ThemeChoice.system) const SizedBox(width: 12),
            Expanded(
              child: _ThemeCard(
                name: name,
                themes: themes,
                selected: choice == t,
                onTap: () => choose(t),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Spacer(),
          OutlinedButton(
            onPressed: () => setState(() => _step = 0),
            child: Text(l.back),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => setState(() => _step = 2),
            child: Text(l.next),
          ),
        ],
      ),
    ];
  }

  List<Widget> _readyStep(BuildContext context, ThemeData theme) {
    final l = context.l10n;
    final c = context.ow.colors;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    Widget shortcut(String keys, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Align(alignment: Alignment.centerLeft, child: KeyCap(keys)),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return [
      Semantics(
        header: true,
        child: Text(l.readyTitle, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: 8),
      Text(l.readyBody, style: TextStyle(color: c.textMuted)),
      const SizedBox(height: 16),
      shortcut('${key}T', l.shortcutLocal),
      shortcut('${key}K', l.shortcutSearch),
      shortcut('${key}N', l.shortcutNewHost),
      shortcut(isApple ? '⌘,' : 'Ctrl+,', l.shortcutSettings),
      const SizedBox(height: 24),
      Row(
        children: [
          const Spacer(),
          OutlinedButton(
            onPressed: () => setState(() => _step = 1),
            child: Text(l.back),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _done, child: Text(l.start)),
        ],
      ),
    ];
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < steps.length; i++)
          Semantics(
            selected: i == current,
            child: Container(
              height: 26,
              padding: const EdgeInsets.only(left: 4, right: 10),
              decoration: BoxDecoration(
                color: i == current ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == current ? c.accent : null,
                      border: i == current
                          ? null
                          : Border.all(color: c.control),
                    ),
                    child: i < current
                        ? Icon(Icons.check, size: 12, color: c.accent)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: i == current ? c.onPrimary : c.textMuted,
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: i == current ? c.accentText : c.textMuted,
                      fontWeight: i == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A choice of look, with a small picture of the window in it.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.themes,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final List<OwTheme> themes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            border: Border.all(
              color: selected ? c.accent : c.control,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 72,
                child: Row(
                  children: [
                    for (final t in themes)
                      Expanded(child: _MiniWindow(theme: t)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniWindow extends StatelessWidget {
  const _MiniWindow({required this.theme});

  final OwTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = theme.colors;
    final t = theme.terminal;
    Widget line(Color color, double width) => FractionallySizedBox(
      widthFactor: width,
      child: Container(height: 3, color: color),
    );
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: c.window,
          border: Border.all(color: c.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 22),
            Expanded(
              child: Container(
                margin: theme.shape.insetTerminal
                    ? const EdgeInsets.all(5)
                    : EdgeInsets.zero,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(
                    theme.shape.insetTerminal ? 4 : 0,
                  ),
                  border: theme.shape.insetTerminal
                      ? Border.all(color: c.border)
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(c.accent, 0.6),
                    const SizedBox(height: 4),
                    line(t.foreground, 0.85),
                    const SizedBox(height: 4),
                    line(c.info, 0.45),
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
