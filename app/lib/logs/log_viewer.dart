// A recording opened in a tab of its own, read only: its commands to jump
// to, the terminal as it was at any moment (found with ⌘F), a timeline to
// play it back, and saving it with a note, exporting it or connecting
// again. One recording at a time: opening another replaces it.

import '../core/save_file.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/address.dart';
import '../core/errors.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../home/start_page.dart' show durationText;
import '../l10n/l10n.dart';
import '../sftp/format.dart' show formatSize;
import '../src/rust/api/app.dart';
import '../src/rust/api/logs.dart';
import '../tabs/find_bar.dart';
import '../tabs/tabs.dart';
import '../terminal/controller.dart';
import '../terminal/keys.dart';
import '../terminal/terminal_pane.dart';
import '../ui/confirm.dart';
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'logs.dart';

/// A recording being watched, and where it is.
class LogViewer extends ChangeNotifier {
  LogViewer._(this.app, this.entry, this.player, this.terminal)
    : markers = player.markers(),
      duration = player.duration(),
      complete = player.complete();

  static Future<LogViewer> open(
    OpenWard app,
    LogEntry entry, {
    required int scrollback,
  }) async {
    final player = await app.openLog(id: entry.id, scrollback: scrollback);
    final terminal = TerminalController.playback(
      app: app,
      label: entry.label,
      session: player.session(),
    );
    return LogViewer._(app, entry, player, terminal);
  }

  final OpenWard app;
  final LogPlayer player;
  final TerminalController terminal;
  final List<LogMarker> markers;
  final double duration;

  /// False when it stops short (OpenWard closed suddenly).
  final bool complete;

  /// Its entry as last read (the note changes it).
  LogEntry entry;

  double position = 0;
  bool playing = false;
  double speed = 1;

  /// The command chosen in the list, while the position stays on it.
  int? _chosen;

  Timer? _tick;
  bool _disposed = false;

  late final List<LogMarker> commands = [
    for (final m in markers)
      if (m.kind == LogMarkerKind.command) m,
  ];

  /// The command on screen: the one chosen, or the last before here.
  int? get currentCommand {
    if (_chosen case final i?) return i;
    int? at;
    for (var i = 0; i < commands.length; i++) {
      if (commands[i].at <= position) at = i;
    }
    return at;
  }

  /// The moment just before the next command: the screen with what this
  /// one answered. The last one's goes on to the end, its answer often the
  /// last thing recorded.
  double _endOf(int i) => i + 1 < commands.length
      ? math.max(commands[i].at, commands[i + 1].at - 1e-3)
      : duration;

  Future<void> seek(double at) async {
    final resume = playing;
    if (resume) player.pause();
    await player.seek(at: at.clamp(0, duration));
    if (_disposed) return;
    position = player.position();
    _chosen = null;
    if (resume) player.play(speed: speed);
    notifyListeners();
  }

  Future<void> jumpTo(int command) async {
    if (command < 0 || command >= commands.length) return;
    await seek(_endOf(command));
    _chosen = command;
    notifyListeners();
  }

  void togglePlay() {
    if (playing) {
      player.pause();
      playing = false;
      _tick?.cancel();
    } else {
      player.play(speed: speed);
      playing = true;
      _chosen = null;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        position = player.position();
        playing = player.playing();
        if (!playing) _tick?.cancel();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  static const speeds = [1.0, 2.0, 8.0];

  void nextSpeed() {
    speed = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    if (playing) player.play(speed: speed);
    notifyListeners();
  }

  /// The stretches paused while recording, `(from, to)`.
  List<(double, double)> get pauses {
    final out = <(double, double)>[];
    double? from;
    for (final m in markers) {
      if (m.kind == LogMarkerKind.pause) from = m.at;
      if (m.kind == LogMarkerKind.resume && from != null) {
        out.add((from, m.at));
        from = null;
      }
    }
    if (from != null) out.add((from, duration));
    return out;
  }

  /// Its entry changed (a note).
  void changed(LogEntry fresh) {
    entry = fresh;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    player.pause();
    terminal.dispose();
    player.dispose();
    super.dispose();
  }
}

class LogViewerNotifier extends Notifier<LogViewer?> {
  /// The one shown, for letting it go: `state` cannot be read while the
  /// notifier is disposed.
  LogViewer? _shown;

  @override
  LogViewer? build() {
    // Closing its tab lets it go.
    ref.listen(tabsProvider, (_, tabs) {
      final open = tabs.tabs.any((t) => t is PageTab && t.page == PageKind.log);
      if (!open && _shown != null) _replace(null);
    });
    ref.onDispose(() => _shown?.dispose());
    return null;
  }

  /// Opens a recording in its tab, at `at` seconds, or at its end.
  Future<void> open(LogEntry entry, {double? at}) async {
    final app = ref.read(openWardProvider);
    final viewer = await LogViewer.open(
      app,
      // As it is now: a session going on has grown since the list was read.
      app.log(id: entry.id) ?? entry,
      scrollback: ref.read(settingsProvider).scrollback,
    );
    final command = at == null ? viewer.commands.length - 1 : null;
    if (command != null && command >= 0) {
      await viewer.jumpTo(command);
    } else {
      await viewer.seek(at ?? viewer.duration);
    }
    _replace(viewer);
    ref.read(tabsProvider.notifier).openPage(PageKind.log);
  }

  /// The entry changed (a note): the viewer shows it.
  void refreshEntry(LogEntry entry) {
    final v = state;
    if (v == null || v.entry.id != entry.id) return;
    v.changed(entry);
  }

  void _replace(LogViewer? next) {
    final old = _shown;
    _shown = next;
    state = next;
    // After the frame: the pane that draws it lets go of it first.
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }
}

final logViewerProvider = NotifierProvider<LogViewerNotifier, LogViewer?>(
  LogViewerNotifier.new,
);

/// Opens a session's recording by its id (from its pane, a recent
/// connection), at its end.
Future<void> openLogById(BuildContext context, WidgetRef ref, String id) async {
  final e = ref.read(openWardProvider).log(id: id);
  if (e == null || !e.recorded) return;
  await runAction(context, () => ref.read(logViewerProvider.notifier).open(e));
}

/// Connects again to where a session went.
void connectAgain(WidgetRef ref, LogEntry e) {
  final tabs = ref.read(tabsProvider.notifier);
  switch (e.place) {
    case LogPlace.host:
      final host = ref
          .read(libraryProvider)
          .hosts
          .where((h) => h.id == e.hostId)
          .firstOrNull;
      if (host != null) {
        tabs.openHost(host);
      } else if (QuickTarget.parse(e.address) case final t?) {
        tabs.openAddress(t);
      }
    case LogPlace.address:
      if (QuickTarget.parse(e.address) case final t?) tabs.openAddress(t);
    case LogPlace.local:
      tabs.openLocal();
  }
}

/// Saves a session with a note, or changes its note.
Future<void> editNote(BuildContext context, WidgetRef ref, LogEntry e) async {
  final l = context.l10n;
  final note = await askText(
    context,
    title: e.saved ? l.logEditNote : l.logNoteTitle,
    action: l.save,
    initial: e.note,
    hint: l.logNoteHint,
    help: l.logNoteHelp,
  );
  if (note == null || !context.mounted) return;
  final app = ref.read(openWardProvider);
  await runAction(context, () => app.saveLog(id: e.id, note: note));
  _refresh(ref, e.id);
}

void _refresh(WidgetRef ref, String id) {
  ref.read(logsProvider.notifier).refresh();
  if (ref.read(openWardProvider).log(id: id) case final fresh?) {
    ref.read(logViewerProvider.notifier).refreshEntry(fresh);
  }
}

/// A name for an exported file: the session's and when it began.
String exportName(AppLocalizations l, LogEntry e, String ext) {
  final label = logLabel(l, e).replaceAll(RegExp(r'[^\w.@-]+'), '-');
  final at = DateFormat('yyyy-MM-dd HHmm').format(started(e));
  return '$label $at.$ext';
}

class LogViewPage extends ConsumerWidget {
  const LogViewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(logViewerProvider);
    final c = context.ow.colors;
    if (viewer == null) {
      return ColoredBox(
        color: c.surface,
        child: Center(
          child: Text(
            context.l10n.logViewerEmpty,
            style: TextStyle(color: c.textMuted),
          ),
        ),
      );
    }
    return _LogView(key: ObjectKey(viewer), viewer: viewer);
  }
}

class _LogView extends ConsumerWidget {
  const _LogView({super.key, required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ow.colors;
    final live = viewer.entry.end == LogEnd.open;
    final find = macShortcuts
        ? const SingleActivator(LogicalKeyboardKey.keyF, meta: true)
        : const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          );
    return CallbackShortcuts(
      bindings: {
        find: viewer.terminal.openFind,
        const SingleActivator(LogicalKeyboardKey.space): viewer.togglePlay,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            viewer.jumpTo((viewer.currentCommand ?? 1) - 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            viewer.jumpTo((viewer.currentCommand ?? -1) + 1),
      },
      child: ColoredBox(
        color: c.surface,
        child: ListenableBuilder(
          listenable: Listenable.merge([viewer, viewer.terminal]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bar(viewer: viewer),
              if (viewer.entry.saved) _NoteStrip(viewer: viewer),
              // Cut short: a session still going on, or a sudden exit.
              if (!viewer.complete)
                Container(
                  color: live ? c.sunken : c.warnSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: OwSpace.s8,
                    vertical: OwSpace.s3,
                  ),
                  child: Text(
                    live
                        ? context.l10n.logStillRecording
                        : context.l10n.logIncomplete,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: live ? c.textMuted : c.text,
                    ),
                  ),
                ),
              Divider(height: 1, color: c.border),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (viewer.markers.isNotEmpty) ...[
                      SizedBox(width: 248, child: _Commands(viewer: viewer)),
                      VerticalDivider(width: 1, color: c.border),
                    ],
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: TerminalPane(
                              key: const ValueKey('log.terminal'),
                              controller: viewer.terminal,
                              readOnly: true,
                            ),
                          ),
                          if (viewer.terminal.findOpen)
                            Positioned(
                              top: 8,
                              right: 12,
                              child: FindBar(controller: viewer.terminal),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border),
              _Timeline(viewer: viewer),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s8,
        OwSpace.s5,
        OwSpace.s6,
        OwSpace.s5,
      ),
      // Narrow (a small window), the actions as icons: their names stay in
      // the tooltips.
      child: LayoutBuilder(
        builder: (context, box) => _row(context, ref, box.maxWidth < 640),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, bool narrow) {
    final l = context.l10n;
    final c = context.ow.colors;
    final e = viewer.entry;
    final env = logEnv(e);
    final meta = [
      '${whenText(l, e)} – ${timeRange(l, e).split(' – ').last}',
      lengthText(l, e),
      if (e.place != LogPlace.local) e.address,
      formatSize(l, e.bytes.toInt()),
    ].join(' · ');
    return Row(
      children: [
        SystemBadge(
          code: e.place == LogPlace.local ? 'mac' : e.system,
          env: env,
          size: 26,
        ),
        const SizedBox(width: OwSpace.s6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        logLabel(l, e),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: OwText.title,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (env != null) ...[
                    const SizedBox(width: OwSpace.s4),
                    EnvChip(env),
                  ],
                  const SizedBox(width: OwSpace.s4),
                  Pill(l.logReadOnly, tone: PillTone.warm),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: OwText.small, color: c.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: OwSpace.s4),
        _SaveButton(viewer: viewer, narrow: narrow),
        const SizedBox(width: OwSpace.s4),
        _ExportMenu(viewer: viewer, narrow: narrow),
        const SizedBox(width: OwSpace.s4),
        if (narrow)
          IconButton(
            key: const ValueKey('log.connect'),
            tooltip: l.logsConnectAgain,
            onPressed: () => connectAgain(ref, e),
            icon: const Icon(Icons.refresh, size: 18),
          )
        else
          OutlinedButton.icon(
            key: const ValueKey('log.connect'),
            onPressed: () => connectAgain(ref, e),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l.logsConnectAgain),
          ),
        const SizedBox(width: OwSpace.s2),
        _MoreMenu(viewer: viewer),
      ],
    );
  }
}

class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.viewer, required this.narrow});

  final LogViewer viewer;
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.ow.colors;
    final e = viewer.entry;
    if (narrow) {
      return IconButton(
        key: ValueKey(e.saved ? 'log.saved' : 'log.save'),
        tooltip: e.saved ? l.logSaved : l.save,
        onPressed: () => editNote(context, ref, e),
        icon: e.saved
            ? Icon(Icons.star, size: 18, color: c.warn)
            : const Icon(Icons.star_border, size: 18),
      );
    }
    if (e.saved) {
      return FilledButton.tonalIcon(
        key: const ValueKey('log.saved'),
        onPressed: () => editNote(context, ref, e),
        icon: Icon(Icons.star, size: 16, color: c.warn),
        label: Text(l.logSaved),
      );
    }
    return OutlinedButton.icon(
      key: const ValueKey('log.save'),
      onPressed: () => editNote(context, ref, e),
      icon: const Icon(Icons.star_border, size: 16),
      label: Text(l.save),
    );
  }
}

class _ExportMenu extends ConsumerWidget {
  const _ExportMenu({required this.viewer, required this.narrow});

  final LogViewer viewer;
  final bool narrow;

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    LogFormat format,
  ) async {
    final l = context.l10n;
    final e = viewer.entry;
    final ext = format == LogFormat.cast ? 'cast' : 'txt';
    final to = await chooseSave(exportName(l, e, ext));
    if (to == null) return;
    if (!context.mounted) return to.cancel();
    final app = ref.read(openWardProvider);
    final done = await runAction(
      context,
      () => app.exportLog(id: e.id, path: to.path, format: format),
    );
    if (!done) return to.cancel();
    if (await to.finish() && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.logExported(to.shown))));
    }
  }

  Future<void> _copy(
    BuildContext context,
    Future<String> Function() text,
  ) async {
    final l = context.l10n;
    final done = await runAction(context, () async {
      await Clipboard.setData(ClipboardData(text: await text()));
    });
    if (done && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.logCopied)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.ow.colors;
    final app = ref.read(openWardProvider);
    final id = viewer.entry.id;
    final command = viewer.currentCommand;
    PopupMenuItem<VoidCallback> item(
      String key,
      IconData icon,
      String title,
      String? help,
      VoidCallback? onTap,
    ) => PopupMenuItem(
      key: ValueKey(key),
      value: onTap,
      enabled: onTap != null,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textMuted),
          const SizedBox(width: OwSpace.s5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('log.export'),
      tooltip: l.exportEllipsis,
      onSelected: (f) => f(),
      itemBuilder: (context) => [
        item(
          'log.export.cast',
          Icons.smart_display_outlined,
          l.logExportCast,
          l.logExportCastHelp,
          () => _export(context, ref, LogFormat.cast),
        ),
        item(
          'log.export.text',
          Icons.notes,
          l.logExportText,
          l.logExportTextHelp,
          () => _export(context, ref, LogFormat.text),
        ),
        const PopupMenuDivider(),
        item(
          'log.copy.text',
          Icons.copy,
          l.logCopyText,
          null,
          () => _copy(context, () => app.logText(id: id)),
        ),
        item(
          'log.copy.command',
          Icons.terminal,
          l.logCopyCommand,
          command == null ? null : '\$ ${viewer.commands[command].command}',
          command == null
              ? null
              : () => _copy(
                  context,
                  () => app.logCommandText(id: id, index: command),
                ),
        ),
      ],
      icon: narrow ? const Icon(Icons.ios_share, size: 18) : null,
      // Only its look: the menu's button is the one a screen reader uses.
      child: narrow
          ? null
          : ExcludeSemantics(
              child: IgnorePointer(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: Text(l.exportEllipsis),
                ),
              ),
            ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final e = viewer.entry;
    Future<void> delete() async {
      final sure = await confirmDestructive(
        context,
        title: l.logDeleteTitle,
        body: l.logDeleteBody,
        action: l.delete,
        actionKey: const ValueKey('log.delete.confirm'),
      );
      if (!sure || !context.mounted) return;
      final app = ref.read(openWardProvider);
      final done = await runAction(context, () => app.deleteLog(id: e.id));
      if (!done) return;
      ref.read(logsProvider.notifier).refresh();
      final tabs = ref.read(tabsProvider);
      final at = tabs.tabs.indexWhere(
        (t) => t is PageTab && t.page == PageKind.log,
      );
      if (at >= 0) ref.read(tabsProvider.notifier).close(at);
    }

    Future<void> unsave() async {
      final app = ref.read(openWardProvider);
      await runAction(context, () => app.unsaveLog(id: e.id));
      _refresh(ref, e.id);
    }

    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('log.more'),
      tooltip: l.logMoreActions,
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (f) => f(),
      itemBuilder: (context) => [
        if (e.saved)
          PopupMenuItem(
            key: const ValueKey('log.unsave'),
            value: unsave,
            child: Text(l.logUnsave),
          ),
        PopupMenuItem(
          key: const ValueKey('log.delete'),
          value: delete,
          child: Text(l.logDelete),
        ),
      ],
    );
  }
}

class _NoteStrip extends ConsumerWidget {
  const _NoteStrip({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.ow.colors;
    final e = viewer.entry;
    return Container(
      key: const ValueKey('log.note'),
      color: c.raised,
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s8,
        OwSpace.s3,
        OwSpace.s6,
        OwSpace.s3,
      ),
      child: Row(
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 16, color: c.warn),
          const SizedBox(width: OwSpace.s5),
          Expanded(
            child: Text(
              e.note.isEmpty ? l.logNeverExpires : e.note,
              style: TextStyle(
                fontSize: OwText.body,
                color: e.note.isEmpty ? c.textMuted : c.text,
              ),
            ),
          ),
          if (e.note.isNotEmpty) ...[
            Text(
              l.logNeverExpires,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
            const SizedBox(width: OwSpace.s4),
          ],
          TextButton.icon(
            onPressed: () => editNote(context, ref, e),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(l.logEditNote),
          ),
        ],
      ),
    );
  }
}

class _Commands extends StatelessWidget {
  const _Commands({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final current = viewer.currentCommand;
    var command = -1;
    final rows = <Widget>[];
    for (final m in viewer.markers) {
      if (m.kind == LogMarkerKind.command) {
        final i = ++command;
        final on = i == current;
        rows.add(
          Semantics(
            selected: on,
            child: Material(
              color: on ? c.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(context.ow.shape.radius),
              child: InkWell(
                key: ValueKey('log.command.$i'),
                borderRadius: BorderRadius.circular(context.ow.shape.radius),
                onTap: () => viewer.jumpTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OwSpace.s5,
                    vertical: OwSpace.s3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clockText(m.at),
                        style: monoStyle(
                          context,
                          size: OwText.small,
                          color: on ? c.accentText : c.textMuted,
                        ),
                      ),
                      Text(
                        m.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                          context,
                          size: OwText.small,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final (icon, text) = switch (m.kind) {
        LogMarkerKind.pause => (Icons.pause, l.logMarkPause),
        LogMarkerKind.lost => (Icons.link_off, l.logMarkLost),
        LogMarkerKind.back => (Icons.link, l.logMarkBack),
        LogMarkerKind.omitted => (Icons.more_horiz, l.logMarkOmitted),
        LogMarkerKind.full => (Icons.block, l.logMarkFull),
        _ => (null, null),
      };
      if (icon == null || text == null) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OwSpace.s5,
            vertical: OwSpace.s2,
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: c.warn),
              const SizedBox(width: OwSpace.s3),
              Expanded(
                child: Text(
                  '${clockText(m.at)} · $text',
                  style: TextStyle(fontSize: OwText.small, color: c.text),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: c.window,
      child: ListView(
        padding: const EdgeInsets.all(OwSpace.s4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OwSpace.s5,
              OwSpace.s1,
              OwSpace.s5,
              OwSpace.s3,
            ),
            child: SectionLabel('${l.logCommands} · ${viewer.commands.length}'),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final v = viewer;
    final paused = v.pauses.fold(0.0, (s, p) => s + (p.$2 - p.$1));
    return ColoredBox(
      color: c.window,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OwSpace.s7,
          vertical: OwSpace.s3,
        ),
        child: Row(
          children: [
            IconButton.filled(
              key: const ValueKey('log.play'),
              tooltip: v.playing ? l.logPausePlayback : l.logPlay,
              style: IconButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.onPrimary,
              ),
              onPressed: v.togglePlay,
              icon: Icon(v.playing ? Icons.pause : Icons.play_arrow, size: 20),
            ),
            const SizedBox(width: OwSpace.s3),
            OutlinedButton(
              key: const ValueKey('log.speed'),
              onPressed: v.nextSpeed,
              child: Text(
                '${v.speed.toStringAsFixed(0)}×',
                semanticsLabel: l.logSpeed('${v.speed.toStringAsFixed(0)}×'),
              ),
            ),
            const SizedBox(width: OwSpace.s5),
            Text(
              clockText(v.position),
              style: monoStyle(context, size: OwText.body, color: c.text),
            ),
            const SizedBox(width: OwSpace.s5),
            Expanded(child: _Track(viewer: v)),
            const SizedBox(width: OwSpace.s5),
            Text(
              clockText(v.duration),
              style: monoStyle(context, size: OwText.body, color: c.textMuted),
            ),
            const SizedBox(width: OwSpace.s6),
            Text(
              [
                l.logsCommands(v.commands.length),
                if (paused >= 1)
                  l.logPausedTotal(
                    durationText(l, Duration(seconds: paused.round())),
                  ),
              ].join(' · '),
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The session from start to end: what was played, each command, the
/// stretches paused, and a handle to drag. The arrows move 10 s.
class _Track extends StatelessWidget {
  const _Track({required this.viewer});

  final LogViewer viewer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final v = viewer;
    return LayoutBuilder(
      builder: (context, box) {
        void seekAt(double x) {
          if (v.duration <= 0) return;
          v.seek((x / box.maxWidth).clamp(0.0, 1.0) * v.duration);
        }

        return Semantics(
          key: const ValueKey('log.timeline'),
          slider: true,
          label: l.logPosition,
          value: clockText(v.position),
          increasedValue: clockText(math.min(v.duration, v.position + 10)),
          decreasedValue: clockText(math.max(0, v.position - 10)),
          onIncrease: () => v.seek(v.position + 10),
          onDecrease: () => v.seek(v.position - 10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 28,
              child: CustomPaint(
                painter: _TrackPainter(
                  duration: v.duration,
                  position: v.position,
                  commands: [for (final m in v.commands) m.at],
                  pauses: v.pauses,
                  current: v.currentCommand,
                  track: c.control,
                  played: c.primary,
                  tick: c.textMuted,
                  pause: c.warn,
                  handle: c.text,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.duration,
    required this.position,
    required this.commands,
    required this.pauses,
    required this.current,
    required this.track,
    required this.played,
    required this.tick,
    required this.pause,
    required this.handle,
  });

  final double duration;
  final double position;
  final List<double> commands;
  final List<(double, double)> pauses;
  final int? current;
  final Color track, played, tick, pause, handle;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    double x(double t) => duration <= 0 ? 0 : t / duration * size.width;
    final line = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      line..color = track,
    );
    canvas.drawLine(
      Offset(0, mid),
      Offset(x(position), mid),
      line..color = played,
    );
    for (final (from, to) in pauses) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x(from),
            mid - 4,
            math.max(x(to), x(from) + 2),
            mid + 4,
          ),
          const Radius.circular(OwSpace.s1),
        ),
        Paint()..color = pause.withValues(alpha: 0.55),
      );
    }
    for (var i = 0; i < commands.length; i++) {
      final at = x(commands[i]);
      canvas.drawLine(
        Offset(at, mid - 6),
        Offset(at, mid + 6),
        Paint()
          ..strokeWidth = i == current ? 2 : 1.5
          ..color = i == current ? played : tick,
      );
    }
    canvas.drawCircle(Offset(x(position), mid), 6, Paint()..color = handle);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.position != position ||
      old.current != current ||
      old.duration != duration ||
      old.commands.length != commands.length ||
      old.track != track ||
      old.played != played;
}
