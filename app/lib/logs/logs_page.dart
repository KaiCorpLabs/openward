// The «Registros» page: every session by day, with when, how long and how
// it ended; a search through what was seen in the recorded ones; filters;
// and, beside the list, the last that was seen of the one chosen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/errors.dart';
import '../core/providers.dart';
import '../hosts/hosts_page.dart' show FilterPill;
import '../l10n/l10n.dart';
import '../settings/settings_page.dart' show SettingsSection, openSettings;
import '../sftp/format.dart' show formatSize;
import '../src/rust/api/logs.dart';
import '../src/rust/api/vault.dart' show EnvironmentView;
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'log_viewer.dart';
import 'logs.dart';

enum _Show { all, recorded, saved, local }

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final _query = TextEditingController();
  _Show _show = _Show.all;

  /// An environment, by its name.
  String? _env;
  String? _selected;

  /// The match chosen in a search, in [_selected].
  LogHit? _hit;

  Timer? _typing;
  StreamSubscription<LogFound>? _search;
  String _searched = '';
  List<LogFound> _found = const [];
  bool _searching = false;

  @override
  void dispose() {
    _typing?.cancel();
    _search?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Each change searches again once the typing pauses.
  void _onQuery(String _) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 250), _runSearch);
    setState(() {});
  }

  void _runSearch() {
    final q = _query.text.trim();
    if (q == _searched) return;
    _search?.cancel();
    _searched = q;
    _hit = null;
    if (q.isEmpty) {
      setState(() {
        _found = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _found = [];
      _searching = true;
    });
    final app = ref.read(openWardProvider);
    _search = app
        .searchLogs(query: q)
        .listen(
          (f) => setState(() => _found = [..._found, f]),
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  bool _keep(LogEntry e) =>
      switch (_show) {
        _Show.all => true,
        _Show.recorded => e.recorded,
        _Show.saved => e.saved,
        _Show.local => e.place == LogPlace.local,
      } &&
      (_env == null || e.marking?.name == _env);

  /// Opens a recording: at its end, or a moment past a match, so that
  /// the whole line it began is on screen.
  void _open(LogEntry e, {double? at}) {
    if (!e.recorded) return;
    runAction(
      context,
      () => ref
          .read(logViewerProvider.notifier)
          .open(e, at: at == null ? null : at + 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final entries = ref.watch(logsProvider);
    final searching = _query.text.trim().isNotEmpty;
    final shown = searching
        ? [
            for (final f in _found)
              if (_keep(f.entry)) f.entry,
          ]
        : entries.where(_keep).toList();
    final hits = {for (final f in _found) f.entry.id: f};
    final selected =
        shown.where((e) => e.id == _selected).firstOrNull ?? shown.firstOrNull;
    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OwSpace.s14,
          OwSpace.s11,
          OwSpace.s14,
          OwSpace.s6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, entries),
            const SizedBox(height: OwSpace.s7),
            if (entries.isEmpty)
              Expanded(child: _empty(context))
            else ...[
              _searchField(context),
              const SizedBox(height: OwSpace.s6),
              _filters(context, searching ? shown : entries),
              const SizedBox(height: OwSpace.s6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final list = _list(context, shown, hits, selected);
                    if (box.maxWidth < 760) return list;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: list),
                        const SizedBox(width: OwSpace.s8),
                        SizedBox(
                          width: 360,
                          child: selected == null
                              ? const SizedBox()
                              : _Preview(
                                  key: ValueKey((selected.id, _hit?.at)),
                                  entry: selected,
                                  hit: _hit,
                                  onOpen: (at) => _open(selected, at: at),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, List<LogEntry> entries) {
    final l = context.l10n;
    final c = context.ow.colors;
    final app = ref.read(openWardProvider);
    final usage = app.logsUsage();
    final config = ref.watch(logsConfigProvider);
    final size = formatSize(l, usage.bytes.toInt());
    final limits = config.maxBytes > BigInt.zero && config.keepDays > 0
        ? l.logsUsage(
            size,
            formatSize(l, config.maxBytes.toInt()),
            config.keepDays,
          )
        : size;
    return Row(
      children: [
        Semantics(
          header: true,
          child: Text(l.logs, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(width: OwSpace.s5),
        Text(
          '${entries.length}',
          style: monoStyle(context, size: 13, color: c.textSubtle),
        ),
        const SizedBox(width: OwSpace.s5),
        Flexible(
          child: Text(
            '· $limits',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          key: const ValueKey('logs.settings'),
          onPressed: () => openSettings(ref, SettingsSection.logs),
          icon: const Icon(Icons.settings_outlined, size: 16),
          label: Text(l.logsSettings),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 32, color: c.textMuted),
            const SizedBox(height: OwSpace.s6),
            Text(
              l.logsEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: OwSpace.s4),
            Text(
              l.logsEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final q = _query.text.trim();
    final total = _found.fold(0, (n, f) => n + f.total);
    final status = q.isEmpty
        ? null
        : _searching && _found.isEmpty
        ? l.logsSearching
        : _found.isEmpty
        ? l.logsSearchNone
        : '${l.logsHits(total)} ${l.logsHitsIn(_found.length)}';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _query.clear();
          _onQuery('');
          _runSearch();
        },
      },
      child: TextField(
        key: const ValueKey('logs.search'),
        controller: _query,
        autofocus: true,
        onChanged: _onQuery,
        onSubmitted: (_) => _runSearch(),
        style: const TextStyle(fontSize: OwText.body),
        decoration: InputDecoration(
          isDense: true,
          hintText: l.logsSearchHint,
          prefixIcon: Icon(Icons.search, size: 16, color: c.textSubtle),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: status == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: OwSpace.s5),
                  child: Text(
                    status,
                    key: const ValueKey('logs.search.status'),
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: c.textMuted,
                    ),
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(minHeight: 0),
          contentPadding: const EdgeInsets.symmetric(vertical: OwSpace.s5),
        ),
      ),
    );
  }

  Widget _filters(BuildContext context, List<LogEntry> entries) {
    final l = context.l10n;
    final envs = <String, (EnvironmentView, int)>{};
    for (final e in entries) {
      if (logEnv(e) case final env?) {
        envs[env.name] = (env, (envs[env.name]?.$2 ?? 0) + 1);
      }
    }
    int count(_Show s) => s == _Show.all
        ? entries.length
        : entries
              .where(
                (e) => switch (s) {
                  _Show.recorded => e.recorded,
                  _Show.saved => e.saved,
                  _Show.local => e.place == LogPlace.local,
                  _Show.all => true,
                },
              )
              .length;
    FilterPill pill(_Show s, String text, {bool star = false}) => FilterPill(
      key: ValueKey('logs.filter.${s.name}'),
      text: text,
      count: count(s),
      star: star,
      on: _show == s && (s != _Show.all || _env == null),
      onTap: () => setState(() {
        _show = s;
        if (s == _Show.all) _env = null;
      }),
    );
    return Semantics(
      container: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          pill(_Show.all, l.logsAll),
          if (count(_Show.recorded) > 0) pill(_Show.recorded, l.logsRecorded),
          if (count(_Show.saved) > 0)
            pill(_Show.saved, l.logsSaved, star: true),
          for (final (env, n)
              in (envs.values.toList()..sort((a, b) => b.$2 - a.$2)))
            FilterPill(
              key: ValueKey('logs.filter.env.${env.name}'),
              text: shownEnv(l, env).name,
              count: n,
              env: env,
              on: _env == env.name,
              onTap: () =>
                  setState(() => _env = _env == env.name ? null : env.name),
            ),
          if (count(_Show.local) > 0) pill(_Show.local, l.logsLocal),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<LogEntry> shown,
    Map<String, LogFound> hits,
    LogEntry? selected,
  ) {
    final l = context.l10n;
    final c = context.ow.colors;
    final searching = _query.text.trim().isNotEmpty;
    if (shown.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(OwSpace.s6),
          child: Text(
            searching
                ? (_searching ? l.logsSearching : l.logsSearchNone)
                : l.logsNothing,
            style: TextStyle(color: c.textMuted),
          ),
        ),
      );
    }
    final rows = <Widget>[];
    for (final (day, entries) in byDay(shown)) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OwSpace.s6,
            OwSpace.s6,
            OwSpace.s6,
            OwSpace.s2,
          ),
          child: SectionLabel(dayTitle(l, day)),
        ),
      );
      for (final e in entries) {
        rows.add(
          _Row(
            key: ValueKey('logs.row.${e.id}'),
            entry: e,
            selected: e.id == selected?.id,
            found: hits[e.id],
            chosenHit: e.id == selected?.id ? _hit : null,
            onTap: () => setState(() {
              _selected = e.id;
              _hit = null;
            }),
            onHit: (h) => setState(() {
              _selected = e.id;
              _hit = h;
            }),
            onOpen: () => _open(e, at: e.id == selected?.id ? _hit?.at : null),
          ),
        );
      }
    }
    if (searching) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(OwSpace.s6),
          child: Text(
            l.logsSearchNote,
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          ),
        ),
      );
    }
    return ListView(children: rows);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onHit,
    this.found,
    this.chosenHit,
  });

  final LogEntry entry;
  final bool selected;
  final LogFound? found;
  final LogHit? chosenHit;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final ValueChanged<LogHit> onHit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final e = entry;
    final env = logEnv(e);
    final open = e.end == LogEnd.open;
    final (stateText, stateColor, stateIcon) = switch (e.end) {
      LogEnd.open when e.recorded => (l.logsLive, c.accentText, null),
      LogEnd.open => (l.logsOpenEntry, c.textMuted, null),
      LogEnd.lost => (l.logsCut, c.warn, Icons.warning_amber_rounded),
      LogEnd.appQuit => (l.logsAppQuit, c.warn, Icons.warning_amber_rounded),
      LogEnd.closed when !e.recorded => (l.logsNotRecorded, c.textMuted, null),
      LogEnd.closed => (l.logsCommands(e.commands), c.textMuted, null),
    };
    final second = e.saved && e.note.isNotEmpty ? '«${e.note}»' : e.address;
    final hits = found;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(ow.shape.radius),
          onTap: onTap,
          onDoubleTap: e.recorded ? onOpen : null,
          child: Opacity(
            opacity: e.recorded || open ? 1 : 0.8,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OwSpace.s6,
                vertical: OwSpace.s4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SystemBadge(
                    code: e.place == LogPlace.local ? 'mac' : e.system,
                    env: env,
                    size: 22,
                  ),
                  const SizedBox(width: OwSpace.s6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                logLabel(l, e),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (env != null) ...[
                              const SizedBox(width: OwSpace.s4),
                              EnvChip(env),
                            ],
                            if (e.saved) ...[
                              const SizedBox(width: OwSpace.s3),
                              Icon(
                                Icons.star,
                                size: 14,
                                color: c.warn,
                                semanticLabel: l.logSaved,
                              ),
                            ],
                            if (e.tmux) ...[
                              const SizedBox(width: OwSpace.s3),
                              Pill('tmux', tone: PillTone.warm),
                            ],
                          ],
                        ),
                        Text(
                          second,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: e.saved && e.note.isNotEmpty
                              ? TextStyle(
                                  fontSize: OwText.small,
                                  color: c.textMuted,
                                )
                              : monoStyle(
                                  context,
                                  size: OwText.small,
                                  color: c.textMuted,
                                ),
                        ),
                        if (hits != null) ...[
                          const SizedBox(height: OwSpace.s2),
                          for (final h in hits.hits.take(3))
                            _HitLine(
                              hit: h,
                              chosen: chosenHit == h,
                              onTap: () => onHit(h),
                            ),
                          if (hits.total > 3)
                            Text(
                              l.logsMoreHits(hits.total - 3),
                              style: TextStyle(
                                fontSize: OwText.small,
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: OwSpace.s6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeRange(l, e),
                        style: monoStyle(
                          context,
                          size: OwText.small,
                          color: e.recorded ? c.text : c.textMuted,
                        ),
                      ),
                      Text(
                        [
                          lengthText(l, e),
                          if (e.recorded && !open)
                            formatSize(l, e.bytes.toInt()),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: OwText.small,
                          color: c.textMuted,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (stateIcon != null) ...[
                            Icon(stateIcon, size: 13, color: stateColor),
                            const SizedBox(width: OwSpace.s1),
                          ],
                          if (open && e.recorded) ...[
                            const StatusDot(Status.connected, size: 7),
                            const SizedBox(width: OwSpace.s2),
                          ],
                          Text(
                            stateText,
                            style: TextStyle(
                              fontSize: OwText.small,
                              color: stateColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HitLine extends StatelessWidget {
  const _HitLine({
    required this.hit,
    required this.chosen,
    required this.onTap,
  });

  final LogHit hit;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OwSpace.hair),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                clockText(hit.at),
                textAlign: TextAlign.right,
                style: monoStyle(
                  context,
                  size: OwText.small,
                  color: chosen ? c.accentText : c.textMuted,
                ),
              ),
            ),
            const SizedBox(width: OwSpace.s4),
            Expanded(
              child: Text(
                hit.line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: OwText.small, color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the chosen session shows beside the list: when and how it went,
/// its last lines (or those around a match) and last commands.
class _Preview extends ConsumerStatefulWidget {
  const _Preview({
    super.key,
    required this.entry,
    required this.onOpen,
    this.hit,
  });

  final LogEntry entry;
  final LogHit? hit;
  final ValueChanged<double?> onOpen;

  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  Future<LogPreview?>? _preview;
  Future<List<LogLine>>? _around;

  @override
  void initState() {
    super.initState();
    final app = ref.read(openWardProvider);
    final e = widget.entry;
    if (e.recorded) {
      _preview = app
          .logPreview(id: e.id, lines: 10)
          .then<LogPreview?>((p) => p)
          .catchError((_) => null);
      if (widget.hit case final hit?) {
        _around = app
            .logLinesAround(id: e.id, at: hit.at, before: 2, after: 5)
            .catchError((_) => <LogLine>[]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final e = widget.entry;
    final env = logEnv(e);
    final hit = widget.hit;
    final hm = DateFormat.Hm(l.localeName);
    final end = ended(e);
    return Container(
      key: const ValueKey('logs.preview'),
      padding: const EdgeInsets.all(OwSpace.s8),
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SystemBadge(
                code: e.place == LogPlace.local ? 'mac' : e.system,
                env: env,
                size: 24,
              ),
              const SizedBox(width: OwSpace.s5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            logLabel(l, e),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: OwText.title,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (env != null) ...[
                          const SizedBox(width: OwSpace.s4),
                          EnvChip(env),
                        ],
                      ],
                    ),
                    Text(
                      e.address,
                      style: monoStyle(
                        context,
                        size: OwText.small,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OwSpace.s5),
          Text(
            [
              '${whenText(l, e)} – ${end == null ? l.logsNow : hm.format(end)}',
              lengthText(l, e),
              if (e.recorded) l.logsCommands(e.commands),
              if (e.recorded && end != null) formatSize(l, e.bytes.toInt()),
            ].join(' · '),
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          ),
          const SizedBox(height: OwSpace.s5),
          if (e.end == LogEnd.lost || e.end == LogEnd.appQuit) ...[
            Container(
              padding: const EdgeInsets.all(OwSpace.s5),
              decoration: BoxDecoration(
                color: c.warnSoft,
                border: Border.all(color: c.warnLine),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Text(
                e.end == LogEnd.lost
                    ? l.logsCutAt(end == null ? '' : hm.format(end))
                    : l.logsAppQuitAt(end == null ? '' : hm.format(end)),
                style: TextStyle(fontSize: OwText.small, color: c.text),
              ),
            ),
            const SizedBox(height: OwSpace.s5),
          ],
          if (!e.recorded)
            Text(
              l.logsNoRecording,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            )
          else
            Expanded(child: _content(context, hit)),
          const SizedBox(height: OwSpace.s6),
          Row(
            children: [
              if (e.recorded)
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('logs.open'),
                    onPressed: () => widget.onOpen(hit?.at),
                    icon: const Icon(Icons.subject, size: 16),
                    label: Text(hit == null ? l.logsOpen : l.logsOpenHere),
                  ),
                ),
              if (e.recorded) const SizedBox(width: OwSpace.s4),
              OutlinedButton.icon(
                key: const ValueKey('logs.connect'),
                onPressed: () => connectAgain(ref, e),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l.logsConnectAgain),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, LogHit? hit) {
    final l = context.l10n;
    final c = context.ow.colors;
    Widget box(List<LogLine> lines) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OwSpace.s5),
      decoration: BoxDecoration(
        color: c.sunken,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(context.ow.shape.radius),
      ),
      child: Text(
        lines.map((x) => x.text).join('\n'),
        key: const ValueKey('logs.preview.lines'),
        maxLines: 12,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: monoStyle(context, size: OwText.small, color: c.text),
      ),
    );
    if (hit != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.logsHitAt(clockText(hit.at)),
            style: TextStyle(fontSize: OwText.small, color: c.textMuted),
          ),
          const SizedBox(height: OwSpace.s3),
          FutureBuilder(
            future: _around,
            builder: (context, s) => box(s.data ?? const []),
          ),
        ],
      );
    }
    return FutureBuilder(
      future: _preview,
      builder: (context, s) {
        final p = s.data;
        if (p == null) return const SizedBox();
        final commands = [
          for (final m in p.markers)
            if (m.kind == LogMarkerKind.command) m,
        ];
        final last = commands.reversed.take(3).toList().reversed;
        return ListView(
          children: [
            if (p.lines.isNotEmpty) box(p.lines),
            if (last.isNotEmpty) ...[
              const SizedBox(height: OwSpace.s6),
              SectionLabel(l.logsLastCommands),
              const SizedBox(height: OwSpace.s2),
              for (final m in last)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: OwSpace.hair),
                  child: Text(
                    '${clockText(m.at).padLeft(6)}  ${m.command}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      context,
                      size: OwText.small,
                      color: c.text,
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
