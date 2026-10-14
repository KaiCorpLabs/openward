import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../terminal/terminal_pane.dart';
import 'connection_panels.dart';
import 'messages.dart';
import 'prompt_card.dart';

/// The front tab: its terminal, whatever the connection needs to say over
/// it (a question, progress, a failure, a reconnection), and a status line.
class SessionView extends ConsumerWidget {
  const SessionView({super.key, required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.phase == Phase.reconnecting && prompt == null)
              ReconnectBanner(controller: c),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TerminalPane(
                      // One pane per tab: its focus and input method stay
                      // with it.
                      key: ObjectKey(c),
                      controller: c,
                      autofocus: card == null,
                    ),
                  ),
                  if (card != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Center(child: card),
                      ),
                    ),
                ],
              ),
            ),
            _StatusBar(controller: c, theme: theme, ref: ref),
          ],
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.controller,
    required this.theme,
    required this.ref,
  });

  final TerminalController controller;
  final ThemeData theme;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final failure = c.closed?.failure;
    final failed =
        c.phase == Phase.closed && (failure != null || c.error != null);
    final connected = c.phase == Phase.connected;
    final pq = connected && c.connected!.postQuantum;
    final color = failed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final compact = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      textStyle: theme.textTheme.bodySmall,
    );
    final line = Row(
      children: [
        Icon(
          switch (c.phase) {
            Phase.connecting => Icons.hourglass_empty,
            Phase.reconnecting => Icons.sync,
            Phase.connected => pq ? Icons.verified_user : Icons.lock,
            Phase.running => Icons.computer,
            Phase.closed => failed ? Icons.error_outline : Icons.link_off,
          },
          size: 14,
          color: pq ? theme.colorScheme.primary : color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            statusText(c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: connected
                ? Tooltip(
                    message: 'Detalles de la conexión',
                    child: InkWell(
                      onTap: () => showConnectionInfo(context, c),
                      child: line,
                    ),
                  )
                : line,
          ),
          if (failure?.kind == FailureKind.hostKeyChanged)
            TextButton(
              onPressed: () => showHostKeyChanged(context, ref, c),
              style: compact,
              child: const Text('Revisar la clave…'),
            ),
          if (c.phase == Phase.closed)
            TextButton.icon(
              onPressed: c.start,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(c.isLocal ? 'Reiniciar' : 'Reconectar'),
              style: compact,
            ),
        ],
      ),
    );
  }
}
