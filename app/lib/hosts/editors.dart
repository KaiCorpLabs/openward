import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/errors.dart';
import '../core/providers.dart';
import '../identities/identities.dart';
import '../identities/identity_editor.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../ui/confirm.dart';
import '../ui/environment.dart';
import '../ui/keep_focus.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Creates (no `id`) or edits a host, in a panel on the right of the
/// window. True if something was saved. A new host may start from a
/// `draft` (an address typed in the quick connection, say).
Future<bool> showHostEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? groupId,
  HostSpec? draft,
}) => showSidePanel(
  context,
  (_) => _HostEditor(id: id, groupId: groupId, draft: draft),
);

/// Creates (no `id`) or edits a group. True if something was saved.
Future<bool> showGroupEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? parentId,
}) => showSidePanel(context, (_) => _GroupEditor(id: id, parentId: parentId));

/// A panel on the right of the window, as editors open. True if it
/// closed saying something was saved.
Future<bool> showSidePanel(
  BuildContext context,
  WidgetBuilder builder, {
  double width = 560,
}) async {
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
        width: width,
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
      legacyHostKeys = original.legacyHostKeys,
      persistent = original.persistentSession,
      keepalive = original.keepaliveSecs,
      connectTimeout = original.connectTimeoutSecs,
      identity = original.identity,
      identityId = original.identityId,
      envKind = original.environment,
      envName = original.environmentName,
      envShort = original.environmentShort,
      envColor = original.environmentColor,
      readOsRelease = original.readOsRelease,
      jumps = [...original.jumps],
      setHere = {
        if (original.identity != null) 'identity',
        if (original.user != null) 'user',
        if (original.port != null) 'port',
        if (original.identityFiles != null) 'identity_files',
        if (original.agent != null) 'agent',
        if (original.route != null) 'route',
        if (original.proxy != null) 'proxy',
        if (original.hostKeyPolicy != null) 'host_key_policy',
        if (original.legacyHostKeys != null) 'legacy_host_keys',
        if (original.persistentSession != null) 'persistent_session',
        if (original.keepaliveSecs != null) 'keepalive_secs',
        if (original.connectTimeoutSecs != null) 'connect_timeout_secs',
        if (original.environment != null) 'environment',
        if (original.readOsRelease != null) 'read_os_release',
      };

  final SettingsSpec original;
  final TextEditingController user, port, keys, socket, command;
  final TextEditingController proxyHost, proxyPort, proxyUser;
  AgentKind? agent;
  RouteKind? route;
  ProxyKind? proxy;
  KeyPolicy? policy;
  bool? legacyHostKeys;
  IdentityChoice? identity;
  bool? persistent;
  int? keepalive;
  int? connectTimeout;

  /// With [IdentityChoice.use].
  String identityId;

  /// The mark: none, or the one in [envName], [envShort] and [envColor].
  EnvironmentKind? envKind;
  String envName, envShort, envColor;
  bool? readOsRelease;

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
      case 'legacy_host_keys':
        legacyHostKeys = inherited.legacyHostKeys ?? false;
      case 'identity':
        identity = inherited.identity ?? IdentityChoice.none;
        identityId = inherited.identityId;
      case 'persistent_session':
        persistent = inherited.persistentSession ?? false;
      case 'keepalive_secs':
        keepalive = inherited.keepaliveSecs ?? 10;
      case 'connect_timeout_secs':
        connectTimeout = inherited.connectTimeoutSecs ?? 15;
      case 'environment':
        envKind = inherited.environment ?? EnvironmentKind.none;
        envName = inherited.environmentName;
        envShort = inherited.environmentShort;
        envColor = inherited.environmentColor;
      case 'read_os_release':
        readOsRelease = inherited.readOsRelease ?? false;
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
      case 'legacy_host_keys':
        legacyHostKeys = null;
      case 'identity':
        identity = null;
        identityId = '';
      case 'persistent_session':
        persistent = null;
      case 'keepalive_secs':
        keepalive = null;
      case 'connect_timeout_secs':
        connectTimeout = null;
      case 'environment':
        envKind = null;
        envName = envShort = envColor = '';
      case 'read_os_release':
        readOsRelease = null;
    }
  }

  /// What the form says now, to tell whether it changed.
  String get signature => [
    ...(setHere.toList()..sort()),
    user.text,
    port.text,
    keys.text,
    socket.text,
    command.text,
    proxyHost.text,
    proxyPort.text,
    proxyUser.text,
    jumpAddress.text,
    agent,
    route,
    proxy,
    policy,
    legacyHostKeys,
    identity,
    identityId,
    persistent,
    keepalive,
    connectTimeout,
    envKind,
    envName,
    envShort,
    envColor,
    readOsRelease,
    for (final j in jumps) '${j.hostId}|${j.address}|${j.user}|${j.port}',
  ].join('\u0000');

  /// The mark chosen here, if one is.
  EnvironmentView? get envMark =>
      setHere.contains('environment') && envKind == EnvironmentKind.mark
      ? EnvironmentView(name: envName, short: envShort, color: envColor)
      : null;

  void setEnv(EnvironmentView? mark) {
    envKind = mark == null ? EnvironmentKind.none : EnvironmentKind.mark;
    envName = mark?.name ?? '';
    envShort = mark?.short ?? '';
    envColor = mark?.color ?? '';
  }

  /// The identity choice as the vault would take it, or null to inherit.
  IdentityChoice? get identityChoice =>
      setHere.contains('identity') ? identity : null;

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
    if (identityChoice == IdentityChoice.use && identityId.isEmpty) {
      return l.pickIdentity;
    }
    if (setHere.contains('environment') &&
        envKind == EnvironmentKind.mark &&
        envName.trim().isEmpty) {
      return l.envNeedsName;
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
      keepaliveSecs: setHere.contains('keepalive_secs') ? keepalive : null,
      connectTimeoutSecs: setHere.contains('connect_timeout_secs')
          ? connectTimeout
          : null,
      agentForward: original.agentForward,
      persistentSession: setHere.contains('persistent_session')
          ? persistent
          : null,
      term: original.term,
      env: original.env,
      hostKeyPolicy: setHere.contains('host_key_policy') ? policy : null,
      legacyHostKeys: setHere.contains('legacy_host_keys')
          ? legacyHostKeys
          : null,
      identity: identityChoice,
      identityId: identityChoice == IdentityChoice.use ? identityId : '',
      environment: setHere.contains('environment') ? envKind : null,
      environmentName: envMark?.name ?? '',
      environmentShort: envMark?.short ?? '',
      environmentColor: envMark?.color ?? '',
      readOsRelease: setHere.contains('read_os_release') ? readOsRelease : null,
    );
  }
}

/// The connection settings, each set here or inherited, and where the
/// inherited ones come from.
class _SettingsFields extends ConsumerStatefulWidget {
  const _SettingsFields({
    required this.form,
    required this.hosts,
    required this.groupId,
    required this.connectionTitle,
    this.system,
    this.inheritors,
  });

  final _SettingsForm form;

  /// The title over the connection settings.
  final String connectionTitle;

  /// A host's «Sistema» block (its logo and what told it); reading
  /// os-release goes under it. Groups have none: it goes in «Advanced».
  final Widget? system;

  /// How many hosts a group's settings reach, when it has any.
  final int? inheritors;

  /// Hosts that can be jumped through: (id, label).
  final List<(String, String)> hosts;

  /// Where the item inherits from: its group, or a group's parent.
  final String? groupId;

  @override
  ConsumerState<_SettingsFields> createState() => _SettingsFieldsState();
}

class _SettingsFieldsState extends ConsumerState<_SettingsFields> {
  late bool _more = _advanced.any(widget.form.setHere.contains);

  /// Fields under «Advanced», folded unless one is set here.
  List<String> get _advanced => [
    'proxy',
    'host_key_policy',
    'legacy_host_keys',
    'persistent_session',
    'keepalive_secs',
    'connect_timeout_secs',
    'agent',
    if (widget.system == null) 'read_os_release',
  ];

  _SettingsForm get f => widget.form;

  /// What the item inherits before its own identity choice (for the
  /// identity row), and with it (for the rest).
  late InheritedView _base;
  late InheritedView _inherited;
  SettingsSpec get _from => _inherited.effective;

  void _resolve() {
    final app = ref.read(openWardProvider);
    _base = app.inherited(
      groupId: widget.groupId,
      identity: null,
      identityId: '',
    );
    final choice = f.identityChoice;
    _inherited = choice == null
        ? _base
        : app.inherited(
            groupId: widget.groupId,
            identity: choice,
            identityId: choice == IdentityChoice.use ? f.identityId : '',
          );
  }

  String _identityLabel(String id) =>
      identityById(ref.read(identitiesProvider), id)?.spec.label ??
      context.l10n.deletedIdentity;

  /// The identity in force with what the form says now.
  String? get _identityInForce {
    final choice = f.identityChoice;
    if (choice != null) {
      return choice == IdentityChoice.use && f.identityId.isNotEmpty
          ? f.identityId
          : null;
    }
    final e = _base.effective;
    return e.identity == IdentityChoice.use ? e.identityId : null;
  }

  FieldOrigin? _originOf(String field) =>
      (field == 'identity' ? _base : _inherited).origins
          .where((o) => o.field == field)
          .firstOrNull;

  Future<void> _newIdentity() async {
    final id = await showIdentityEditor(context, ref);
    if (id == null || !mounted) return setState(() {});
    setState(() {
      f.setHere.add('identity');
      f.identity = IdentityChoice.use;
      f.identityId = id;
    });
  }

  Future<void> _editIdentity(String id) async {
    await showIdentityEditor(context, ref, id: id);
    if (mounted) setState(() {});
  }

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
    final o = _originOf(field);
    return switch (o?.origin) {
      OriginKind.group => l.fromGroup(
        ref.read(libraryProvider).group(o!.groupId ?? '')?.name ?? '',
      ),
      OriginKind.identity => l.fromIdentity(
        _identityLabel(o!.identityId ?? ''),
      ),
      OriginKind.default_ => l.fromDefault,
      _ when field == 'identity' => l.noIdentityInherited,
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
      'legacy_host_keys' =>
        e.legacyHostKeys ?? false ? l.legacyHostKeysOn : l.legacyHostKeysOff,
      'persistent_session' =>
        e.persistentSession ?? false ? l.persistentOn : l.persistentOff,
      'keepalive_secs' => _keepalive(l, e.keepaliveSecs ?? 10),
      'connect_timeout_secs' => l.connectTimeoutAfter(
        e.connectTimeoutSecs ?? 15,
      ),
      'identity' =>
        _base.effective.identity == IdentityChoice.use
            ? _identityLabel(_base.effective.identityId)
            : l.identityNone,
      'environment' =>
        e.environment == EnvironmentKind.mark
            ? '${e.environmentShort} · ${e.environmentName}'
            : l.envNone,
      'read_os_release' =>
        e.readOsRelease ?? false ? l.readOsReleaseOn : l.readOsReleaseOff,
      _ => '',
    };
  }

  Widget _osReleaseRow(AppLocalizations l) => _row(
    field: 'read_os_release',
    label: l.readOsRelease,
    editor: DropdownButtonFormField<bool>(
      style: fieldTextStyle(context),
      key: const ValueKey('settings.osRelease'),
      autofocus: focusFor('read_os_release'),
      initialValue: f.readOsRelease ?? false,
      isExpanded: true,
      items: [
        DropdownMenuItem(value: true, child: Text(l.readOsReleaseOn)),
        DropdownMenuItem(value: false, child: Text(l.readOsReleaseOff)),
      ],
      onChanged: (v) => setState(() => f.readOsRelease = v),
    ),
  );

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

  /// `Cada 10 s · perdida a los 20 s`, as the watcher reads it.
  String _keepalive(AppLocalizations l, int secs) => secs == 0
      ? l.keepaliveOff
      : l.keepaliveEvery(secs, secs * 2 < 15 ? 15 : secs * 2);

  static const _keepalives = [5, 10, 15, 30, 60, 0];
  static const _connectTimeouts = [5, 10, 15, 30, 60];

  String _policy(AppLocalizations l, KeyPolicy p) => switch (p) {
    KeyPolicy.ask => l.policyAsk,
    KeyPolicy.acceptNew => l.policyAcceptNew,
    KeyPolicy.strict => l.policyStrict,
  };

  /// The field just set here by a click on its inherited value: its
  /// editor takes the focus as it appears.
  String? _justTook;

  bool focusFor(String field) => _justTook == field;

  Widget _row({
    required String field,
    required String label,
    required Widget editor,
    bool mono = false,
    (String, VoidCallback)? noteAction,
  }) {
    final l = context.l10n;
    final set = f.setHere.contains(field);
    final fromIdentity = _originOf(field)?.origin == OriginKind.identity;
    return _SettingRow(
      field: field,
      label: label,
      isSet: set,
      editor: editor,
      inherited: _inheritedValue(field),
      origin: _origin(field),
      mono: mono,
      note: fromIdentity
          ? l.setHereIdentitySays(_inheritedValue(field))
          : l.setHereWouldInherit(_inheritedValue(field)),
      noteAction: noteAction,
      onChange: () => setState(() {
        f.take(field, field == 'identity' ? _base.effective : _from);
        _justTook = field;
      }),
      onClear: () => setState(() => f.drop(field)),
    );
  }

  Widget _identityPicker(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    const none = '';
    const create = '+';
    final identities = ref.watch(identitiesProvider);
    final value = f.identity == IdentityChoice.use ? f.identityId : none;
    Widget title(String text) => Row(
      children: [
        Icon(Icons.badge_outlined, size: 16, color: c.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
    Widget item(String text, String? sub, {bool warn = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, overflow: TextOverflow.ellipsis),
        if (sub != null)
          Text(
            sub,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: warn ? c.warn : c.textSubtle),
          ),
      ],
    );
    final choices = [
      for (final i in identities)
        (
          i.id,
          i.spec.label,
          missingKeys(i).isEmpty
              ? identitySummary(l, i)
              : l.identityKeyMissingHere(i.spec.user ?? ''),
          missingKeys(i).isNotEmpty,
        ),
      if (value.isNotEmpty && identityById(identities, value) == null)
        (value, l.deletedIdentity, null, true),
      (none, l.identityNone, l.identityNoneNote, false),
      (create, l.newIdentityEllipsis, null, false),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('settings.identity.$value'),
      style: fieldTextStyle(context),
      isExpanded: true,
      itemHeight: null,
      initialValue: value,
      selectedItemBuilder: (context) => [
        for (final (_, text, _, _) in choices) title(text),
      ],
      items: [
        for (final (id, text, sub, warn) in choices)
          DropdownMenuItem(
            value: id,
            child: id == create
                ? Text(text, style: TextStyle(color: c.accentText))
                : item(text, sub, warn: warn),
          ),
      ],
      onChanged: (v) {
        if (v == create) {
          _newIdentity();
        } else {
          setState(() {
            f.identity = v == none ? IdentityChoice.none : IdentityChoice.use;
            f.identityId = v ?? '';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    _resolve();
    final inForce = _identityInForce;
    final c = ow.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // How inheriting reads, before the first inherited value.
        const _InheritLegend(),
        if (widget.system case final system?) ...[
          _Section(l.sectionSystem),
          system,
          const SizedBox(height: 10),
          _osReleaseRow(l),
          Padding(
            padding: const EdgeInsets.only(
              left: _labelWidth,
              right: _resetWidth,
              bottom: 6,
            ),
            child: Text(
              l.readOsReleaseNote,
              style: TextStyle(fontSize: 12, color: c.textSubtle),
            ),
          ),
        ],
        _Section(l.sectionEnvironment),
        if (widget.system == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, right: _resetWidth),
            child: Text(l.envHint, style: TextStyle(color: c.textMuted)),
          ),
        _row(
          field: 'environment',
          label: l.environment,
          editor: _EnvPicker(
            chosen: f.envKind == EnvironmentKind.mark
                ? EnvironmentView(
                    name: f.envName,
                    short: f.envShort,
                    color: f.envColor,
                  )
                : null,
            onChanged: (mark) => setState(() => f.setEnv(mark)),
          ),
        ),
        if (widget.inheritors case final n? when n > 0)
          Padding(
            padding: const EdgeInsets.only(
              left: _labelWidth,
              right: _resetWidth,
              bottom: 10,
            ),
            child: Text(
              l.envInheritors(n),
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ),
        _Section(widget.connectionTitle),
        _row(
          field: 'identity',
          label: l.identity,
          editor: _identityPicker(context),
          noteAction: inForce == null
              ? null
              : (l.editTheIdentity, () => _editIdentity(inForce)),
        ),
        _row(
          field: 'user',
          label: l.user,
          mono: true,
          editor: TextField(
            key: const ValueKey('settings.user'),
            controller: f.user,
            autofocus: focusFor('user'),
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
            autofocus: focusFor('port'),
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
            autofocus: focusFor('identity_files'),
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
                autofocus: focusFor('route'),
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
        _AdvancedToggle(
          open: _more,
          setHere: _advanced.where(f.setHere.contains).length,
          onTap: () => setState(() => _more = !_more),
        ),
        if (_more) ...[
          _row(
            field: 'proxy',
            label: l.proxy,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ProxyKind>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.proxy'),
                  autofocus: focusFor('proxy'),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: ow.colors.textMuted,
                      ),
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
              autofocus: focusFor('host_key_policy'),
              initialValue: f.policy ?? KeyPolicy.ask,
              items: [
                for (final p in KeyPolicy.values)
                  DropdownMenuItem(value: p, child: Text(_policy(l, p))),
              ],
              onChanged: (v) => setState(() => f.policy = v),
            ),
          ),
          _row(
            field: 'legacy_host_keys',
            label: l.legacyHostKeys,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<bool>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.legacyHostKeys'),
                  autofocus: focusFor('legacy_host_keys'),
                  initialValue: f.legacyHostKeys ?? false,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: true,
                      child: Text(l.legacyHostKeysOn),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text(l.legacyHostKeysOff),
                    ),
                  ],
                  onChanged: (v) => setState(() => f.legacyHostKeys = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l.legacyHostKeysNote,
                  style: TextStyle(fontSize: 12, color: ow.colors.textMuted),
                ),
              ],
            ),
          ),
          _row(
            field: 'persistent_session',
            label: l.persistentSession,
            editor: DropdownButtonFormField<bool>(
              style: fieldTextStyle(context),
              key: const ValueKey('settings.persistent'),
              autofocus: focusFor('persistent_session'),
              initialValue: f.persistent ?? false,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: true, child: Text(l.persistentOn)),
                DropdownMenuItem(value: false, child: Text(l.persistentOff)),
              ],
              onChanged: (v) => setState(() => f.persistent = v),
            ),
          ),
          _row(
            field: 'keepalive_secs',
            label: l.keepaliveLabel,
            editor: DropdownButtonFormField<int>(
              style: fieldTextStyle(context),
              key: const ValueKey('settings.keepalive'),
              autofocus: focusFor('keepalive_secs'),
              initialValue: f.keepalive ?? 10,
              isExpanded: true,
              items: [
                for (final k in {..._keepalives, ?f.keepalive})
                  DropdownMenuItem(value: k, child: Text(_keepalive(l, k))),
              ],
              onChanged: (v) => setState(() => f.keepalive = v),
            ),
          ),
          _row(
            field: 'connect_timeout_secs',
            label: l.connectTimeoutLabel,
            editor: DropdownButtonFormField<int>(
              style: fieldTextStyle(context),
              key: const ValueKey('settings.connectTimeout'),
              autofocus: focusFor('connect_timeout_secs'),
              initialValue: f.connectTimeout ?? 15,
              isExpanded: true,
              items: [
                for (final t in {..._connectTimeouts, ?f.connectTimeout})
                  DropdownMenuItem(
                    value: t,
                    child: Text(l.connectTimeoutAfter(t)),
                  ),
              ],
              onChanged: (v) => setState(() => f.connectTimeout = v),
            ),
          ),
          _row(
            field: 'agent',
            label: l.agent,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<AgentKind>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.agent'),
                  autofocus: focusFor('agent'),
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
          if (widget.system == null) _osReleaseRow(l),
        ],
      ],
    );
  }
}

/// The marks to choose from: none, the four of every install, the one in
/// use if it is another, and «Other…» to make one. A preview below.
class _EnvPicker extends StatelessWidget {
  const _EnvPicker({required this.chosen, required this.onChanged});

  /// Null: no mark.
  final EnvironmentView? chosen;
  final ValueChanged<EnvironmentView?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final presets = envPresets(l);
    final mark = chosen;
    final options = <EnvironmentView?>[
      null,
      ...presets,
      if (mark != null && !presets.contains(mark)) mark,
    ];
    Widget option(EnvironmentView? env) {
      final on = env == mark;
      final colors = env == null ? null : envColors(c, env.color);
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: InkWell(
            key: ValueKey('env.${env?.short ?? 'none'}'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => onChanged(env),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? c.accentSoft : null,
                border: Border.all(color: on ? c.accent : c.control),
                borderRadius: BorderRadius.circular(ow.shape.radius),
              ),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors?.fg,
                      border: colors == null
                          ? Border.all(color: c.textSubtle)
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      env?.name ?? l.envNone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    env?.short ?? l.envNoneNote,
                    style: monoStyle(context, size: 12, color: c.textSubtle),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final env in options)
                  SizedBox(width: w, child: option(env)),
                SizedBox(
                  width: w,
                  child: OutlinedButton.icon(
                    key: const ValueKey('env.other'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () async {
                      final made = await showEnvDialog(context, mark);
                      if (made != null) onChanged(made);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      l.envOther,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (mark != null) ...[
          const SizedBox(height: 10),
          _EnvPreview(env: mark),
        ],
      ],
    );
  }
}

/// How the mark looks: a tab and the top of its terminal.
class _EnvPreview extends StatelessWidget {
  const _EnvPreview({required this.env});

  final EnvironmentView env;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final line = envColors(c, env.color).fg;
    return Semantics(
      label: l.envPreview(env.name),
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.window,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10),
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: ow.terminal.background,
                  border: Border(top: BorderSide(color: line, width: 2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(Status.connected, size: 7),
                    const SizedBox(width: 8),
                    Text(
                      l.envPreviewHost,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    EnvChip(env),
                  ],
                ),
              ),
            ),
            Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 0),
              decoration: BoxDecoration(
                color: ow.terminal.background,
                border: Border(top: BorderSide(color: line, width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'deploy@${l.envPreviewHost}:~\$',
                      style: monoStyle(
                        context,
                        size: 12,
                        color: ow.terminal.foreground,
                      ),
                    ),
                  ),
                  EnvChip(env, big: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mark of one's own: its name, short name and color.
Future<EnvironmentView?> showEnvDialog(
  BuildContext context,
  EnvironmentView? from,
) => showDialog<EnvironmentView>(
  context: context,
  builder: (_) => _EnvDialog(from: from),
);

class _EnvDialog extends StatefulWidget {
  const _EnvDialog({this.from});

  final EnvironmentView? from;

  @override
  State<_EnvDialog> createState() => _EnvDialogState();
}

class _EnvDialogState extends State<_EnvDialog> {
  late final _name = TextEditingController(text: widget.from?.name ?? '');
  late final _short = TextEditingController(text: widget.from?.short ?? '');
  late String _color = widget.from?.color ?? 'green';

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final short = _short.text.trim();
    Navigator.pop(
      context,
      EnvironmentView(
        name: name,
        short: short.isEmpty ? name.toLowerCase() : short,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    // Esc also from a field, which would keep it otherwise.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l.envDialogTitle),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('envDialog.name'),
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.envName),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('envDialog.short'),
                controller: _short,
                maxLength: 12,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.envShort,
                  helperText: l.envShortHelp,
                ),
              ),
              const SizedBox(height: 12),
              Text(l.envColor, style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in envColorNames)
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: name == _color,
                      label: envColorName(l, name),
                      child: Tooltip(
                        message: envColorName(l, name),
                        child: InkWell(
                          key: ValueKey('envDialog.color.$name'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _color = name),
                          child: Container(
                            width: 30,
                            height: 30,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: name == _color
                                    ? c.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: envColors(c, name).fg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_name.text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: EnvChip(
                    EnvironmentView(
                      name: _name.text.trim(),
                      short: _short.text.trim().isEmpty
                          ? _name.text.trim().toLowerCase()
                          : _short.text.trim(),
                      color: _color,
                    ),
                    big: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('envDialog.ok'),
            onPressed: _name.text.trim().isEmpty ? null : _done,
            child: Text(l.envUse),
          ),
        ],
      ),
    );
  }
}

/// «Advanced»: folds the settings that are changed less often, and says
/// how many of them are set here.
class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({
    required this.open,
    required this.setHere,
    required this.onTap,
  });

  final bool open;
  final int setHere;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12, right: _resetWidth),
      child: Semantics(
        button: true,
        expanded: open,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('settings.advanced'),
              borderRadius: BorderRadius.circular(ow.shape.radius),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: c.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.advanced,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Expanded(
                      child: Text(
                        ' · ${l.advancedList}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                    if (setHere > 0)
                      Text(
                        l.advancedSetHere(setHere),
                        style: TextStyle(fontSize: 12, color: c.accentText),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One setting: its own editor when set here; otherwise the inherited
/// value in a dashed box that says where it comes from, and a click on it
/// sets it here. Set here, ↺ goes back to inheriting.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.field,
    required this.label,
    required this.isSet,
    required this.editor,
    required this.inherited,
    required this.origin,
    required this.note,
    required this.onChange,
    required this.onClear,
    this.mono = false,
    this.noteAction,
  });

  /// Its name in the vault, for its keys.
  final String field;
  final String label;
  final bool isSet;
  final Widget editor;
  final String inherited;

  /// Where the inherited value comes from: «Del grupo prod».
  final String origin;

  /// Set here: what it would inherit otherwise.
  final String note;
  final VoidCallback onChange;
  final VoidCallback onClear;
  final bool mono;

  /// A link under it: «Editar la identidad».
  final (String, VoidCallback)? noteAction;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    Widget link((String, VoidCallback) action) => InkWell(
      onTap: action.$2,
      child: Text(
        action.$1,
        style: TextStyle(
          fontSize: 12,
          color: c.text,
          decoration: TextDecoration.underline,
          decorationColor: c.textSubtle,
        ),
      ),
    );
    final inheritedBox = Tooltip(
      message: l.setHereHint,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        label: '$label: $inherited',
        hint: '$origin. ${l.setHereHint}',
        excludeSemantics: true,
        child: FocusOutline(
          radius: ow.shape.radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('setting.$field'),
              borderRadius: BorderRadius.circular(ow.shape.radius),
              mouseCursor: SystemMouseCursors.text,
              onTap: onChange,
              child: CustomPaint(
                painter: _DashedBorder(c.control, ow.shape.radius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          inherited,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mono
                              ? monoStyle(context, size: 13)
                              : TextStyle(color: c.textMuted),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          origin,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: c.textSubtle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(label, style: TextStyle(color: c.textMuted)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSet) editor else inheritedBox,
                if (isSet)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: c.accentText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            note,
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ),
                        if (noteAction case final action?) ...[
                          Text(
                            ' · ',
                            style: TextStyle(fontSize: 12, color: c.textSubtle),
                          ),
                          link(action),
                        ],
                      ],
                    ),
                  )
                else if (noteAction case final action?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: link(action),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: _resetWidth,
            child: isSet
                ? Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: IconButton(
                      key: ValueKey('setting.$field.reset'),
                      tooltip: l.inheritAgain,
                      icon: const Icon(Icons.undo, size: 17),
                      onPressed: onClear,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The width of the labels on the left, the same in every row.
const double _labelWidth = 132;

/// The column of ↺ on the right.
const double _resetWidth = 44;

/// A field with its label on the left, aligned with the settings below.
/// Editors without inherited settings (identities) need no room for ↺.
class EditorFieldRow extends StatelessWidget {
  const EditorFieldRow(this.label, this.field, {super.key, this.reset = true});

  final String label;
  final Widget field;
  final bool reset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              label,
              style: TextStyle(color: context.ow.colors.textMuted),
            ),
          ),
        ),
        Expanded(child: field),
        if (reset) const SizedBox(width: _resetWidth),
      ],
    ),
  );
}

/// Under the fields of an [EditorFieldRow], past its label.
const double editorLabelWidth = _labelWidth;

/// One line on how inheriting reads: dashed is inherited, solid is set
/// here, ↺ inherits again; the order of inheritance behind the (i).
class _InheritLegend extends StatelessWidget {
  const _InheritLegend();

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final small = TextStyle(fontSize: 12, color: c.textMuted);
    Widget swatch({required bool dashed}) => SizedBox(
      width: 18,
      height: 11,
      child: dashed
          ? CustomPaint(painter: _DashedBorder(c.textSubtle, 3))
          : DecoratedBox(
              decoration: BoxDecoration(
                color: c.raised,
                border: Border.all(color: c.textSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
    );
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(text, style: small),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                item(swatch(dashed: true), l.legendInherited),
                item(swatch(dashed: false), l.legendSetHere),
                item(
                  Icon(Icons.undo, size: 13, color: c.textMuted),
                  l.legendInheritAgain,
                ),
              ],
            ),
          ),
          Tooltip(
            message: l.connectionHint,
            child: Semantics(
              label: l.connectionHint,
              child: Icon(Icons.info_outline, size: 16, color: c.textMuted),
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
class EditorFrame extends StatefulWidget {
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
    this.saveLabel,
    this.saveEnabled = true,
    this.snapshot,
    this.errorCause,
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

  /// The main button's text; "Save" by default.
  final String? saveLabel;
  final bool saveEnabled;

  /// What the form says now. Closing without saving after it changed asks
  /// first: Esc, Cancel, the close button or a click outside the panel.
  final String Function()? snapshot;

  /// What [error] came from, when it came from the core: «Detalles»
  /// shows its own words.
  final Object? errorCause;

  @override
  State<EditorFrame> createState() => _EditorFrameState();
}

class _EditorFrameState extends State<EditorFrame> {
  /// The form as it opened.
  String? _opened;

  @override
  void initState() {
    super.initState();
    _opened = widget.snapshot?.call();
  }

  void save() {
    if (widget.saveEnabled) widget.onSave();
  }

  /// Closes without saving: at once if nothing changed, else if the user
  /// says to discard the changes.
  Future<void> _leave() async {
    final changed = widget.snapshot != null && widget.snapshot!() != _opened;
    if (changed) {
      final l = context.l10n;
      final discard = await confirmAction(
        context,
        title: l.discardChangesTitle,
        body: l.discardChangesBody,
        action: l.discardChanges,
        danger: true,
      );
      if (!discard) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final EditorFrame(
      :title,
      :subtitle,
      :error,
      :onSave,
      :onSaveAndConnect,
      :saveAndConnectLabel,
      :onDelete,
      :children,
      :saveLabel,
      :saveEnabled,
    ) = widget;
    // Every way out but saving comes here (a click outside the panel
    // too): saving pops the route itself.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      // A focused field that goes away (a setting back to inheriting)
      // would leave Esc and ⌘↩ hearing nothing.
      child: KeepFocus(
        debugLabel: 'EditorFrame',
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): save,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                save,
            // Also with the cursor in a field, which would keep Esc otherwise.
            const SingleActivator(LogicalKeyboardKey.escape): _leave,
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
                                  subtitle,
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
                        onPressed: _leave,
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(error, style: TextStyle(color: c.danger)),
                        ),
                        if (widget.errorCause case final cause?)
                          TextButton(
                            key: const ValueKey('editor.errorDetails'),
                            onPressed: () => showErrorDetails(context, cause),
                            child: Text(l.details),
                          ),
                      ],
                    ),
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
                          style: TextButton.styleFrom(
                            foregroundColor: c.danger,
                          ),
                          child: Text(l.delete),
                        ),
                      if (onSaveAndConnect != null)
                        TextButton(
                          onPressed: onSaveAndConnect,
                          child: Text(saveAndConnectLabel ?? l.saveAndConnect),
                        ),
                      const Spacer(),
                      OutlinedButton(onPressed: _leave, child: Text(l.cancel)),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: saveEnabled ? onSave : null,
                        child: Text(saveLabel ?? l.save),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Favorito»: up in the sidebar, in the rail and on the start page.
class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({required this.favorite, required this.onChanged});

  final bool favorite;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    return Padding(
      padding: const EdgeInsets.only(left: _labelWidth, right: _resetWidth),
      child: MergeSemantics(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radius),
          ),
          child: InkWell(
            key: const ValueKey('host.favorite'),
            borderRadius: BorderRadius.circular(ow.shape.radius),
            onTap: () => onChanged(!favorite),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: favorite ? c.warn : c.textSubtle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: l.favorite,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          TextSpan(
                            text: ' · ${l.favoriteNote}',
                            style: TextStyle(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Checkbox(
                    value: favorite,
                    onChanged: (v) => onChanged(v ?? false),
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

/// What the server runs: its logo, what told it, and the systems to choose
/// one by hand.
class _SystemBlock extends StatelessWidget {
  const _SystemBlock({
    required this.told,
    required this.chosen,
    required this.env,
    required this.onChanged,
  });

  /// What connecting told, or what was chosen before.
  final SystemView? told;

  /// Chosen by hand in this editor (or before); null: what connecting tells.
  final String? chosen;
  final EnvironmentView? env;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final t = told;
    final detected = t != null && t.kind != SystemKind.manual ? t : null;
    final code = chosen ?? detected?.code;
    final name = chosen != null
        ? systemName(l, chosen!)
        : detected == null
        ? null
        : detected.name.isEmpty
        ? systemName(l, detected.code)
        : detected.name;
    final how = chosen != null
        ? Text(
            l.systemManual,
            style: TextStyle(fontSize: 12, color: c.textMuted),
          )
        : detected == null
        ? Text(
            l.systemNotYet,
            style: TextStyle(fontSize: 12, color: c.textMuted),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: detected.kind == SystemKind.osRelease
                      ? l.systemByOsRelease
                      : l.systemByBanner,
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: detected.evidence,
                  style: monoStyle(context, size: 12, color: c.text),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: c.textMuted),
          );
    return Padding(
      padding: const EdgeInsets.only(right: _resetWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SystemBadge(code: code, env: env, size: 38),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? l.systemUnknownYet,
                      key: const ValueKey('system.name'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    how,
                    if (chosen != null)
                      TextButton(
                        key: const ValueKey('system.detect'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () => onChanged(null),
                        child: Text(l.systemDetectAgain),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: _labelWidth),
            child: Semantics(
              label: l.systemIcon,
              container: true,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final s in systemCodes)
                    Tooltip(
                      message: systemName(l, s),
                      child: Semantics(
                        button: true,
                        selected: s == code,
                        label: systemName(l, s),
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey('system.$s'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onChanged(s),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: s == code
                                    ? c.accent
                                    : Colors.transparent,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SystemBadge(
                              code: s,
                              env: s == code ? env : null,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: SectionLabel(title),
  );
}

class _HostEditor extends ConsumerStatefulWidget {
  const _HostEditor({this.id, this.groupId, this.draft});

  final String? id;
  final String? groupId;
  final HostSpec? draft;

  @override
  ConsumerState<_HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends ConsumerState<_HostEditor> {
  late final HostDetail? _detail = widget.id == null
      ? null
      : ref.read(openWardProvider).host(id: widget.id!);
  late final HostSpec _spec =
      _detail?.spec ??
      widget.draft ??
      HostSpec(label: '', address: '', groupId: widget.groupId);
  late final _label = TextEditingController(text: _spec.label);
  late final _address = TextEditingController(text: _spec.address);
  late final List<String> _tags = [..._spec.tags];
  late final _notes = TextEditingController(text: _spec.notes ?? '');
  late final _settings = _SettingsForm(_spec.settings);
  late String? _group = _spec.groupId;
  late bool _favorite = _spec.favorite;

  /// Chosen by hand; null leaves it to what connecting tells.
  late String? _systemCode = _spec.systemCode;
  String? _error;
  Object? _cause;

  String _snapshot() => [
    _label.text,
    _address.text,
    ..._tags,
    _notes.text,
    _group,
    _favorite,
    _systemCode,
    _settings.signature,
  ].join('\u0000');

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
    _cause = null;
    if (problem != null) return setState(() => _error = problem);
    final spec = HostSpec(
      label: label,
      address: address,
      groupId: _group,
      tags: _tags,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      settings: _settings.toSpec(),
      favorite: _favorite,
      systemCode: _systemCode,
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      final String id;
      if (d == null) {
        id = await app.createHost(spec: spec);
      } else {
        // What changed meanwhile (connecting learned its system) and
        // what was changed here go together.
        await app.updateHost(id: d.id, rev: d.rev, spec: spec, base: _spec);
        id = d.id;
      }
      if (connect) {
        ref.read(libraryProvider.notifier).refresh();
        final host = ref.read(libraryProvider).host(id);
        if (host != null) ref.read(tabsProvider.notifier).openHost(host);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    final groups = _groupChoices(library);
    final groupName = _group == null ? null : library.group(_group!)?.name;
    final mono = monoStyle(context, size: 13, color: context.ow.colors.text);
    return EditorFrame(
      title: _detail == null ? l.newHostTitle : l.editHostTitle,
      subtitle: [
        if (_spec.label.isNotEmpty) _spec.label,
        if (groupName != null) l.inGroup(groupName),
      ].join(' · ').ifEmpty,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      onSaveAndConnect: () => _save(connect: true),
      snapshot: _snapshot,
      children: [
        // One grid: the label on the left, as in the settings below.
        _Section(l.sectionGeneral),
        EditorFieldRow(
          l.name,
          TextField(
            key: const ValueKey('host.label'),
            controller: _label,
            autofocus: true,
          ),
        ),
        EditorFieldRow(
          l.address,
          TextField(
            key: const ValueKey('host.address'),
            controller: _address,
            style: mono,
            decoration: InputDecoration(hintText: l.addressHint),
          ),
        ),
        EditorFieldRow(
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
        EditorFieldRow(l.tags, _TagsField(tags: _tags)),
        _FavoriteRow(
          favorite: _favorite,
          onChanged: (v) => setState(() => _favorite = v),
        ),
        const SizedBox(height: 6),
        _SettingsFields(
          form: _settings,
          hosts: [
            for (final h in library.hosts)
              if (h.id != widget.id) (h.id, h.label),
          ],
          groupId: _group,
          connectionTitle: l.sectionConnection,
          system: _SystemBlock(
            told: _detail?.system,
            chosen: _systemCode,
            env:
                _settings.envMark ??
                (_settings.setHere.contains('environment')
                    ? null
                    : _group == null
                    ? null
                    : library.group(_group!)?.environment),
            onChanged: (code) => setState(() => _systemCode = code),
          ),
        ),
        const SizedBox(height: 8),
        EditorFieldRow(
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
  Object? _cause;

  String _snapshot() =>
      [_name.text, _parent, _settings.signature].join('\u0000');

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
    _cause = null;
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
      setState(() {
        _error = isVaultError(e, VaultErrorKind.cycle)
            ? l.groupInsideItself
            : saveErrorText(l, e);
        _cause = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = ref.watch(libraryProvider);
    return EditorFrame(
      title: _detail == null ? l.newGroupTitle : l.editGroupTitle,
      subtitle: _spec.name.isEmpty ? null : _spec.name,
      error: _error,
      errorCause: _cause,
      onSave: _save,
      snapshot: _snapshot,
      children: [
        _Section(l.sectionGeneral),
        EditorFieldRow(
          l.name,
          TextField(
            key: const ValueKey('group.name'),
            controller: _name,
            autofocus: true,
          ),
        ),
        EditorFieldRow(
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
        const SizedBox(height: 6),
        _SettingsFields(
          form: _settings,
          hosts: [for (final h in library.hosts) (h.id, h.label)],
          groupId: _parent,
          connectionTitle: l.groupSettingsSection,
          inheritors: widget.id == null ? null : library.countUnder(widget.id!),
        ),
      ],
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
