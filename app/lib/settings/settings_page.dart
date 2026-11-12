import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../core/version.dart';
import '../history/history.dart';
import '../home/recent.dart';
import '../hosts/editors.dart' show showGroupEditor, showHostEditor;
import '../keys/key_actions.dart' show revealLabel;
import '../l10n/l10n.dart';
import '../logs/logs.dart';
import '../sftp/format.dart' show formatSize;
import '../src/rust/api/app.dart';
import '../src/rust/api/logs.dart' show LogSetIn;
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/confirm.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/umbral.dart';
import '../ui/widgets.dart';
import '../welcome/whats_new.dart';
import 'appearance_page.dart';
import '../security/settings.dart';
import 'highlight_rules.dart';
import 'report.dart';
import '../window/shortcuts.dart';
import '../window/sidebar_state.dart';

enum SettingsSection { general, appearance, terminal, logs, security }

class SettingsSectionNotifier extends Notifier<SettingsSection> {
  @override
  SettingsSection build() => SettingsSection.general;

  void show(SettingsSection section) => state = section;
}

/// The section Ajustes shows: the last one chosen, or the one asked for.
final settingsSectionProvider =
    NotifierProvider<SettingsSectionNotifier, SettingsSection>(
      SettingsSectionNotifier.new,
    );

/// Opens Ajustes, at `section` if one is given.
void openSettings(WidgetRef ref, [SettingsSection? section]) {
  if (section != null) {
    ref.read(settingsSectionProvider.notifier).show(section);
  }
  ref.read(tabsProvider.notifier).openPage(PageKind.settings);
}

/// Settings, in a tab of their own. They take effect as they change;
/// there is nothing to save.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final section = ref.watch(settingsSectionProvider);
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s12,
              OwSpace.s5,
              OwSpace.s12,
              0,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                for (final s in SettingsSection.values)
                  _NavItem(
                    key: ValueKey('settings.section.${s.name}'),
                    text: switch (s) {
                      SettingsSection.general => l.settingsGeneral,
                      SettingsSection.appearance => l.settingsAppearance,
                      SettingsSection.terminal => l.settingsTerminal,
                      SettingsSection.logs => l.settingsLogs,
                      SettingsSection.security => l.vaultSecurity,
                    },
                    selected: s == section,
                    onTap: () =>
                        ref.read(settingsSectionProvider.notifier).show(s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                OwSpace.s12,
                OwSpace.s10,
                OwSpace.s12,
                OwSpace.s12,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: section == SettingsSection.appearance
                        ? 1100
                        : 680,
                  ),
                  child: switch (section) {
                    SettingsSection.general => const _General(),
                    SettingsSection.appearance => const AppearanceSection(),
                    SettingsSection.terminal => const _Terminal(),
                    SettingsSection.logs => const _Logs(),
                    SettingsSection.security => const VaultSettings(),
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
    super.key,
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
          padding: const EdgeInsets.symmetric(
            horizontal: OwSpace.s5,
            vertical: OwSpace.s4,
          ),
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
        padding: const EdgeInsets.symmetric(vertical: OwSpace.s5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  if (help != null)
                    Padding(
                      padding: const EdgeInsets.only(top: OwSpace.s1),
                      child: Text(
                        help!,
                        style: TextStyle(
                          fontSize: OwText.small,
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
            control: DropdownButton<OptionAltChoice>(
              key: const ValueKey('settings.optionAsAlt'),
              value: s.optionAsAlt,
              underline: const SizedBox.shrink(),
              items: [
                for (final (v, text) in [
                  (OptionAltChoice.off, l.optionAltOff),
                  (OptionAltChoice.both, l.optionAltBoth),
                  (OptionAltChoice.left, l.optionAltLeft),
                  (OptionAltChoice.right, l.optionAltRight),
                ])
                  DropdownMenuItem(value: v, child: Text(text)),
              ],
              onChanged: (v) => notifier.update(
                (s) => s.copyWith(optionAsAlt: v ?? OptionAltChoice.off),
              ),
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
          padding: const EdgeInsets.fromLTRB(
            OwSpace.s7,
            OwSpace.s5,
            OwSpace.s4,
            OwSpace.s5,
          ),
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
                      style: TextStyle(
                        fontSize: OwText.small,
                        color: c.textSubtle,
                      ),
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
                    padding: EdgeInsets.all(OwSpace.s4),
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
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s7,
              OwSpace.s5,
              OwSpace.s7,
              OwSpace.s5,
            ),
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
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
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
          label: l.autocomplete,
          help: s.commandHistory
              ? l.autocompleteHelp
              : l.autocompleteNeedsHistory,
          control: Switch(
            key: const ValueKey('settings.autocomplete'),
            value: s.autocomplete && s.commandHistory,
            onChanged: s.commandHistory
                ? (v) => notifier.update((s) => s.copyWith(autocomplete: v))
                : null,
          ),
        ),
        SectionLabel(l.settingsMouse),
        _Row(
          label: l.copyOnSelect,
          help: l.copyOnSelectHelp,
          control: Switch(
            key: const ValueKey('settings.copyOnSelect'),
            value: s.copyOnSelect,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(copyOnSelect: v)),
          ),
        ),
        _Row(
          label: l.rightClickPaste,
          help: l.rightClickPasteHelp,
          control: Switch(
            key: const ValueKey('settings.rightClickPaste'),
            value: s.rightClickPaste,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(rightClickPaste: v)),
          ),
        ),
        SectionLabel(l.settingsHighlight),
        _Row(
          label: l.highlightOn,
          help: l.highlightOnHelp,
          control: Switch(
            key: const ValueKey('settings.highlight'),
            value: s.highlight,
            onChanged: (v) => notifier.update((s) => s.copyWith(highlight: v)),
          ),
        ),
        const HighlightRules(),
        SectionLabel(l.settingsShortcuts),
        _Row(
          label: l.shortcutProfile,
          help: l.shortcutProfileHelp,
          control: SegmentedButton<ShortcutProfile>(
            key: const ValueKey('settings.shortcutProfile'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ShortcutProfile.system,
                label: Text(l.shortcutProfileSystem),
              ),
              ButtonSegment(
                value: ShortcutProfile.mac,
                label: Text(l.shortcutProfileMac),
              ),
              ButtonSegment(
                value: ShortcutProfile.pc,
                label: Text(l.shortcutProfilePc),
              ),
            ],
            selected: {s.shortcutProfile},
            onSelectionChanged: (v) =>
                notifier.update((s) => s.copyWith(shortcutProfile: v.single)),
          ),
        ),
        // With ⌘ there is nothing to give: no program hears ⌘.
        if (!s.macShortcuts)
          _Row(
            label: l.terminalKeysFirst,
            help: l.terminalKeysFirstHelp,
            control: Switch(
              key: const ValueKey('settings.terminalKeysFirst'),
              value: s.terminalKeysFirst,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(terminalKeysFirst: v)),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          l.terminalShortcuts(macShortcuts ? '⌘' : l.ctrlShiftPrefix),
          style: TextStyle(
            fontSize: OwText.small,
            color: context.ow.colors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Ajustes › Registros: where the session log is on, what this device
/// records and keeps, and the rest this device keeps of what is done
/// (the command history, the recent connections).
class _Logs extends ConsumerWidget {
  const _Logs();

  static const _days = [7, 30, 90, 365, 0];
  static const _gib = 1024 * 1024 * 1024;
  static const _spaces = [_gib ~/ 2, _gib, 2 * _gib, 5 * _gib, 10 * _gib, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final config = ref.watch(logsConfigProvider);
    // The space used changes with the entries; where it is on, with the
    // library.
    ref.watch(logsProvider);
    final library = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);
    final recent = ref.watch(recentProvider.select((r) => r.connections));
    final app = ref.read(openWardProvider);
    final usage = app.logsUsage();
    final l = context.l10n;
    final c = context.ow.colors;
    final logs = ref.read(logsConfigProvider.notifier);
    final maxBytes = config.maxBytes.toInt();
    final used = usage.bytes.toInt();
    // Where a group or a host says otherwise than «everywhere».
    final others = [
      for (final p in app.logsSetIn())
        if (p.enabled != s.sessionLog) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l.logsSessionTitle),
        _Row(
          label: l.logsEverywhere,
          help: l.logsEverywhereHelp,
          control: Switch(
            key: const ValueKey('settings.logEverywhere'),
            value: s.sessionLog,
            onChanged: (v) => notifier.update((s) => s.copyWith(sessionLog: v)),
          ),
        ),
        _SetIn(places: others, everywhere: s.sessionLog, library: library),
        const Divider(height: OwSpace.s10),
        _Row(
          label: l.logsLocalTerminals,
          help: l.logsLocalHelp,
          control: Switch(
            key: const ValueKey('settings.logLocal'),
            value: config.recordLocal,
            onChanged: (v) => logs.set(recordLocal: v),
          ),
        ),
        _Row(
          label: l.logsKeep,
          help: l.logsKeepHelp,
          control: DropdownButton<int>(
            key: const ValueKey('settings.logDays'),
            style: fieldTextStyle(context),
            value: config.keepDays,
            items: [
              for (final d in {..._days, config.keepDays})
                DropdownMenuItem(
                  value: d,
                  child: Text(d == 0 ? l.logsKeepAlways : l.logsKeepDays(d)),
                ),
            ],
            onChanged: (v) => logs.set(keepDays: v),
          ),
        ),
        _Row(
          label: l.logsSpace,
          help: l.logsSpaceHelp,
          control: DropdownButton<int>(
            key: const ValueKey('settings.logSpace'),
            style: fieldTextStyle(context),
            value: maxBytes,
            items: [
              for (final b in {..._spaces, maxBytes})
                DropdownMenuItem(
                  value: b,
                  child: Text(b == 0 ? l.logsNoLimit : formatSize(l, b)),
                ),
            ],
            onChanged: (v) => logs.set(maxBytes: v),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: maxBytes == 0 ? 0 : (used / maxBytes).clamp(0.0, 1.0),
                minHeight: OwSpace.s2,
                borderRadius: BorderRadius.circular(context.ow.shape.round),
              ),
            ),
            const SizedBox(width: OwSpace.s6),
            Text(
              '${formatSize(l, used)} · ${l.logsCount(usage.entries)} · '
              '${l.logsSavedCount(usage.saved)}',
              key: const ValueKey('settings.logUsage'),
              style: monoStyle(context, size: 12, color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: OwSpace.s4),
        _Row(
          label: l.logsFolder,
          help: app.logsDir(),
          control: OutlinedButton.icon(
            key: const ValueKey('settings.logFolder'),
            onPressed: () => _revealFolder(app.logsDir()),
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(revealLabel(l)),
          ),
        ),
        Callout(
          tone: Tone.info,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 16, color: c.textMuted),
              const SizedBox(width: OwSpace.s5),
              Expanded(
                child: Text(
                  app.securityState().phase.name == 'legacy'
                      ? l.logsUnencrypted
                      : l.logsEncrypted,
                ),
              ),
            ],
          ),
        ),
        _Row(
          label: l.logsDeleteAll,
          help: l.logsDeleteAllHelp(
            l.logsCount(usage.entries),
            formatSize(l, used),
          ),
          control: OutlinedButton.icon(
            key: const ValueKey('settings.logDeleteAll'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.dangerLine),
            ),
            onPressed: () async {
              final sure = await confirmDestructive(
                context,
                title: l.logsDeleteAllTitle,
                body: l.logsDeleteAllHelp(
                  l.logsCount(usage.entries),
                  formatSize(l, used),
                ),
                action: l.logsDeleteAllAction,
                actionKey: const ValueKey('settings.logDeleteAll.confirm'),
              );
              if (!sure || !context.mounted) return;
              await runAction(context, () async {
                await app.deleteAllLogs();
              });
              ref.read(logsProvider.notifier).refresh();
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(l.logsDeleteAllEllipsis),
          ),
        ),
        const SizedBox(height: OwSpace.s12),
        SectionLabel(l.logsAlsoHere),
        _Row(
          label: l.commandHistory,
          help: l.commandHistoryHelp(keysFor('⌘K', '${l.ctrlShiftPrefix}K')),
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('settings.clearHistory'),
                onPressed: history.isEmpty
                    ? null
                    : () async {
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
      ],
    );
  }
}

/// Under «everywhere»: the groups and hosts that say otherwise, each a
/// way to its editor, and where it is changed.
class _SetIn extends ConsumerWidget {
  const _SetIn({
    required this.places,
    required this.everywhere,
    required this.library,
  });

  final List<LogSetIn> places;
  final bool everywhere;
  final Library library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final small = TextStyle(fontSize: OwText.small, color: c.textMuted);
    final chips = <Widget>[];
    for (final p in places) {
      final group = p.group ? library.group(p.id) : null;
      final host = p.group ? null : library.host(p.id);
      if (group == null && host == null) continue;
      chips.add(
        Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(ow.shape.radius),
          child: InkWell(
            key: ValueKey('settings.logSetIn.${p.id}'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => group != null
                ? showGroupEditor(context, ref, id: p.id, field: 'session_log')
                : showHostEditor(context, ref, id: p.id, field: 'session_log'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: OwSpace.s5,
                vertical: OwSpace.s3,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: c.control),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (group?.environment case final env?) ...[
                    EnvChip(env),
                    const SizedBox(width: OwSpace.s4),
                  ],
                  if (host != null) ...[
                    SystemBadge(
                      code: host.system?.code,
                      env: host.environment,
                      size: 18,
                    ),
                    const SizedBox(width: OwSpace.s4),
                  ],
                  Text(group?.name ?? host!.label),
                  const SizedBox(width: OwSpace.s4),
                  Text(
                    group != null
                        ? '${l.logsGroup} · ${l.hostCountText(library.countUnder(group.id))}'
                        : l.logsHost,
                    style: small,
                  ),
                  const SizedBox(width: OwSpace.s2),
                  Icon(Icons.chevron_right, size: 16, color: c.textSubtle),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(OwSpace.s6),
      decoration: BoxDecoration(
        color: c.sunken,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chips.isNotEmpty) ...[
            Text(everywhere ? l.logsExceptIn : l.logsOnlyIn, style: small),
            const SizedBox(height: OwSpace.s4),
            Wrap(spacing: OwSpace.s4, runSpacing: OwSpace.s4, children: chips),
            const SizedBox(height: OwSpace.s5),
          ],
          Text(
            chips.isEmpty
                ? '${everywhere ? l.logsNoneOff : l.logsNoneOn} ${l.logsWhereNote}'
                : l.logsWhereNote,
            style: small,
          ),
        ],
      ),
    );
  }
}

/// A folder in the system's file manager.
Future<void> _revealFolder(String dir) async {
  if (Platform.isMacOS) {
    await Process.run('open', [dir]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', [dir]);
  } else {
    await launchUrl(Uri.directory(dir));
  }
}
