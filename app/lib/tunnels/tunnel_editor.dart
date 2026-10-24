import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/tunnels.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'tunnels.dart';

/// Creates (no `tunnel`) or edits a tunnel in the side panel; `hostId`
/// picks the host of a new one. True if something was saved.
Future<bool> showTunnelEditor(
  BuildContext context,
  WidgetRef ref, {
  TunnelView? tunnel,
  String? hostId,
}) => showSidePanel(
  context,
  (_) => _TunnelEditor(tunnel: tunnel, hostId: hostId),
);

class _TunnelEditor extends ConsumerStatefulWidget {
  const _TunnelEditor({this.tunnel, this.hostId});

  final TunnelView? tunnel;
  final String? hostId;

  @override
  ConsumerState<_TunnelEditor> createState() => _TunnelEditorState();
}

class _TunnelEditorState extends ConsumerState<_TunnelEditor> {
  late final TunnelSpec? _old = widget.tunnel?.spec;
  late final _label = TextEditingController(text: _old?.label ?? '');
  late final _listen = TextEditingController(
    text: _old == null ? '' : '${_old.listenPort}',
  );
  late final _dest = TextEditingController(text: _old?.destHost ?? 'localhost');
  late final _destPort = TextEditingController(
    text: _old?.destPort?.toString() ?? '',
  );
  late String? _host = _old?.hostId ?? widget.hostId;
  late TunnelKind _kind = _old?.kind ?? TunnelKind.local;
  late bool _lan = (_old?.listenAddress ?? '').isNotEmpty;
  late bool _autostart = _old?.autostart ?? false;
  String? _error;
  Object? _cause;

  String _snapshot() => [
    _label.text,
    _listen.text,
    _dest.text,
    _destPort.text,
    _host,
    _kind,
    _lan,
    _autostart,
  ].join('\u0000');

  @override
  void dispose() {
    for (final c in [_label, _listen, _dest, _destPort]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _port(TextEditingController c) {
    final n = int.tryParse(c.text.trim());
    return n == null || n < 1 || n > 65535 ? null : n;
  }

  String? _validate(AppLocalizations l) {
    if (_label.text.trim().isEmpty) return l.tunnelNeedsName;
    if (_host == null) return l.tunnelNeedsHost;
    if (_port(_listen) == null) return l.portRange;
    if (_kind != TunnelKind.dynamic_ &&
        (_dest.text.trim().isEmpty || _port(_destPort) == null)) {
      return l.tunnelNeedsDest;
    }
    return null;
  }

  TunnelSpec _spec() => TunnelSpec(
    label: _label.text.trim(),
    hostId: _host!,
    kind: _kind,
    listenPort: _port(_listen)!,
    listenAddress: _lan ? '0.0.0.0' : null,
    destHost: _kind == TunnelKind.dynamic_ ? null : _dest.text.trim(),
    destPort: _kind == TunnelKind.dynamic_ ? null : _port(_destPort),
    autostart: _autostart,
  );

  Future<void> _save({bool open = false}) async {
    final l = context.l10n;
    _cause = null;
    final problem = _validate(l);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final app = ref.read(openWardProvider);
    final board = ref.read(tunnelBoardProvider);
    final old = widget.tunnel;
    try {
      final String id;
      if (old == null) {
        id = await app.createTunnel(spec: _spec());
      } else {
        await app.updateTunnel(id: old.id, rev: old.rev, spec: _spec());
        id = old.id;
      }
      board.refresh();
      if (!mounted) return;
      Navigator.pop(context, true);
      final saved = board.byId(id);
      if (open && saved != null && context.mounted) {
        await openTunnel(context, ref, saved);
      }
    } catch (e) {
      setState(() {
        _error = saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  /// Deletes it at once (closing it, if open); the notice that says so
  /// can bring it back, closed.
  Future<void> _delete() async {
    final t = widget.tunnel;
    if (t == null) return;
    final l = context.l10n;
    final app = ref.read(openWardProvider);
    final board = ref.read(tunnelBoardProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.delete(id: t.id);
    } catch (e) {
      return setState(() {
        _error = l.deleteFailed(errorReason(l, e));
        _cause = e;
      });
    }
    board.refresh();
    if (mounted) Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.tunnelDeleted(t.spec.label)),
        action: SnackBarAction(
          label: l.undo,
          onPressed: () async {
            try {
              await app.createTunnel(spec: t.spec);
            } catch (e) {
              showErrorNotice(messenger, saveErrorText(l, e), e);
            }
            board.refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final hostLabel = _host == null
        ? l.theHost
        : library.host(_host!)?.label ?? l.theHost;
    final mono = monoStyle(context, size: 13, color: c.text);
    final listenPort = _port(_listen);
    // Taken right now, here (remote ones listen on the server).
    final busy =
        _kind != TunnelKind.remote &&
        listenPort != null &&
        widget.tunnel?.port != listenPort &&
        ref.read(openWardProvider).freePortNear(port: listenPort - 1) !=
            listenPort;
    Widget labelled(String text, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(color: c.textMuted, fontSize: OwText.small),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
    final remote = _kind == TunnelKind.remote;
    return EditorFrame(
      title: widget.tunnel == null ? l.newTunnel : l.editTunnel,
      subtitle: l.tunnelEditorHint,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      onSaveAndConnect: () => _save(open: true),
      saveAndConnectLabel: l.saveAndOpen,
      onDelete: widget.tunnel == null ? null : _delete,
      snapshot: _snapshot,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: labelled(
                l.name,
                TextField(
                  key: const ValueKey('tunnel.label'),
                  controller: _label,
                  autofocus: widget.tunnel == null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelled(
                l.host,
                DropdownButtonFormField<String>(
                  key: const ValueKey('tunnel.host'),
                  style: fieldTextStyle(context),
                  isExpanded: true,
                  initialValue: _host,
                  items: [
                    for (final h in library.hosts)
                      DropdownMenuItem(
                        value: h.id,
                        child: Text(h.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _host = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        labelled(
          l.tunnelType,
          SegmentedButton<TunnelKind>(
            key: const ValueKey('tunnel.kind'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: TunnelKind.local, label: Text(l.kindLocal)),
              ButtonSegment(
                value: TunnelKind.remote,
                label: Text(l.kindRemote),
              ),
              ButtonSegment(
                value: TunnelKind.dynamic_,
                label: Text(l.kindDynamic),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        const SizedBox(height: 14),
        TunnelDiagram(
          kind: _kind,
          host: hostLabel,
          listen: _listen.text.trim(),
          dest: '${_dest.text.trim()}:${_destPort.text.trim()}',
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: labelled(
                remote ? l.portOnHost(hostLabel) : l.portHere,
                TextField(
                  key: const ValueKey('tunnel.listen'),
                  controller: _listen,
                  style: mono,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    helperText: busy ? l.portBusyNow : null,
                    helperStyle: TextStyle(color: c.warn),
                  ),
                ),
              ),
            ),
            if (_kind != TunnelKind.dynamic_) ...[
              const SizedBox(width: 12),
              Expanded(
                child: labelled(
                  l.destination,
                  TextField(
                    key: const ValueKey('tunnel.dest'),
                    controller: _dest,
                    style: mono,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      helperText: remote
                          ? l.seenFromHere
                          : l.seenFrom(hostLabel),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: labelled(
                  l.itsPort,
                  TextField(
                    key: const ValueKey('tunnel.destPort'),
                    controller: _destPort,
                    style: mono,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        labelled(
          l.whoCanUse,
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(remote ? l.onlyTheServer : l.onlyThisComputer),
              ),
              ButtonSegment(
                value: true,
                label: Text(remote ? l.theServerNetwork : l.theLocalNetwork),
              ),
            ],
            selected: {_lan},
            onSelectionChanged: (s) => setState(() => _lan = s.first),
          ),
        ),
        if (_lan)
          Padding(
            padding: const EdgeInsets.only(top: OwSpace.s4),
            child: Text(
              remote ? l.lanRemoteNote : l.lanLocalNote,
              style: TextStyle(fontSize: OwText.small, color: c.warn),
            ),
          ),
        const SizedBox(height: 16),
        Material(
          color: c.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radius + 2),
          ),
          child: SwitchListTile(
            key: const ValueKey('tunnel.autostart'),
            value: _autostart,
            onChanged: (v) => setState(() => _autostart = v),
            title: Text(l.openOnConnect(hostLabel)),
            subtitle: Text(l.openOnConnectNote),
          ),
        ),
      ],
    );
  }
}

/// What a tunnel does, drawn: where it listens, the SSH hop, where it
/// leads.
class TunnelDiagram extends StatelessWidget {
  const TunnelDiagram({
    super.key,
    required this.kind,
    required this.host,
    required this.listen,
    required this.dest,
  });

  final TunnelKind kind;
  final String host;
  final String listen;
  final String dest;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    Widget node(IconData icon, String title, String sub) => SizedBox(
      width: 118,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.raised,
              border: Border.all(color: c.control),
              borderRadius: BorderRadius.circular(ow.shape.radius + 2),
            ),
            child: Icon(icon, size: 18, color: c.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: OwText.small,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: 12, color: c.accentText),
          ),
        ],
      ),
    );
    Widget arrow(String text) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: OwSpace.s15),
        child: Column(
          children: [
            Text(
              text,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Container(height: 2, color: c.accent)),
                Icon(Icons.arrow_forward_ios, size: 10, color: c.accent),
              ],
            ),
          ],
        ),
      ),
    );
    final here = listen.isEmpty ? '' : 'localhost:$listen';
    final (List<Widget> row, String sentence) = switch (kind) {
      TunnelKind.local => (
        [
          node(Icons.laptop_mac, l.thisComputer, here),
          arrow(l.bySsh),
          node(Icons.dns_outlined, host, ''),
          arrow(l.fromThere),
          node(Icons.public, l.destination, dest),
        ],
        l.localSentence(here, dest, host),
      ),
      TunnelKind.remote => (
        [
          node(Icons.dns_outlined, host, listen.isEmpty ? '' : ':$listen'),
          arrow(l.bySsh),
          node(Icons.laptop_mac, l.thisComputer, ''),
          arrow(l.fromHere),
          node(Icons.public, l.destination, dest),
        ],
        l.remoteSentence(host, listen, dest),
      ),
      TunnelKind.dynamic_ => (
        [
          node(Icons.laptop_mac, l.thisComputer, here),
          arrow(l.bySsh),
          node(Icons.dns_outlined, host, ''),
          arrow(l.fromThere),
          node(Icons.public, l.anyDestination, ''),
        ],
        l.dynamicSentence(here, host),
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s7,
        OwSpace.s8,
        OwSpace.s7,
        OwSpace.s6,
      ),
      decoration: BoxDecoration(
        color: c.sunken,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Column(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: row),
          const SizedBox(height: 4),
          Text(
            sentence,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: OwText.small,
              color: c.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
