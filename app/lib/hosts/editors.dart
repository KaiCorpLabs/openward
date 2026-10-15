import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Creates (no `id`) or edits a host, in a panel on the right of the
/// window. True if something was saved.
Future<bool> showHostEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? groupId,
}) => showSidePanel(context, (_) => _HostEditor(id: id, groupId: groupId));

/// Creates (no `id`) or edits a group. True if something was saved.
Future<bool> showGroupEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? parentId,
}) => showSidePanel(context, (_) => _GroupEditor(id: id, parentId: parentId));

/// A panel on the right of the window, as editors open. True if it
/// closed saying something was saved.
Future<bool> showSidePanel(BuildContext context, WidgetBuilder builder) async {
  final ow = context.ow;
  final still = MediaQuery.of(context).disableAnimations;
  final saved = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: ow.colors.scrim,
    transitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 560,
        height: double.infinity,
        child: Material(
          color: ow.colors.raised,
          shape: Border(left: BorderSide(color: ow.colors.control)),
          elevation: 12,
          child: builder(context),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
  return saved ?? false;
}

/// Group names with their path, for pickers: `prod / eu`.
List<(String, String)> _groupChoices(Library library, {String? excluding}) {
  final out = <(String, String)>[];
  void walk(String? parent, String prefix) {
    for (final g in library.groupsIn(parent)) {
      if (g.id == excluding) continue;
      final name = prefix.isEmpty ? g.name : '$prefix / ${g.name}';
      out.add((g.id, name));
      walk(g.id, name);
    }
  }

  walk(null, '');
  return out;
}

/// The connection settings a host or group may set. A field is either set
/// here or inherited; [setHere] says which.
class _SettingsForm {
  _SettingsForm(this.original)
    : user = TextEditingController(text: original.user ?? ''),
      port = TextEditingController(text: original.port?.toString() ?? ''),
      keys = TextEditingController(
        text: (original.identityFiles ?? const []).join('\n'),
      ),
      socket = TextEditingController(text: original.agentSocket),
      command = TextEditingController(text: original.proxyCommand),
      proxyHost = TextEditingController(text: original.proxyHost),
      proxyPort = TextEditingController(
        text: original.proxyPort == 0 ? '' : '${original.proxyPort}',
      ),
      proxyUser = TextEditingController(text: original.proxyUser),
      proxy = original.proxy,
      agent = original.agent,
      route = original.route,
      policy = original.hostKeyPolicy,
      jumps = [...original.jumps],
      setHere = {
        if (original.user != null) 'user',
        if (original.port != null) 'port',
        if (original.identityFiles != null) 'identity_files',
        if (original.agent != null) 'agent',
        if (original.route != null) 'route',
        if (original.proxy != null) 'proxy',
        if (original.hostKeyPolicy != null) 'host_key_policy',
      };

  final SettingsSpec original;
  final TextEditingController user, port, keys, socket, command;
  final TextEditingController proxyHost, proxyPort, proxyUser;
  AgentKind? agent;
  RouteKind? route;
  ProxyKind? proxy;
  KeyPolicy? policy;

  /// The jump chain, first hop first.
  final List<JumpSpec> jumps;
  final TextEditingController jumpAddress = TextEditingController();

  /// Fields this item sets itself, by their vault name.
  final Set<String> setHere;

  void dispose() {
    for (final c in [
      user,
      port,
      keys,
      socket,
      command,
      jumpAddress,
      proxyHost,
      proxyPort,
      proxyUser,
    ]) {
      c.dispose();
    }
  }

  /// Starts setting `field` here, from the value it inherits.
  void take(String field, SettingsSpec inherited) {
    setHere.add(field);
    switch (field) {
      case 'user':
        user.text = inherited.user ?? '';
      case 'port':
        port.text = '${inherited.port ?? 22}';
      case 'identity_files':
        keys.text = (inherited.identityFiles ?? const []).join('\n');
      case 'agent':
        agent = inherited.agent ?? AgentKind.system;
        socket.text = inherited.agentSocket;
      case 'route':
        route = inherited.route ?? RouteKind.direct;
        jumps
          ..clear()
          ..addAll(inherited.jumps);
        command.text = inherited.proxyCommand;
      case 'proxy':
        proxy = inherited.proxy ?? ProxyKind.off;
        proxyHost.text = inherited.proxyHost;
        proxyPort.text = inherited.proxyPort == 0
            ? ''
            : '${inherited.proxyPort}';
        proxyUser.text = inherited.proxyUser;
      case 'host_key_policy':
        policy = inherited.hostKeyPolicy ?? KeyPolicy.ask;
    }
  }

  /// Goes back to inheriting `field`.
  void drop(String field) {
    setHere.remove(field);
    switch (field) {
      case 'user':
        user.clear();
      case 'port':
        port.clear();
      case 'identity_files':
        keys.clear();
      case 'agent':
        agent = null;
        socket.clear();
      case 'route':
        route = null;
        jumps.clear();
        command.clear();
      case 'proxy':
        proxy = null;
        proxyHost.clear();
        proxyPort.clear();
        proxyUser.clear();
      case 'host_key_policy':
        policy = null;
    }
  }

  /// A proxy server is in use (not "none", not inherited).
  bool get proxyServer =>
      setHere.contains('proxy') &&
      (proxy == ProxyKind.http || proxy == ProxyKind.socks5);

  String? validate(AppLocalizations l) {
    final p = port.text.trim();
    if (setHere.contains('port') && p.isNotEmpty) {
      final n = int.tryParse(p);
      if (n == null || n < 1 || n > 65535) return l.portRange;
    }
    if (agent == AgentKind.socket && socket.text.trim().isEmpty) {
      return l.missingSocket;
    }
    if (route == RouteKind.jump && jumps.isEmpty) return l.missingJump;
    if (route == RouteKind.command && command.text.trim().isEmpty) {
      return l.missingProxyCommand;
    }
    if (proxyServer) {
      final n = int.tryParse(proxyPort.text.trim());
      if (proxyHost.text.trim().isEmpty || n == null || n < 1 || n > 65535) {
        return l.missingProxy;
      }
    }
    return null;
  }

  SettingsSpec toSpec() {
    String? text(String field, TextEditingController c) =>
        setHere.contains(field) && c.text.trim().isNotEmpty
        ? c.text.trim()
        : null;
    final files = (text('identity_files', keys) ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final r = setHere.contains('route') ? route : null;
    final a = setHere.contains('agent') ? agent : null;
    return SettingsSpec(
      user: text('user', user),
      port: int.tryParse(text('port', port) ?? ''),
      identityFiles: files.isEmpty ? null : files,
      certificateFiles: original.certificateFiles,
      identitiesOnly: original.identitiesOnly,
      agent: a,
      agentSocket: a == AgentKind.socket ? socket.text.trim() : '',
      route: r,
      jumps: r == RouteKind.jump ? jumps : const [],
      proxyCommand: r == RouteKind.command ? command.text.trim() : '',
      proxy: setHere.contains('proxy') ? proxy : null,
      proxyHost: proxyServer ? proxyHost.text.trim() : '',
      proxyPort: proxyServer ? int.tryParse(proxyPort.text.trim()) ?? 0 : 0,
      proxyUser: proxyServer ? proxyUser.text.trim() : '',
      keepaliveSecs: original.keepaliveSecs,
      agentForward: original.agentForward,
      term: original.term,
      env: original.env,
      hostKeyPolicy: setHere.contains('host_key_policy') ? policy : null,
    );
  }
}

/// The connection settings, each set here or inherited, and where the
/// inherited ones come from.
class _SettingsFields extends ConsumerStatefulWidget {
  const _SettingsFields({
    required this.form,
    required this.hosts,
    required this.inherited,
  });

  final _SettingsForm form;

  /// Hosts that can be jumped through: (id, label).
  final List<(String, String)> hosts;
  final InheritedView inherited;

  @override
  ConsumerState<_SettingsFields> createState() => _SettingsFieldsState();
}

class _SettingsFieldsState extends ConsumerState<_SettingsFields> {
  bool _more = false;

  _SettingsForm get f => widget.form;
  SettingsSpec get _from => widget.inherited.effective;

  String _hostLabel(String id) {
    for (final (hid, label) in widget.hosts) {
      if (hid == id) return label;
    }
    return ref.read(libraryProvider).host(id)?.label ??
        context.l10n.deletedHost;
  }

  String _jumpLabel(JumpSpec j) {
    final id = j.hostId;
    if (id != null) return _hostLabel(id);
    return QuickTarget(
      address: j.address ?? '',
      user: j.user,
      port: j.port,
    ).label;
  }

  /// Where an inherited value comes from, in words.
  String _origin(String field) {
    final l = context.l10n;
    final o = widget.inherited.origins
        .where((o) => o.field == field)
        .firstOrNull;
    return switch (o?.origin) {
      OriginKind.group => l.fromGroup(
        ref.read(libraryProvider).group(o!.groupId ?? '')?.name ?? '',
      ),
      OriginKind.default_ => l.fromDefault,
      _ => l.fromNowhere,
    };
  }

  /// What `field` inherits, as text.
  String _inheritedValue(String field) {
    final l = context.l10n;
    final e = _from;
    return switch (field) {
      'user' => e.user ?? l.localUser,
      'port' => '${e.port ?? 22}',
      'identity_files' => e.identityFiles?.join(', ') ?? l.defaultKeys,
      'agent' => switch (e.agent) {
        AgentKind.off => l.agentNone,
        AgentKind.socket => e.agentSocket,
        _ => l.agentSystem,
      },
      'route' => switch (e.route) {
        RouteKind.jump => l.jumpVia(e.jumps.map(_jumpLabel).join(' → ')),
        RouteKind.command => 'ProxyCommand: ${e.proxyCommand}',
        _ => l.routeDirect,
      },
      'proxy' => switch (e.proxy) {
        ProxyKind.http => 'HTTP ${e.proxyHost}:${e.proxyPort}',
        ProxyKind.socks5 => 'SOCKS5 ${e.proxyHost}:${e.proxyPort}',
        _ => l.proxyNone,
      },
      'host_key_policy' => _policy(l, e.hostKeyPolicy ?? KeyPolicy.ask),
      _ => '',
    };
  }

  /// "este equipo → proxy → first hop…" with what the form says now.
  String _proxyRoute(AppLocalizations l) {
    final route = f.setHere.contains('route') ? f.route : _from.route;
    final jumps = f.setHere.contains('route') ? f.jumps : _from.jumps;
    final proxy = '${f.proxyHost.text.trim()}:${f.proxyPort.text.trim()}';
    return [
      l.routeStart,
      proxy,
      if (route == RouteKind.jump) ...jumps.map(_jumpLabel),
      l.theHost,
    ].join(' → ');
  }

  String _policy(AppLocalizations l, KeyPolicy p) => switch (p) {
    KeyPolicy.ask => l.policyAsk,
    KeyPolicy.acceptNew => l.policyAcceptNew,
    KeyPolicy.strict => l.policyStrict,
  };

  Widget _row({
    required String field,
    required String label,
    required Widget editor,
    bool mono = false,
  }) {
    final set = f.setHere.contains(field);
    return _SettingRow(
      label: label,
      isSet: set,
      editor: editor,
      inherited: _inheritedValue(field),
      mono: mono,
      note: set
          ? context.l10n.setHereWouldInherit(_inheritedValue(field))
          : _origin(field),
      onChange: () => setState(() => f.take(field, _from)),
      onClear: () => setState(() => f.drop(field)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          field: 'user',
          label: l.user,
          mono: true,
          editor: TextField(
            key: const ValueKey('settings.user'),
            controller: f.user,
            style: monoStyle(context, size: 13, color: ow.colors.text),
          ),
        ),
        _row(
          field: 'port',
          label: l.port,
          mono: true,
          editor: TextField(
            key: const ValueKey('settings.port'),
            controller: f.port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: monoStyle(context, size: 13, color: ow.colors.text),
          ),
        ),
        _row(
          field: 'identity_files',
          label: l.keys,
          mono: true,
          editor: TextField(
            key: const ValueKey('settings.keys'),
            controller: f.keys,
            minLines: 1,
            maxLines: 4,
            style: monoStyle(context, size: 13, color: ow.colors.text),
            decoration: InputDecoration(helperText: l.keysHelp),
          ),
        ),
        _row(
          field: 'route',
          label: l.route,
          editor: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<RouteKind>(
                style: fieldTextStyle(context),
                key: const ValueKey('settings.route'),
                initialValue: f.route ?? RouteKind.direct,
                items: [
                  DropdownMenuItem(
                    value: RouteKind.direct,
                    child: Text(l.routeDirect),
                  ),
                  DropdownMenuItem(
                    value: RouteKind.jump,
                    child: Text(l.routeJump),
                  ),
                  const DropdownMenuItem(
                    value: RouteKind.command,
                    child: Text('ProxyCommand'),
                  ),
                ],
                onChanged: (v) => setState(() => f.route = v),
              ),
              if (f.route == RouteKind.jump) ...[
                const SizedBox(height: 10),
                _JumpChain(
                  jumps: f.jumps,
                  hosts: widget.hosts,
                  address: f.jumpAddress,
                  label: _jumpLabel,
                  onChanged: () => setState(() {}),
                ),
              ],
              if (f.route == RouteKind.command) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: f.command,
                  style: monoStyle(context, size: 13, color: ow.colors.text),
                  decoration: const InputDecoration(
                    hintText: 'cloudflared access ssh --hostname %h',
                  ),
                ),
              ],
            ],
          ),
        ),
        _row(
          field: 'proxy',
          label: l.proxy,
          editor: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ProxyKind>(
                style: fieldTextStyle(context),
                key: const ValueKey('settings.proxy'),
                initialValue: f.proxy ?? ProxyKind.off,
                items: [
                  DropdownMenuItem(
                    value: ProxyKind.off,
                    child: Text(l.proxyNone),
                  ),
                  const DropdownMenuItem(
                    value: ProxyKind.http,
                    child: Text('HTTP (CONNECT)'),
                  ),
                  const DropdownMenuItem(
                    value: ProxyKind.socks5,
                    child: Text('SOCKS5'),
                  ),
                ],
                onChanged: (v) => setState(() => f.proxy = v),
              ),
              if (f.proxyServer) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('settings.proxyHost'),
                        controller: f.proxyHost,
                        onChanged: (_) => setState(() {}),
                        style: monoStyle(
                          context,
                          size: 13,
                          color: ow.colors.text,
                        ),
                        decoration: InputDecoration(labelText: l.proxyServer),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        key: const ValueKey('settings.proxyPort'),
                        controller: f.proxyPort,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: monoStyle(
                          context,
                          size: 13,
                          color: ow.colors.text,
                        ),
                        decoration: InputDecoration(labelText: l.port),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('settings.proxyUser'),
                  controller: f.proxyUser,
                  style: monoStyle(context, size: 13, color: ow.colors.text),
                  decoration: InputDecoration(
                    labelText: l.proxyUser,
                    helperText: l.proxyUserHelp,
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l.proxyRouteTitle,
                  style: TextStyle(fontSize: 12, color: ow.colors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  _proxyRoute(l),
                  style: monoStyle(context, size: 12, color: ow.colors.text),
                ),
                if ((f.setHere.contains('route') ? f.route : _from.route) ==
                    RouteKind.command) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.proxyNotWithCommand,
                    style: TextStyle(fontSize: 12, color: ow.colors.warn),
                  ),
                ],
                if (f.proxy == ProxyKind.http) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.proxyHttpNote,
                    style: TextStyle(fontSize: 12, color: ow.colors.textMuted),
                  ),
                ],
              ],
            ],
          ),
        ),
        _row(
          field: 'host_key_policy',
          label: l.hostKeys,
          editor: DropdownButtonFormField<KeyPolicy>(
            style: fieldTextStyle(context),
            key: const ValueKey('settings.policy'),
            initialValue: f.policy ?? KeyPolicy.ask,
            items: [
              for (final p in KeyPolicy.values)
                DropdownMenuItem(value: p, child: Text(_policy(l, p))),
            ],
            onChanged: (v) => setState(() => f.policy = v),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _more = !_more),
            style: TextButton.styleFrom(foregroundColor: ow.colors.textMuted),
            icon: Icon(
              _more ? Icons.expand_more : Icons.chevron_right,
              size: 16,
            ),
            label: Text(l.moreOptions),
          ),
        ),
        if (_more)
          _row(
            field: 'agent',
            label: l.agent,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<AgentKind>(
                  style: fieldTextStyle(context),
                  initialValue: f.agent ?? AgentKind.system,
                  items: [
                    DropdownMenuItem(
                      value: AgentKind.system,
                      child: Text(l.agentSystem),
                    ),
                    DropdownMenuItem(
                      value: AgentKind.off,
                      child: Text(l.agentNone),
                    ),
                    DropdownMenuItem(
                      value: AgentKind.socket,
                      child: Text(l.agentSocket),
                    ),
                  ],
                  onChanged: (v) => setState(() => f.agent = v),
                ),
                if (f.agent == AgentKind.socket) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: f.socket,
                    style: monoStyle(context, size: 13, color: ow.colors.text),
                    decoration: const InputDecoration(
                      hintText: '~/Library/Group Containers/…/agent.sock',
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One setting: its own editor when set here, or the inherited value in a
/// dashed box; under it, where the value comes from.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.isSet,
    required this.editor,
    required this.inherited,
    required this.note,
    required this.onChange,
    required this.onClear,
    this.mono = false,
  });

  final String label;
  final bool isSet;
  final Widget editor;
  final String inherited;
  final String note;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(label, style: TextStyle(color: c.textMuted)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSet)
                  editor
                else
                  Semantics(
                    label: label,
                    value: inherited,
                    readOnly: true,
                    child: CustomPaint(
                      painter: _DashedBorder(c.control, ow.shape.radius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Text(
                          inherited,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mono
                              ? monoStyle(context, size: 13)
                              : TextStyle(color: c.textMuted),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Row(
                    children: [
                      Icon(
                        isSet
                            ? Icons.edit_outlined
                            : Icons.subdirectory_arrow_right,
                        size: 12,
                        color: isSet ? c.textMuted : c.textSubtle,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSet ? c.textMuted : c.textSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, left: 8),
              child: TextButton(
                onPressed: isSet ? onClear : onChange,
                child: Text(isSet ? l.clear : l.change),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded, dashed outline: an inherited value, not one set here.
class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// The hops in order, each removable, and ways to add one: a saved host or
/// an address.
class _JumpChain extends StatelessWidget {
  const _JumpChain({
    required this.jumps,
    required this.hosts,
    required this.address,
    required this.label,
    required this.onChanged,
  });

  final List<JumpSpec> jumps;
  final List<(String, String)> hosts;
  final TextEditingController address;
  final String Function(JumpSpec) label;
  final VoidCallback onChanged;

  void _addAddress() {
    final j = parseJumpAddress(address.text);
    if (j == null) return;
    jumps.add(j);
    address.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.jumpThrough, style: TextStyle(fontSize: 12, color: c.textMuted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < jumps.length; i++) ...[
              if (i > 0)
                Icon(Icons.arrow_forward, size: 14, color: c.textSubtle),
              InputChip(
                label: Text(label(jumps[i])),
                avatar: Icon(
                  jumps[i].hostId != null ? Icons.dns_outlined : Icons.lan,
                  size: 14,
                ),
                onDeleted: () {
                  jumps.removeAt(i);
                  onChanged();
                },
              ),
            ],
            if (jumps.isEmpty)
              Text(
                l.noJumpsYet,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          style: fieldTextStyle(context),
          key: ValueKey(jumps.length),
          decoration: InputDecoration(hintText: l.addSavedHost),
          items: [
            for (final (id, name) in hosts)
              DropdownMenuItem(value: id, child: Text(name)),
          ],
          onChanged: (id) {
            if (id == null) return;
            jumps.add(JumpSpec(hostId: id));
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: address,
          decoration: InputDecoration(
            hintText: l.orAnAddress,
            suffixIcon: IconButton(
              tooltip: l.add,
              icon: const Icon(Icons.add, size: 16),
              onPressed: _addAddress,
            ),
          ),
          onSubmitted: (_) => _addAddress(),
        ),
      ],
    );
  }
}

/// Tags as chips, with a field to add more (Enter or a comma).
class _TagsField extends StatefulWidget {
  const _TagsField({required this.tags});

  final List<String> tags;

  @override
  State<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<_TagsField> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add(String text) {
    final tags = text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !widget.tags.contains(t));
    setState(() {
      widget.tags.addAll(tags);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final l = context.l10n;
    return InputDecorator(
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in widget.tags)
            Container(
              padding: const EdgeInsets.only(left: 7),
              decoration: BoxDecoration(
                color: ow.colors.accentSoft,
                borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t,
                    style: TextStyle(fontSize: 12, color: ow.colors.accentText),
                  ),
                  IconButton(
                    tooltip: l.removeTag(t),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 12,
                    color: ow.colors.accentText,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => widget.tags.remove(t)),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
            child: TextField(
              key: const ValueKey('host.tags'),
              controller: _field,
              decoration: InputDecoration(
                hintText: l.addTag,
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
              ),
              onChanged: (v) {
                if (v.contains(',')) _add(v);
              },
              onSubmitted: _add,
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel: title, the form, and the buttons that close it.
/// An editor in a side panel: a title, what it edits, and save.
class EditorFrame extends StatelessWidget {
  const EditorFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.error,
    required this.onSave,
    required this.children,
    this.onSaveAndConnect,
    this.saveAndConnectLabel,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback? onSaveAndConnect;

  /// The second way to save; "save and connect" by default.
  final String? saveAndConnectLabel;
  final VoidCallback? onDelete;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSave,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onSave,
      },
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.close,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(error!, style: TextStyle(color: c.danger)),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  if (onDelete != null)
                    TextButton(
                      onPressed: onDelete,
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      child: Text(l.delete),
                    ),
                  if (onSaveAndConnect != null)
                    TextButton(
                      onPressed: onSaveAndConnect,
                      child: Text(saveAndConnectLabel ?? l.saveAndConnect),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onSave, child: Text(l.save)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                hint!,
                style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// A field with its label above.
Widget _labelled(BuildContext context, String label, Widget field) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(label, style: TextStyle(color: context.ow.colors.textMuted)),
    const SizedBox(height: 6),
    field,
  ],
);

class _HostEditor extends ConsumerStatefulWidget {
  const _HostEditor({this.id, this.groupId});

  final String? id;
  final String? groupId;

  @override
  ConsumerState<_HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends ConsumerState<_HostEditor> {
  late final HostDetail? _detail = widget.id == null
      ? null
      : ref.read(openWardProvider).host(id: widget.id!);
  late final HostSpec _spec =
      _detail?.spec ??
      HostSpec(label: '', address: '', groupId: widget.groupId);
  late final _label = TextEditingController(text: _spec.label);
  late final _address = TextEditingController(text: _spec.address);
  late final List<String> _tags = [..._spec.tags];
  late final _notes = TextEditingController(text: _spec.notes ?? '');
  late final _settings = _SettingsForm(_spec.settings);
  late String? _group = _spec.groupId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _address, _notes]) {
      c.dispose();
    }
    _settings.dispose();
    super.dispose();
  }

  Future<void> _save({bool connect = false}) async {
    final l = context.l10n;
    final label = _label.text.trim();
    final address = _address.text.trim();
    final problem = label.isEmpty
        ? l.hostNeedsName
        : address.isEmpty
        ? l.missingAddress
        : _settings.validate(l);
    if (problem != null) return setState(() => _error = problem);
    final spec = HostSpec(
      label: label,
      address: address,
      groupId: _group,
      tags: _tags,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      settings: _settings.toSpec(),
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      final String id;
      if (d == null) {
        id = await app.createHost(spec: spec);
      } else {
        await app.updateHost(id: d.id, rev: d.rev, spec: spec);
        id = d.id;
      }
      if (connect) {
        ref.read(libraryProvider.notifier).refresh();
        final host = ref.read(libraryProvider).host(id);
        if (host != null) ref.read(tabsProvider.notifier).openHost(host);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(
        () => _error = '$e'.contains('changed since')
            ? l.changedMeanwhile
            : l.saveFailed('$e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final groups = _groupChoices(library);
    final inherited = ref.read(openWardProvider).inherited(groupId: _group);
    final groupName = _group == null ? null : library.group(_group!)?.name;
    final mono = monoStyle(context, size: 13, color: context.ow.colors.text);
    return EditorFrame(
      title: _detail == null ? l.newHostTitle : l.editHostTitle,
      subtitle: [
        if (_spec.label.isNotEmpty) _spec.label,
        if (groupName != null) l.inGroup(groupName),
      ].join(' · ').ifEmpty,
      error: _error,
      onSave: _save,
      onSaveAndConnect: () => _save(connect: true),
      children: [
        _Section(l.sectionGeneral),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labelled(
                context,
                l.name,
                TextField(
                  key: const ValueKey('host.label'),
                  controller: _label,
                  autofocus: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labelled(
                context,
                l.address,
                TextField(
                  key: const ValueKey('host.address'),
                  controller: _address,
                  style: mono,
                  decoration: InputDecoration(hintText: l.addressHint),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labelled(
                context,
                l.group,
                DropdownButtonFormField<String?>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('host.group'),
                  initialValue: _group,
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.noGroup)),
                    for (final (id, name) in groups)
                      DropdownMenuItem(value: id, child: Text(name)),
                  ],
                  onChanged: (v) => setState(() => _group = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labelled(context, l.tags, _TagsField(tags: _tags)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(l.sectionConnection, hint: l.connectionHint),
        _SettingsFields(
          form: _settings,
          hosts: [
            for (final h in library.hosts)
              if (h.id != widget.id) (h.id, h.label),
          ],
          inherited: inherited,
        ),
        const SizedBox(height: 8),
        _labelled(
          context,
          l.notes,
          TextField(controller: _notes, minLines: 2, maxLines: 5),
        ),
      ],
    );
  }
}

class _GroupEditor extends ConsumerStatefulWidget {
  const _GroupEditor({this.id, this.parentId});

  final String? id;
  final String? parentId;

  @override
  ConsumerState<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends ConsumerState<_GroupEditor> {
  late final GroupDetail? _detail = widget.id == null
      ? null
      : ref.read(openWardProvider).group(id: widget.id!);
  late final GroupSpec _spec =
      _detail?.spec ?? GroupSpec(name: '', parentId: widget.parentId);
  late final _name = TextEditingController(text: _spec.name);
  late final _settings = _SettingsForm(_spec.settings);
  late String? _parent = _spec.parentId;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim();
    final problem = name.isEmpty ? l.groupNeedsName : _settings.validate(l);
    if (problem != null) return setState(() => _error = problem);
    final spec = GroupSpec(
      name: name,
      parentId: _parent,
      settings: _settings.toSpec(),
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      if (d == null) {
        await app.createGroup(spec: spec);
      } else {
        await app.updateGroup(id: d.id, rev: d.rev, spec: spec);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(
        () => _error = '$e'.contains('inside itself')
            ? l.groupInsideItself
            : l.saveFailed('$e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final inherited = ref.read(openWardProvider).inherited(groupId: _parent);
    return EditorFrame(
      title: _detail == null ? l.newGroupTitle : l.editGroupTitle,
      subtitle: _spec.name.isEmpty ? null : _spec.name,
      error: _error,
      onSave: _save,
      children: [
        _Section(l.sectionGeneral),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labelled(
                context,
                l.name,
                TextField(
                  key: const ValueKey('group.name'),
                  controller: _name,
                  autofocus: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labelled(
                context,
                l.inside,
                DropdownButtonFormField<String?>(
                  style: fieldTextStyle(context),
                  initialValue: _parent,
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.noParent)),
                    for (final (id, name) in _groupChoices(
                      library,
                      excluding: widget.id,
                    ))
                      DropdownMenuItem(value: id, child: Text(name)),
                  ],
                  onChanged: (v) => setState(() => _parent = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(l.groupSettingsSection, hint: l.connectionHint),
        _SettingsFields(
          form: _settings,
          hosts: [for (final h in library.hosts) (h.id, h.label)],
          inherited: inherited,
        ),
      ],
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
