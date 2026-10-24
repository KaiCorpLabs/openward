// The «Túneles» page and what the rest of the app shows of tunnels: the
// count in a terminal's status bar with its popover, and the notice of one
// that did not open on connect.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../hosts/import_ssh_config.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/tunnels.dart';
import '../tabs/messages.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'tunnel_editor.dart';
import 'tunnels.dart';

/// `localhost:5433 → 10.0.4.21:5432`, `localhost:1080 (SOCKS5)`,
/// `web-2:8080 → localhost:5173`.
String forwardText(TunnelView t) {
  final s = t.spec;
  final lan = (s.listenAddress ?? '').isNotEmpty;
  final here = '${lan ? '*' : 'localhost'}:${s.listenPort}';
  final dest = '${s.destHost}:${s.destPort}';
  return switch (s.kind) {
    TunnelKind.local => '$here → $dest',
    TunnelKind.dynamic_ => '$here (SOCKS5)',
    TunnelKind.remote => '${t.hostLabel}:${s.listenPort} → $dest',
  };
}

String kindText(AppLocalizations l, TunnelKind k) => switch (k) {
  TunnelKind.local => l.kindLocalShort,
  TunnelKind.remote => l.kindRemoteShort,
  TunnelKind.dynamic_ => l.kindDynamicShort,
};

String stateText(AppLocalizations l, TunnelView t) => switch (t.state) {
  TunnelStateKind.closed => l.tunnelClosed,
  TunnelStateKind.opening => l.tunnelOpening,
  TunnelStateKind.open =>
    t.connections > 0 ? l.tunnelOpenWith(t.connections) : l.tunnelOpen,
  TunnelStateKind.failed =>
    t.error?.kind == TunnelErrorKind.lost ? l.tunnelLost : l.tunnelFailed,
};

/// Why it failed, in words.
String tunnelErrorText(AppLocalizations l, TunnelView t) {
  final e = t.error;
  if (e == null) return '';
  return switch (e.kind) {
    TunnelErrorKind.portInUse =>
      e.remote
          ? l.tunnelRemotePortBusy(e.port, t.hostLabel)
          : l.tunnelPortBusy(e.port),
    TunnelErrorKind.badAddress => l.tunnelBadAddress,
    TunnelErrorKind.connection =>
      e.failure == null ? l.failureOther : failureText(l, e.failure!),
    TunnelErrorKind.lost => l.tunnelLostBody(t.hostLabel),
    TunnelErrorKind.other => l.failureOther,
  };
}

/// The error, for «Detalles», when the core's words say more than ours.
TunnelErrorView? _details(TunnelView t) => switch (t.error) {
  final e?
      when e.kind == TunnelErrorKind.connection ||
          e.kind == TunnelErrorKind.other =>
    e,
  _ => null,
};

/// A clause on its own: capitalized.
String _sentence(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// The port to offer instead of one that is taken: a free one here, or
/// the next one on the server.
int? suggestedPort(WidgetRef ref, TunnelView t) {
  final e = t.error;
  if (e?.kind != TunnelErrorKind.portInUse) return null;
  if (e!.remote) return e.port < 65535 ? e.port + 1 : null;
  return ref.read(tunnelBoardProvider).app.freePortNear(port: e.port);
}

/// Saves `t` with another port and opens it.
Future<void> useOtherPort(
  BuildContext context,
  WidgetRef ref,
  TunnelView t,
  int port,
) async {
  final board = ref.read(tunnelBoardProvider);
  final s = t.spec;
  final saved = await runAction(
    context,
    () => board.app.updateTunnel(
      id: t.id,
      rev: t.rev,
      spec: TunnelSpec(
        label: s.label,
        hostId: s.hostId,
        kind: s.kind,
        listenPort: port,
        listenAddress: s.listenAddress,
        destHost: s.destHost,
        destPort: s.destPort,
        autostart: s.autostart,
      ),
    ),
  );
  board.refresh();
  if (!saved) return;
  final updated = board.byId(t.id);
  if (updated != null && context.mounted) {
    await openTunnel(context, ref, updated);
  }
}

class TunnelsPage extends ConsumerStatefulWidget {
  const TunnelsPage({super.key});

  @override
  ConsumerState<TunnelsPage> createState() => _TunnelsPageState();
}

class _TunnelsPageState extends ConsumerState<TunnelsPage> {
  late final TunnelBoard _board = ref.read(tunnelBoardProvider);
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _board.watch(true);
  }

  @override
  void dispose() {
    _board.watch(false);
    _filter.dispose();
    super.dispose();
  }

  bool _matches(TunnelView t) {
    final f = _filter.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    return [
      t.spec.label,
      t.hostLabel,
      forwardText(t),
    ].any((s) => s.toLowerCase().contains(f));
  }

  Future<void> _import() async {
    await importSshConfig(context, ref);
    _board.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    return ColoredBox(
      color: c.surface,
      child: ListenableBuilder(
        listenable: _board,
        builder: (context, _) {
          final all = _board.tunnels;
          final shown = all.where(_matches).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                l.tunnels,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.tunnelsIntro,
                              style: TextStyle(color: c.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: _import,
                        child: Text(l.importFromSshConfig),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('tunnels.new'),
                        onPressed: () => showTunnelEditor(context, ref),
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(l.newTunnel),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (all.isEmpty)
                _empty(context)
              else ...[
                Row(
                  children: [
                    SizedBox(
                      width: 360,
                      height: 34,
                      child: TextField(
                        controller: _filter,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l.filterTunnels,
                          prefixIcon: Icon(
                            Icons.search,
                            size: 16,
                            color: c.textSubtle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l.tunnelsCount(all.length, _board.open),
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _table(context, shown),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: c.textSubtle),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.tunnelsKeepConnection,
                        style: TextStyle(fontSize: 12, color: c.textSubtle),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.swap_horiz, size: 36, color: c.textSubtle),
          const SizedBox(height: 12),
          Text(
            l.noTunnels,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            l.noTunnelsBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  static const _widths = [1.35, 0.7, 1.9, 0.85, 0.75, 1.7];

  Widget _cells(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: (_widths[i] * 100).round(),
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: cells[i],
          ),
        ),
    ],
  );

  Widget _table(BuildContext context, List<TunnelView> rows) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: c.textSubtle,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        children: [
          Container(
            color: c.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _cells([
              for (final h in [
                l.name,
                l.tunnelType,
                l.forward,
                l.host,
                l.onConnect,
                l.state,
              ])
                Text(h.toUpperCase(), style: head),
            ]),
          ),
          for (final t in rows) _row(context, t),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, TunnelView t) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final failed = t.state == TunnelStateKind.failed;
    final tone = switch (t.state) {
      TunnelStateKind.open => c.accentText,
      TunnelStateKind.failed => c.danger,
      _ => c.textMuted,
    };
    final suggestion = failed ? suggestedPort(ref, t) : null;
    final small = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 28),
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: smallButtonText(context),
    );
    final action = switch (t.state) {
      TunnelStateKind.open => OutlinedButton(
        key: ValueKey('tunnel.close.${t.spec.label}'),
        style: small,
        onPressed: () => _board.close(t.id),
        child: Text(l.stopAction),
      ),
      TunnelStateKind.opening => const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _ => OutlinedButton(
        key: ValueKey('tunnel.open.${t.spec.label}'),
        style: small.copyWith(
          foregroundColor: WidgetStatePropertyAll(c.accentText),
          backgroundColor: WidgetStatePropertyAll(c.accentSoft),
        ),
        onPressed: () => openTunnel(context, ref, t),
        child: Text(failed ? l.retry : l.openAction),
      ),
    };
    return FocusOutline(
      radius: 0,
      child: InkWell(
        onTap: () => showTunnelEditor(context, ref, tunnel: t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Column(
            children: [
              _cells([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.spec.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (t.imported)
                      Text(
                        l.fromSshConfig,
                        style: TextStyle(fontSize: 12, color: c.textSubtle),
                      ),
                  ],
                ),
                Text(kindText(l, t.spec.kind)),
                Text(forwardText(t), style: monoStyle(context, color: c.text)),
                Text(t.hostLabel, overflow: TextOverflow.ellipsis),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    label: '${l.onConnect}: ${t.spec.label}',
                    child: Switch(
                      value: t.spec.autostart,
                      onChanged: (v) => _setAutostart(t, v),
                    ),
                  ),
                ),
                Row(
                  children: [
                    StatusDot(switch (t.state) {
                      TunnelStateKind.open => Status.connected,
                      TunnelStateKind.failed => Status.failed,
                      TunnelStateKind.opening => Status.connecting,
                      TunnelStateKind.closed => Status.idle,
                    }, size: 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stateText(l, t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tone),
                      ),
                    ),
                    action,
                  ],
                ),
              ]),
              if (failed) ...[
                const SizedBox(height: 8),
                Callout(
                  tone: Tone.danger,
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sentence(tunnelErrorText(l, t)),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (_details(t) case final e?) DetailsButton(e),
                      if (suggestion != null)
                        OutlinedButton(
                          style: small,
                          onPressed: () =>
                              useOtherPort(context, ref, t, suggestion),
                          child: Text(l.usePort(suggestion)),
                        ),
                      TextButton(
                        onPressed: () =>
                            showTunnelEditor(context, ref, tunnel: t),
                        child: Text(l.editEllipsis),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setAutostart(TunnelView t, bool on) async {
    final s = t.spec;
    // A failure says so, and the switch goes back with the refresh.
    await runAction(
      context,
      () => _board.app.updateTunnel(
        id: t.id,
        rev: t.rev,
        spec: TunnelSpec(
          label: s.label,
          hostId: s.hostId,
          kind: s.kind,
          listenPort: s.listenPort,
          listenAddress: s.listenAddress,
          destHost: s.destHost,
          destPort: s.destPort,
          autostart: on,
        ),
      ),
    );
    _board.refresh();
  }
}

/// In a terminal's status bar: the host's tunnels, and how many are open.
/// Opens a popover to turn them on and off.
class TunnelChip extends ConsumerStatefulWidget {
  const TunnelChip({super.key, required this.hostId, required this.hostLabel});

  final String hostId;
  final String hostLabel;

  @override
  ConsumerState<TunnelChip> createState() => _TunnelChipState();
}

class _TunnelChipState extends ConsumerState<TunnelChip> {
  late final TunnelBoard _board = ref.read(tunnelBoardProvider);

  void _popover() {
    final box = context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => Stack(
        children: [
          Positioned(
            right: (screen.width - at.dx - box.size.width).clamp(
              8,
              screen.width,
            ),
            bottom: screen.height - at.dy + 6,
            child: _TunnelPopover(
              hostId: widget.hostId,
              hostLabel: widget.hostLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) {
        final mine = _board.ofHost(widget.hostId);
        if (mine.isEmpty) return const SizedBox.shrink();
        final open = mine.where((t) => t.state == TunnelStateKind.open).length;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: OutlinedButton.icon(
            key: const ValueKey('status.tunnels'),
            onPressed: _popover,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 22),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: smallButtonText(context),
              foregroundColor: open > 0 ? c.accentText : c.textMuted,
              backgroundColor: open > 0 ? c.accentSoft : null,
              side: BorderSide(color: open > 0 ? c.accent : c.border),
            ),
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: Text(open > 0 ? l.tunnelsOpenCount(open) : l.tunnels),
          ),
        );
      },
    );
  }
}

class _TunnelPopover extends ConsumerWidget {
  const _TunnelPopover({required this.hostId, required this.hostLabel});

  final String hostId;
  final String hostLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final board = ref.watch(tunnelBoardProvider);
    return Material(
      color: c.raised,
      elevation: 12,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.control),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: SizedBox(
        width: 460,
        child: ListenableBuilder(
          listenable: board,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 16, color: c.accentText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.tunnelsOf(hostLabel),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        showTunnelEditor(context, ref, hostId: hostId);
                      },
                      child: Text(l.newEllipsis),
                    ),
                  ],
                ),
              ),
              for (final t in board.ofHost(hostId))
                ListTile(
                  dense: true,
                  leading: Switch(
                    value:
                        t.state == TunnelStateKind.open ||
                        t.state == TunnelStateKind.opening,
                    onChanged: (on) =>
                        on ? openTunnel(context, ref, t) : board.close(t.id),
                  ),
                  title: Text(
                    t.spec.label,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    forwardText(t),
                    style: monoStyle(context, size: 12),
                  ),
                  trailing:
                      t.state == TunnelStateKind.open &&
                          t.spec.kind != TunnelKind.remote
                      ? TextButton(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: 'localhost:${t.port}'),
                          ),
                          child: Text(l.copyAddress),
                        )
                      : Text(
                          stateText(l, t),
                          style: TextStyle(
                            fontSize: 12,
                            color: t.state == TunnelStateKind.failed
                                ? c.danger
                                : c.textMuted,
                          ),
                        ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Text(
                  l.tunnelsStayOpen,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Over a terminal: the host's tunnels that did not open as it connected.
class TunnelNotices extends ConsumerStatefulWidget {
  const TunnelNotices({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<TunnelNotices> createState() => _TunnelNoticesState();
}

class _TunnelNoticesState extends ConsumerState<TunnelNotices> {
  late final TunnelBoard _board = ref.read(tunnelBoardProvider);

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) {
        final failed = [
          for (final t in _board.ofHost(widget.hostId))
            if (t.state == TunnelStateKind.failed && t.onConnect) t,
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Callout(
                  tone: Tone.warn,
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: c.warn,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.tunnelDidNotOpen(
                            t.spec.label,
                            tunnelErrorText(l, t),
                          ),
                          style: TextStyle(color: c.text),
                        ),
                      ),
                      if (_details(t) case final e?) DetailsButton(e),
                      if (suggestedPort(ref, t) case final port?)
                        OutlinedButton(
                          onPressed: () => useOtherPort(context, ref, t, port),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            side: BorderSide(color: c.warnLine),
                          ),
                          child: Text(l.usePort(port)),
                        ),
                      TextButton(
                        onPressed: () => _board.close(t.id),
                        child: Text(l.ignore),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
