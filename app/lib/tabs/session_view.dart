import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../terminal/terminal_pane.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'connection_panels.dart';
import 'find_bar.dart';
import 'messages.dart';
import 'prompt_card.dart';

/// The front tab: its terminal, whatever the connection needs to say over
/// it (a question, progress, a failure, a reconnection), and a status line.
class SessionView extends ConsumerWidget {
  const SessionView({super.key, required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final prompt = c.prompts.isEmpty ? null : c.prompts.first;
        final failed = c.phase == Phase.closed && c.closed?.failure != null;
        // Over a terminal that has nothing to show yet.
        final Widget? card = prompt != null
            ? PromptCard(key: ObjectKey(prompt), controller: c, prompt: prompt)
            : c.everConnected
            ? null
            : c.phase == Phase.connecting && !c.isLocal
            ? ConnectingCard(controller: c)
            : failed
            ? FailureCard(controller: c)
            : null;
        Widget terminal = Stack(
          children: [
            Positioned.fill(
              child: TerminalPane(
                // One pane per tab: its focus and input method stay with it.
                key: ObjectKey(c),
                controller: c,
                autofocus: card == null && !c.findOpen,
              ),
            ),
            Positioned.fill(child: BellFlash(controller: c)),
            if (c.findOpen && card == null)
              Positioned(top: 8, right: 12, child: FindBar(controller: c)),
            if (card != null)
              Positioned.fill(
                child: ColoredBox(
                  color: ow.colors.scrim,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: card,
                    ),
                  ),
                ),
              ),
          ],
        );
        if (ow.shape.insetTerminal) {
          // A card on the page, with room around the text.
          terminal = Container(
            margin: const EdgeInsets.fromLTRB(4, 6, 12, 0),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: ow.terminal.background,
              borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
              border: Border.all(color: ow.colors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14281E0A),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: terminal,
          );
        }
        return ColoredBox(
          color: ow.shape.insetTerminal ? ow.colors.window : ow.colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.phase == Phase.reconnecting && prompt == null)
                ReconnectBanner(controller: c),
              Expanded(child: terminal),
              _StatusBar(controller: c),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = controller;
    final failure = s.closed?.failure;
    final failed =
        s.phase == Phase.closed && (failure != null || s.error != null);
    final k = s.phase == Phase.connected ? s.connected : null;
    final pq = k?.postQuantum ?? false;
    final color = failed ? c.danger : c.textMuted;
    final small = TextStyle(fontSize: 12, color: color);
    final Widget line;
    if (k != null) {
      final via = viaText(l, s);
      line = Row(
        children: [
          Icon(
            pq ? Icons.verified_user_outlined : Icons.lock_outline,
            size: 14,
            color: pq ? c.accent : c.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            l.statusConnected,
            style: TextStyle(
              fontSize: 12,
              color: c.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (pq) ...[const SizedBox(width: 8), Pill(l.postQuantum)],
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              [k.kex, k.cipher, ?via].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11),
            ),
          ),
        ],
      );
    } else {
      line = Row(
        children: [
          Icon(
            switch (s.phase) {
              Phase.connecting => Icons.hourglass_empty,
              Phase.reconnecting => Icons.sync,
              Phase.connected => Icons.lock_outline,
              Phase.running => Icons.computer,
              Phase.closed => failed ? Icons.error_outline : Icons.link_off,
            },
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText(l, s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
          ),
        ],
      );
    }
    final inset = ow.shape.insetTerminal;
    return Container(
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: inset ? 16 : 12),
      decoration: BoxDecoration(
        color: inset ? c.window : c.sunken,
        border: inset ? null : Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: k != null
                ? Tooltip(
                    message: l.connectionDetails,
                    child: InkWell(
                      onTap: () => showConnectionInfo(context, s),
                      child: line,
                    ),
                  )
                : line,
          ),
          if (failure?.kind == FailureKind.hostKeyChanged)
            TextButton(
              onPressed: () => showHostKeyChanged(context, ref, s),
              child: Text(l.reviewKey),
            ),
          if (s.phase == Phase.closed)
            TextButton.icon(
              onPressed: s.start,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(s.isLocal ? l.restart : l.reconnect),
            ),
        ],
      ),
    );
  }
}
