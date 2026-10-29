// The status line under a session tab: the active pane's connection, its
// round trip, and what can be done from there.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';

import '../l10n/l10n.dart';
import '../logs/log_chip.dart';
import '../src/rust/api/session.dart';
import '../terminal/controller.dart';
import '../snippets/palette.dart';
import '../tunnels/tunnels_page.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/shortcuts.dart';
import 'connection_motion.dart';
import 'connection_panels.dart';
import 'latency.dart';
import 'messages.dart';
import 'tabs.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key, required this.controller, this.panes});

  final TerminalController controller;
  final Panes? panes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = controller;
    final failure = s.closed?.failure;
    final failed =
        s.phase == Phase.closed && (failure != null || s.error != null);
    final stalled = s.stalledSince != null && s.phase == Phase.connected;
    final k = s.phase == Phase.connected && !stalled ? s.connected : null;
    final pq = k?.postQuantum ?? false;
    final color = failed ? c.danger : c.textMuted;
    final small = TextStyle(fontSize: OwText.small, color: color);
    final Widget line;
    if (k != null) {
      // The algorithms and the route are in the latency's card and in the
      // connection's details: here, how it is doing.
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
              fontSize: OwText.small,
              color: c.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (pq) ...[const SizedBox(width: 8), Pill(l.postQuantum)],
          if (s.persistent case final p?) tmuxPill(context, p),
          const SizedBox(width: 6),
          LatencyChip(controller: s),
          if (via != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: OwSpace.s2),
                child: Text(
                  via,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: OwText.small, color: c.textMuted),
                ),
              ),
            ),
        ],
      );
    } else {
      line = Row(
        children: [
          Icon(
            stalled
                ? Icons.wifi_tethering_error
                : switch (s.phase) {
                    Phase.connecting => Icons.hourglass_empty,
                    Phase.reconnecting => Icons.sync,
                    Phase.connected => Icons.lock_outline,
                    Phase.running => Icons.computer,
                    Phase.closed =>
                      failed ? Icons.error_outline : Icons.link_off,
                  },
            size: 14,
            color: stalled ? c.warn : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stalled ? l.statusStalled : statusText(l, s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: stalled ? small.copyWith(color: c.warn) : small,
            ),
          ),
        ],
      );
    }
    final inset = ow.shape.insetTerminal;
    return LayoutBuilder(
      // Narrow (a small window, a pane of a split), the actions as icons:
      // their names stay in the tooltips, nothing is cut without a word.
      builder: (context, box) {
        final narrow = box.maxWidth < 640;
        return Container(
          height: heightForText(context, 30),
          padding: EdgeInsets.symmetric(
            horizontal: inset ? OwSpace.s8 : OwSpace.s6,
          ),
          decoration: BoxDecoration(
            color: inset ? c.window : c.sunken,
            border: inset ? null : Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              if (panes?.broadcast ?? false)
                Padding(
                  padding: const EdgeInsets.only(right: OwSpace.s6),
                  child: Text(
                    l.broadcastStatus(panes!.receiving),
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.warn,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // Connected, the line opens the connection's details.
              Expanded(
                child: k != null
                    ? InkWell(
                        onTap: () => showConnectionInfo(context, s),
                        child: line,
                      )
                    : line,
              ),
              if (failure?.kind == FailureKind.hostKeyChanged)
                TextButton(
                  onPressed: () => showHostKeyChanged(context, ref, s),
                  child: Text(l.reviewKey),
                )
              else if ((failed ? failure ?? s.errorCause : null) case final e?)
                DetailsButton(e),
              if (k != null && s.hostId != null)
                TunnelChip(hostId: s.hostId!, hostLabel: s.label),
              // Split, each pane says it in its header.
              if (!(panes?.isSplit ?? false) && s.logId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OwSpace.s3),
                  child: LogChip(
                    controller: s,
                    onDone: () => s.focusTerminal?.call(),
                  ),
                ),
              if (s.phase == Phase.connected || s.phase == Phase.running)
                _StatusAction(
                  key: const ValueKey('status.snippets'),
                  narrow: narrow,
                  icon: Icons.text_snippet_outlined,
                  label: l.snippets,
                  keys: keysFor('⌘⇧S', '${l.ctrlShiftPrefix}S'),
                  onPressed: () => showSnippetPalette(context),
                ),
              if (k != null)
                _StatusAction(
                  key: const ValueKey('status.sftp'),
                  narrow: narrow,
                  icon: Icons.folder_outlined,
                  label: l.openSftp,
                  keys: keysFor('⌘⇧O', '${l.ctrlShiftPrefix}O'),
                  onPressed: () => ref
                      .read(tabsProvider.notifier)
                      .openSftp(
                        hostId: s.hostId,
                        target: s.target,
                        label: s.label,
                      ),
                ),
              if (s.phase == Phase.closed)
                _StatusAction(
                  narrow: narrow,
                  icon: Icons.refresh,
                  label: s.isLocal ? l.restart : l.reconnect,
                  onPressed: s.start,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// An action of the status bar: its icon and name, with its shortcut;
/// only the icon when narrow, the rest in its tooltip.
class _StatusAction extends StatelessWidget {
  const _StatusAction({
    super.key,
    required this.narrow,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.keys,
  });

  final bool narrow;
  final IconData icon;
  final String label;
  final String? keys;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    if (narrow) {
      return IconButton(
        tooltip: keys == null ? label : '$label  $keys',
        onPressed: onPressed,
        iconSize: 14,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: c.textMuted),
      );
    }
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: c.textMuted),
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: keys == null ? Text(label) : _Keyed(label, keys!),
    );
  }
}

/// An action's name and its shortcut, the shortcut quieter.
class _Keyed extends StatelessWidget {
  const _Keyed(this.text, this.keys);

  final String text;
  final String keys;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$text '),
        TextSpan(
          text: keys,
          style: monoStyle(
            context,
            size: 12,
            color: context.ow.colors.textSubtle,
          ),
        ),
      ],
    ),
    style: const TextStyle(fontSize: OwText.small),
  );
}

/// Shows [child] once [delay] has passed since it was first built.
class Delayed extends StatefulWidget {
  const Delayed({super.key, required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<Delayed> {
  Timer? _timer;
  late bool _shown = widget.delay == Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!_shown) {
      _timer = Timer(widget.delay, () => setState(() => _shown = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _shown ? widget.child : const SizedBox.shrink();
}
