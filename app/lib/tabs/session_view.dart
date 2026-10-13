import 'package:flutter/material.dart';

import '../terminal/controller.dart';
import '../terminal/terminal_pane.dart';
import 'messages.dart';
import 'prompt_card.dart';

/// The front tab: its terminal, any question it is waiting on, and a status
/// line with what the session is doing.
class SessionView extends StatelessWidget {
  const SessionView({super.key, required this.controller});

  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final prompt = controller.prompts.isEmpty
            ? null
            : controller.prompts.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TerminalPane(
                      // One pane per tab: its focus and input method stay
                      // with it.
                      key: ObjectKey(controller),
                      controller: controller,
                      autofocus: prompt == null,
                    ),
                  ),
                  if (prompt != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: PromptCard(
                            key: ObjectKey(prompt),
                            controller: controller,
                            prompt: prompt,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _StatusBar(controller: controller, theme: theme),
          ],
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.theme});

  final TerminalController controller;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final failed =
        c.phase == Phase.closed &&
        (c.closed?.failure != null || c.error != null);
    final connected = c.phase == Phase.connected;
    final pq = connected && c.connected!.postQuantum;
    final color = failed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        children: [
          Icon(
            switch (c.phase) {
              Phase.connecting => Icons.hourglass_empty,
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
          if (c.phase == Phase.closed)
            TextButton.icon(
              onPressed: c.start,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(c.isLocal ? 'Reiniciar' : 'Reconectar'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
