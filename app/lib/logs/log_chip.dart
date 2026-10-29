// «Registro» on a pane whose session keeps a log: recording, paused or
// over; and from its menu, pausing, the log itself, and where it is
// turned on (docs/plan/registros.md).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/providers.dart';
import '../hosts/editors.dart' show showHostEditor;
import '../l10n/l10n.dart';
import '../settings/settings_page.dart' show SettingsSection, openSettings;
import '../sftp/format.dart' show formatSize;
import '../src/rust/api/vault.dart' show OriginKind;
import '../terminal/controller.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'log_viewer.dart';
import 'logs.dart';

/// The pane's log: a dot that is green while it records, «En pausa ·
/// m:ss» while paused, grey once the connection is over. Nothing if the
/// tab kept no recording.
class LogChip extends ConsumerStatefulWidget {
  const LogChip({super.key, required this.controller, this.onDone});

  final TerminalController controller;

  /// After its menu: the keyboard back to the terminal.
  final VoidCallback? onDone;

  @override
  ConsumerState<LogChip> createState() => _LogChipState();
}

class _LogChipState extends ConsumerState<LogChip> {
  /// Counts the pause up while there is one.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ticking(bool paused) {
    if (paused) {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller;
    final id = s.logId;
    final log = s.log;
    final live = log != null && log.recording && log.failed == null;
    final paused = live && log.paused;
    _ticking(paused);
    if (id == null) return const SizedBox.shrink();
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final since = s.logPausedAt;
    final text = paused
        ? l.logPausedFor(
            clockText(
              since == null
                  ? 0
                  : DateTime.now().difference(since).inSeconds.toDouble(),
            ),
          )
        : l.logTab;
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('log.chip'),
      tooltip: switch (log?.failed) {
        final why? => l.logFailed(why),
        _ => live ? l.logRecordingTooltip : l.logEndedTooltip,
      },
      position: PopupMenuPosition.under,
      onSelected: (f) {
        f();
        widget.onDone?.call();
      },
      onCanceled: widget.onDone,
      itemBuilder: (context) => _items(context, id, live: live, paused: paused),
      // 28: the least a control in a line of text takes.
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: OwSpace.s4),
        decoration: BoxDecoration(
          color: paused ? c.warnSoft : c.surface,
          border: Border.all(color: paused ? c.warnLine : c.control),
          borderRadius: BorderRadius.circular(ow.shape.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paused ? Icons.pause : Icons.subject,
              size: 13,
              color: paused ? c.warn : c.textMuted,
            ),
            const SizedBox(width: OwSpace.s2),
            Text(
              text,
              style: TextStyle(
                fontSize: OwText.small,
                color: paused ? c.warn : c.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!paused) ...[
              const SizedBox(width: OwSpace.s3),
              StatusDot(
                log?.failed != null
                    ? Status.failed
                    : live
                    ? Status.connected
                    : Status.idle,
                size: 7,
              ),
            ],
          ],
        ),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _item(
    String key,
    IconData icon,
    String title,
    VoidCallback f, {
    String? help,
    Color? iconColor,
  }) {
    final c = context.ow.colors;
    return PopupMenuItem(
      key: ValueKey(key),
      value: f,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: OwSpace.s1),
            child: Icon(icon, size: 16, color: iconColor ?? c.textMuted),
          ),
          const SizedBox(width: OwSpace.s5),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (help != null)
                  Text(
                    help,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<VoidCallback>> _items(
    BuildContext context,
    String id, {
    required bool live,
    required bool paused,
  }) {
    final l = context.l10n;
    final c = context.ow.colors;
    final s = widget.controller;
    final entry = ref.read(openWardProvider).log(id: id);
    final String title;
    final String sub;
    if (!live) {
      title = l.logMenuEnded;
      sub = entry == null ? '' : timeRange(l, entry);
    } else if (paused) {
      title = l.logMenuPaused;
      sub = l.logMenuPausedSub;
    } else {
      title = l.logMenuTitle;
      sub = [
        if (entry != null)
          l.logMenuSince(DateFormat.Hm(l.localeName).format(started(entry))),
        if (entry != null && entry.bytes > BigInt.zero)
          formatSize(l, entry.bytes.toInt()),
        l.logMenuNeverTyped,
      ].join(' · ');
    }
    final hostId = s.hostId;
    final stop = live && hostId != null ? _stopItem(hostId) : null;
    return [
      PopupMenuItem(
        enabled: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: TextStyle(fontSize: OwText.small, color: c.textMuted),
              ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      if (live)
        paused
            ? _item(
                'log.resume',
                Icons.fiber_manual_record,
                l.logResume,
                () => s.pauseLog(false),
                help: l.logResumeHelp,
                iconColor: c.accent,
              )
            : _item(
                'log.pause',
                Icons.pause,
                l.logPause,
                () => s.pauseLog(true),
                help: l.logPauseHelp,
                iconColor: c.warn,
              ),
      if (entry != null && entry.recorded)
        _item(
          'log.openThis',
          Icons.subject,
          l.logOpenThis,
          () => openLogById(context, ref, id),
        ),
      const PopupMenuDivider(),
      ?stop,
      _item(
        'log.settings',
        Icons.settings_outlined,
        l.logsSettingsEllipsis,
        () => openSettings(ref, SettingsSection.logs),
      ),
    ];
  }

  /// «No guardar registros de web-1…», with where it is turned on: the
  /// host's editor, or Ajustes when it is on every host.
  PopupMenuItem<VoidCallback>? _stopItem(String hostId) {
    final l = context.l10n;
    final library = ref.read(libraryProvider);
    final host = library.host(hostId);
    if (host == null) return null;
    final origin = ref
        .read(openWardProvider)
        .host(id: hostId)
        .origins
        .where((o) => o.field == 'session_log')
        .firstOrNull;
    final everywhere = origin?.origin == OriginKind.default_;
    return _item(
      'log.stopHost',
      Icons.edit_outlined,
      l.logStopHost(host.label),
      () => everywhere
          ? openSettings(ref, SettingsSection.logs)
          : showHostEditor(context, ref, id: hostId, field: 'session_log'),
      help: switch (origin?.origin) {
        OriginKind.group => l.logStopFromGroup(
          library.group(origin!.groupId ?? '')?.name ?? '',
        ),
        OriginKind.default_ => l.logStopEverywhere,
        _ => l.logStopOwn,
      },
    );
  }
}
