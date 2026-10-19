import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../core/version.dart';
import '../l10n/l10n.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/umbral.dart';
import '../ui/widgets.dart';
import '../window/shortcuts.dart';

/// The edition of the news [showWhatsNew] tells, seen once per person. A
/// new one shows them again to who saw an earlier one: 0.2.0-beta.2 added
/// the importers, 0.2.0-beta.3 dragging tabs and panes, 0.3.0-beta.1 the
/// palette and history, workspaces, keys and CSV files, 0.3.0-beta.2 the
/// connection that notices a server gone and the persistent session,
/// 0.3.0-beta.3 the sidebar that folds, ⌘K for everything and the latency
/// in sight, 0.3.0-beta.4 the lighter editor, the start page, the
/// shortcuts sheet and each hop's latency, 0.3.1-beta.1 the environment,
/// the system and the favorites, 0.3.1-beta.2 panes that are handled
/// without guessing, 0.3.1-beta.4 the hosts on their page and the sidebar
/// for every day, 0.3.1-beta.5 seven more theme families, 0.3.1-beta.6 the
/// new logo.
const newsVersion = '0.3.1-beta.6';

/// Who updated and has not seen this release's news yet.
bool shouldShowNews(Settings s) => s.welcomed && s.seenNews != newsVersion;

/// What this release brings, in one dialog. Marks it seen.
Future<void> showWhatsNew(BuildContext context, WidgetRef ref) async {
  ref
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(seenNews: newsVersion));
  await showDialog<void>(context: context, builder: (_) => const _WhatsNew());
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew();

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final cs = l.ctrlShiftPrefix;
    String keys(String apple, String other) => isApple ? apple : other;
    // Marked new: what came after who saw the news before.
    final items = [
      (Icons.auto_awesome, l.newsLogoTitle, l.newsLogoBody, true),
      (
        Icons.palette_outlined,
        l.newsMoreThemesTitle,
        l.newsMoreThemesBody,
        false,
      ),
      (
        Icons.dns_outlined,
        l.newsSidebarTitle,
        l.newsSidebarBody(hostsKeys(l)),
        false,
      ),
      (
        Icons.vertical_split_outlined,
        l.newsPanesTitle2,
        l.newsPanesBody2(keys('⌘⌥=', l.paneOptions)),
        false,
      ),
      (Icons.label_important_outline, l.newsEnvTitle, l.newsEnvBody, false),
      (Icons.dns_outlined, l.newsSystemTitle, l.newsSystemBody, false),
      (
        Icons.star_outline_rounded,
        l.newsFavoritesTitle,
        l.newsFavoritesBody,
        false,
      ),
      (Icons.edit_note, l.newsEditorTitle, l.newsEditorBody, false),
      (Icons.home_outlined, l.newsStartTitle, l.newsStartBody, false),
      (
        Icons.keyboard_outlined,
        l.newsShortcutsTitle,
        l.newsShortcutsBody(keys('⌘/', '$cs/')),
        false,
      ),
      (Icons.route_outlined, l.newsHopsTitle, l.newsHopsBody, false),
      (
        Icons.view_sidebar_outlined,
        l.newsFocusTitle,
        l.newsFocusBody(sidebarKeys(l)),
        false,
      ),
      (
        Icons.keyboard_command_key,
        l.newsSearchTitle,
        l.newsSearchBody(keys('⌘K', '${cs}K')),
        false,
      ),
      (Icons.network_ping, l.newsLatencyTitle, l.newsLatencyBody, false),
      (
        Icons.wifi_tethering,
        l.newsConnectionTitle,
        l.newsConnectionBody,
        false,
      ),
      (
        Icons.history,
        l.newsPaletteTitle,
        l.newsPaletteBody(keys('⌘K', '${cs}K')),
        false,
      ),
      (
        Icons.dashboard_outlined,
        l.newsWorkspacesTitle,
        l.newsWorkspacesBody,
        false,
      ),
      (Icons.key_outlined, l.newsKeysTitle, l.newsKeysBody, false),
      (
        Icons.file_download_outlined,
        l.newsImportTitle,
        l.newsImportBody,
        false,
      ),
      (Icons.visibility_outlined, l.newsThemesTitle, l.newsThemesBody, false),
      (
        Icons.vertical_split_outlined,
        l.newsPanesTitle,
        l.newsPanesBody(keys('⌘D', '${cs}D'), keys('⌘⇧B', '${cs}B')),
        false,
      ),
      (
        Icons.folder_outlined,
        l.newsSftpTitle,
        l.newsSftpBody(keys('⌘⇧O', '${cs}O')),
        false,
      ),
      (Icons.swap_horiz, l.newsTunnelsTitle, l.newsTunnelsBody, false),
      (
        Icons.badge_outlined,
        l.newsIdentitiesTitle,
        l.newsIdentitiesBody,
        false,
      ),
      (
        Icons.terminal,
        l.newsSnippetsTitle,
        l.newsSnippetsBody(keys('⌘⇧S', '${cs}S')),
        false,
      ),
    ];
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const UmbralMark(size: 18),
              const SizedBox(width: 8),
              Text(
                'OpenWard $appVersion',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.accentText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(header: true, child: Text(l.whatsNew)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.whatsNewIntro, style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 8),
              for (final (icon, title, body, fresh) in items)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(ow.shape.radius),
                        ),
                        child: Icon(icon, size: 16, color: c.accentText),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (fresh) ...[
                                  const SizedBox(width: 8),
                                  Pill(l.newsFresh),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Text(
                  l.whatsNewReport,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('news.start'),
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(l.startAction),
        ),
      ],
    );
  }
}
