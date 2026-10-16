import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../core/version.dart';
import '../l10n/l10n.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The edition of the news [showWhatsNew] tells, seen once per person. A
/// new one shows them again to who saw an earlier one: 0.2.0-beta.2 added
/// the importers, 0.2.0-beta.3 dragging tabs and panes.
const newsVersion = '0.2.0-beta.3';

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
    String keys(String apple, String other) => isApple ? apple : other;
    // Marked new: what came after who saw the news before.
    final items = [
      (Icons.file_download_outlined, l.newsImportTitle, l.newsImportBody, true),
      (Icons.visibility_outlined, l.newsThemesTitle, l.newsThemesBody, false),
      (
        Icons.vertical_split_outlined,
        l.newsPanesTitle,
        l.newsPanesBody(
          keys('⌘D', 'Ctrl+Shift+D'),
          keys('⌘⇧B', 'Ctrl+Shift+B'),
        ),
        true,
      ),
      (
        Icons.folder_outlined,
        l.newsSftpTitle,
        l.newsSftpBody(keys('⌘⇧O', 'Ctrl+Shift+O')),
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
        l.newsSnippetsBody(keys('⌘⇧S', 'Ctrl+Shift+S')),
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
              Icon(Icons.auto_awesome, size: 16, color: c.accentText),
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
