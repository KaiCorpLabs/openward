import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../snippets/snippets.dart' show snippetTargets;
import '../terminal/send_target.dart';
import '../terminal/visible_text.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'history.dart';

/// Replays one immutable history entry to the terminals captured at selection.
/// A review never changes which shell or text will receive the decision.
Future<int> replayHistory(
  BuildContext context,
  ProviderContainer ref,
  HistoryEntry entry, {
  bool typeOnly = false,
}) async {
  final targets = [for (final c in snippetTargets(ref)) TerminalSendTarget(c)];
  if (targets.isEmpty || !targets.first.current) return 0;
  final text = entry.command;
  final here = targets.first.controller;
  final review =
      targets.length > 1 ||
      !historyIsOwnHere(entry, historyPlace(here), historyBinding(here)) ||
      hasHidden(text, lines: false);
  if (review &&
      !await reviewHistory(context, entry, targets, typeOnly: typeOnly)) {
    return 0;
  }
  if (!context.mounted) return 0;
  var sent = 0;
  for (final target in targets) {
    if (!target.current) continue;
    final private = target.controller.line.privateLine;
    final delivered = typeOnly
        ? target.paste(text, allowUnsafe: true)
        : target.execute(text);
    if (!delivered) continue;
    sent++;
    if (typeOnly) {
      target.controller.line.untrackedInput();
    } else {
      target.controller.line.reset();
      if (identical(target, targets.first) &&
          !private &&
          !text.startsWith(' ') &&
          ref.read(settingsProvider).commandHistory) {
        ref
            .read(historyProvider.notifier)
            .add(text, target.controller, origin: entry.origin);
      }
    }
  }
  if (targets.first.current) targets.first.controller.focusTerminal?.call();
  return sent;
}

Future<bool> reviewHistory(
  BuildContext context,
  HistoryEntry entry,
  List<TerminalSendTarget> targets, {
  required bool typeOnly,
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final l = context.l10n;
        final colors = context.ow.colors;
        return AlertDialog(
          title: Text(l.historyReviewTitle),
          scrollable: true,
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.historyReviewFrom(
                    visibleName(
                      entry.label.isEmpty ? entry.where : entry.label,
                    ),
                  ),
                ),
                Text(switch (entry.origin) {
                  CommandOrigin.own => l.historyOriginOwn,
                  CommandOrigin.screen => l.historyOriginScreen,
                  CommandOrigin.unknown => l.historyOriginUnknown,
                }),
                const SizedBox(height: 12),
                Text(l.historyReviewTo),
                for (final target in targets)
                  Text(visibleName(target.destination)),
                const SizedBox(height: 12),
                Text.rich(
                  visibleText(
                    textForReview(entry, typeOnly),
                    style: monoStyle(context, size: 12, color: colors.text),
                    mark: monoStyle(context, size: 12, color: colors.warn),
                    lines: false,
                  ),
                ),
                const SizedBox(height: 12),
                Text(typeOnly ? l.snippetTypeOnlyNote : l.snippetWithEnter),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('history.review.send'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.sendAction),
            ),
          ],
        );
      },
    ) ??
    false;

String textForReview(HistoryEntry entry, bool typeOnly) =>
    typeOnly ? entry.command : '${entry.command}\n';
