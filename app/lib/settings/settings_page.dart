import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings.dart';
import '../core/version.dart';
import '../history/history.dart';
import '../home/recent.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/app.dart';
import '../terminal/keys.dart';
import '../ui/confirm.dart';
import '../ui/tokens.dart';
import '../ui/umbral.dart';
import '../ui/widgets.dart';
import '../welcome/whats_new.dart';
import 'appearance_page.dart';
import 'report.dart';
import '../window/shortcuts.dart';
import '../window/sidebar_state.dart';

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
                  constraints: BoxConstraints(
                    maxWidth: _section == _Section.appearance ? 1100 : 680,
                  ),
                  child: switch (_section) {
                    _Section.general => const _General(),
                    _Section.appearance => const AppearanceSection(),
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
    // The switch or menu is named by the label and help next to it.
    return MergeSemantics(
      child: Padding(
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
      ),
    );
  }
}

class _General extends ConsumerWidget {
  const _General();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final recent = ref.watch(recentProvider.select((r) => r.connections));
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
        _Row(
          label: l.recentConnections,
          help: l.recentConnectionsHelp,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('settings.clearRecent'),
                onPressed: recent.isEmpty
                    ? null
                    : () async {
                        final l = context.l10n;
                        final sure = await confirmAction(
                          context,
                          title: l.clearRecentTitle,
                          body: l.clearRecentBody,
                          action: l.clearAction,
                          danger: true,
                        );
                        if (sure) ref.read(recentProvider.notifier).clear();
                      },
                child: Text(l.clearRecent(recent.length)),
              ),
              const SizedBox(width: 8),
              Switch(
                key: const ValueKey('settings.recentConnections'),
                value: s.recentConnections,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(recentConnections: v)),
              ),
            ],
          ),
        ),
        _Row(
          label: l.readOsReleaseEverywhere,
          help: l.readOsReleaseEverywhereHelp,
          control: Switch(
            key: const ValueKey('settings.readOsRelease'),
            value: s.readOsRelease,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(readOsRelease: v)),
          ),
        ),
        const SizedBox(height: 24),
        SectionLabel(l.settingsWindow),
        _Row(
          label: l.sidebarSetting,
          help: '${sidebarKeys(l)} · ${l.sidebarHelp}',
          control: SegmentedButton<SidebarMode>(
            key: const ValueKey('settings.sidebar'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SidebarMode.open,
                label: Text(l.sidebarOpen),
              ),
              ButtonSegment(
                value: SidebarMode.rail,
                label: Text(l.sidebarRail),
              ),
              ButtonSegment(
                value: SidebarMode.hidden,
                label: Text(l.sidebarHidden),
              ),
            ],
            selected: {s.sidebar},
            onSelectionChanged: (v) =>
                ref.read(sidebarProvider.notifier).chose(v.single),
          ),
        ),
        _Row(
          label: l.sidebarOnSession,
          help: l.sidebarOnSessionHelp,
          control: SegmentedButton<SidebarOnSession>(
            key: const ValueKey('settings.sidebarOnSession'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SidebarOnSession.keep,
                label: Text(l.onSessionKeep),
              ),
              ButtonSegment(
                value: SidebarOnSession.rail,
                label: Text(l.onSessionRail),
              ),
              ButtonSegment(
                value: SidebarOnSession.hide,
                label: Text(l.onSessionHide),
              ),
            ],
            selected: {s.sidebarOnSession},
            onSelectionChanged: (v) =>
                notifier.update((s) => s.copyWith(sidebarOnSession: v.single)),
          ),
        ),
        _Row(
          label: l.sidebarWidth,
          help: l.sidebarWidthHelp,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.pixels(s.sidebarWidth.round()),
                style: monoStyle(context, size: 12, color: c.text),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('settings.sidebarWidthReset'),
                onPressed: s.sidebarWidth == Settings.defaultSidebarWidth
                    ? null
                    : ref.read(sidebarProvider.notifier).resetWidth,
                child: Text(l.resetTheme),
              ),
            ],
          ),
        ),
        _Row(
          label: l.terminalPadding,
          help: l.terminalPaddingHelp,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: Slider(
                  key: const ValueKey('settings.terminalPadding'),
                  min: 0,
                  max: 24,
                  divisions: 12,
                  value: s.terminalPadding,
                  label: l.pixels(s.terminalPadding.round()),
                  onChanged: (v) =>
                      notifier.update((s) => s.copyWith(terminalPadding: v)),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  l.pixels(s.terminalPadding.round()),
                  style: monoStyle(context, size: 12, color: c.text),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionLabel(l.about),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: c.sunken,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(context.ow.shape.radiusLarge),
          ),
          child: Row(
            children: [
              const UmbralMark(size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OpenWard $appVersion',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${Platform.operatingSystem} · ${l.reportCore} ${coreVersion()}',
                      style: TextStyle(fontSize: 12, color: c.textSubtle),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('about.news'),
                onPressed: () => showWhatsNew(context, ref),
                child: Text(l.whatsNew),
              ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'OpenWard',
                  applicationVersion: appVersion,
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(8),
                    child: UmbralMark(size: 48),
                  ),
                ),
                child: Text(l.licenses),
              ),
            ],
          ),
        ),
        if (ref.read(openWardProvider).unreadableItems() case final n
            when n > 0) ...[
          const SizedBox(height: 10),
          Callout(
            key: const ValueKey('about.unreadable'),
            tone: Tone.info,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(l.unreadableItems(n)),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('about.report'),
              onPressed: () => showReport(context, ref),
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(l.reportProblemEllipsis),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.reportProblemHint,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Terminal extends ConsumerWidget {
  const _Terminal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
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
        _Row(
          label: l.bellFlash,
          help: l.bellFlashHelp,
          control: Switch(
            value: s.bellFlash,
            onChanged: (v) => notifier.update((s) => s.copyWith(bellFlash: v)),
          ),
        ),
        _Row(
          label: l.onExit,
          help: l.onExitHelp,
          control: SegmentedButton<OnExit>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: OnExit.clean, label: Text(l.onExitClean)),
              ButtonSegment(value: OnExit.always, label: Text(l.onExitAlways)),
              ButtonSegment(value: OnExit.never, label: Text(l.onExitNever)),
            ],
            selected: {s.onExit},
            onSelectionChanged: (v) =>
                notifier.update((s) => s.copyWith(onExit: v.single)),
          ),
        ),
        _Row(
          label: l.commandHistory,
          help: l.commandHistoryHelp(isApple ? '⌘K' : 'Ctrl+Shift+K'),
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('settings.clearHistory'),
                onPressed: history.isEmpty
                    ? null
                    : () async {
                        final l = context.l10n;
                        final sure = await confirmAction(
                          context,
                          title: l.clearHistoryTitle,
                          body: l.clearHistoryBody,
                          action: l.clearAction,
                          danger: true,
                        );
                        if (sure) ref.read(historyProvider.notifier).clear();
                      },
                child: Text(l.clearHistory(history.length)),
              ),
              const SizedBox(width: 8),
              Switch(
                key: const ValueKey('settings.commandHistory'),
                value: s.commandHistory,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(commandHistory: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l.terminalShortcuts(isApple ? '⌘' : l.ctrlShiftPrefix),
          style: TextStyle(fontSize: 12, color: context.ow.colors.textMuted),
        ),
      ],
    );
  }
}
