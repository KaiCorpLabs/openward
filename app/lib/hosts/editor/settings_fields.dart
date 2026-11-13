// The connection settings, each set here or inherited.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../identities/identities.dart';
import '../../identities/identity_editor.dart';
import '../../l10n/l10n.dart';
import '../../keys/key_picker.dart';
import '../../src/rust/api/vault.dart';
import '../../settings/appearance_page.dart' show themeName;
import '../../snippets/snippets.dart' show asksNothing, snippetsProvider;
import '../../src/rust/api/snippets.dart' show SnippetView;
import '../../terminal/schemes.dart';
import '../../ui/themes.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

import 'form.dart';
import 'environment_fields.dart';
import 'rows.dart';
import 'serial_fields.dart';

/// The connection settings, each set here or inherited, and where the
/// inherited ones come from.
class SettingsFields extends ConsumerStatefulWidget {
  const SettingsFields({
    super.key,
    required this.form,
    required this.hosts,
    required this.groupId,
    required this.connectionTitle,
    this.system,
    this.inheritors,
    this.show,
  });

  final SettingsForm form;

  /// A field to open in view (under «Advanced», opened for it).
  final String? show;

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
  ConsumerState<SettingsFields> createState() => _SettingsFieldsState();
}

class _SettingsFieldsState extends ConsumerState<SettingsFields> {
  late bool _more =
      _advanced.any(widget.form.setHere.contains) ||
      _advanced.contains(widget.show);

  /// The row of [SettingsFields.show], to bring it into view.
  final _shown = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.form.problem.addListener(_onProblem);
    widget.form.addListener(_onForm);
    if (widget.show != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _shown.currentContext;
        if (mounted && row != null) {
          Scrollable.ensureVisible(row, alignment: 0.3);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.form.problem.removeListener(_onProblem);
    widget.form.removeListener(_onForm);
    super.dispose();
  }

  void _onForm() => setState(() {});

  /// A problem on a field: shown on it, «Advanced» opened if the field is
  /// under it, and the focus there.
  void _onProblem() {
    final field = widget.form.problem.value?.field;
    setState(() {
      if (field == 'proxy' || field == 'socket') _more = true;
    });
    final node = widget.form.focus[field];
    if (node != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
  }

  /// Fields under «Advanced», folded unless one is set here: those the
  /// protocol in force uses.
  List<String> get _advanced => switch (_protocol) {
    ProtocolKind.ssh => [
      'proxy',
      'host_key_policy',
      'legacy_host_keys',
      'persistent_session',
      'mosh',
      'mosh_server',
      ..._terminalFields,
      'session_log',
      'keepalive_secs',
      'connect_timeout_secs',
      'agent',
      if (widget.system == null) 'read_os_release',
    ],
    ProtocolKind.telnet => [
      'proxy',
      ..._terminalFields,
      'session_log',
      'connect_timeout_secs',
    ],
    ProtocolKind.serial => [..._terminalFields, 'session_log'],
  };

  /// How the terminal reads and shows the host, whatever reaches it.
  static const _terminalFields = [
    'encoding',
    'backspace',
    'terminal_scheme',
    'startup_snippet',
  ];

  /// How the item is reached with what the form says now.
  ProtocolKind get _protocol {
    _resolve();
    return f.protocolWith(_from);
  }

  String _protocolName(AppLocalizations l, ProtocolKind p) => switch (p) {
    ProtocolKind.ssh => 'SSH',
    ProtocolKind.telnet => 'Telnet',
    ProtocolKind.serial => l.protocolSerial,
  };

  SettingsForm get f => widget.form;

  /// The colors a host can have of its own, by id and name: the themes'
  /// terminals, the gallery's schemes and those imported.
  List<(String, String)> get _schemes {
    final l = context.l10n;
    return [
      for (final t in OwThemes.all.values) ('theme:${t.id}', themeName(l, t)),
      for (final s in [...knownSchemes, ...ref.watch(settingsProvider).schemes])
        (s.id, s.name),
    ];
  }

  /// The snippets a shell can start with: those that ask nothing.
  List<SnippetView> get _startupSnippets => [
    for (final s in ref.watch(snippetsProvider))
      if (asksNothing(s)) s,
  ];

  String _snippetName(AppLocalizations l, String id) => id.isEmpty
      ? l.startupSnippetNone
      : ref
                .watch(snippetsProvider)
                .where((s) => s.id == id)
                .firstOrNull
                ?.spec
                .label ??
            l.startupSnippetGone;

  String _schemeName(AppLocalizations l, String id) => id.isEmpty
      ? l.terminalSchemeApp
      : _schemes.where((s) => s.$1 == id).firstOrNull?.$2 ?? id;

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

  String _identityLabel(String id) {
    final all = ref.read(identitiesProvider);
    if (!all.hasValue) return all.hasError ? context.l10n.errInternal : '…';
    return identityById(all.value!, id)?.spec.label ??
        context.l10n.deletedIdentity;
  }

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
    f.update(() {
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
      // Telnet's own port when only the defaults set one (as the core
      // does), also while the protocol is chosen here and not saved.
      'port' =>
        _protocol == ProtocolKind.telnet &&
                _originOf('port')?.origin == OriginKind.default_
            ? '23'
            : '${e.port ?? 22}',
      'protocol' => _protocolName(l, e.protocol ?? ProtocolKind.ssh),
      'mosh' => e.mosh ?? false ? l.moshOn : l.moshOff,
      'mosh_server' => e.moshServer ?? 'mosh-server',
      'encoding' => charsetLabel(e.encoding ?? 'utf-8'),
      'backspace' => backspaceLabel(l, e.backspace ?? BackspaceKind.delete),
      'terminal_scheme' => _schemeName(l, e.terminalScheme ?? ''),
      'startup_snippet' => _snippetName(l, e.startupSnippet ?? ''),
      'serial' => serialSummary(l, e.serial ?? defaultSerialLine),
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
      'session_log' => e.sessionLog ?? false ? l.sessionLogOn : l.sessionLogOff,
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
      onChanged: (v) => f.update(() => f.readOsRelease = v),
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
    return SettingRow(
      key: field == widget.show ? _shown : null,
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
        if (field == 'port') f.port.text = _inheritedValue('port');
        _justTook = field;
      }),
      onClear: () => f.drop(field),
    );
  }

  Widget _identityPicker(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    const none = '';
    const create = '+';
    final result = ref.watch(identitiesProvider);
    if (!result.hasValue) {
      return result.hasError
          ? TextButton(
              onPressed: () => ref.read(identitiesProvider.notifier).refresh(),
              child: Text(l.retry),
            )
          : const LinearProgressIndicator();
    }
    final identities = result.value!;
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
            style: TextStyle(
              fontSize: OwText.small,
              color: warn ? c.warn : c.textSubtle,
            ),
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
          f.update(() {
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
        const InheritLegend(),
        if (widget.system case final system?) ...[
          EditorSection(l.sectionSystem),
          system,
          const SizedBox(height: 10),
          // It runs a command over SSH.
          if (_protocol == ProtocolKind.ssh) ...[
            _osReleaseRow(l),
            Padding(
              padding: const EdgeInsets.only(
                left: editorLabelWidth,
                right: editorResetWidth,
                bottom: OwSpace.s3,
              ),
              child: Text(
                l.readOsReleaseNote,
                style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
              ),
            ),
          ],
        ],
        EditorSection(l.sectionEnvironment),
        if (widget.system == null)
          Padding(
            padding: const EdgeInsets.only(
              bottom: OwSpace.s6,
              right: editorResetWidth,
            ),
            child: Text(l.envHint, style: TextStyle(color: c.textMuted)),
          ),
        _row(
          field: 'environment',
          label: l.environment,
          editor: EnvPicker(
            chosen: f.envKind == EnvironmentKind.mark
                ? EnvironmentView(
                    name: f.envName,
                    short: f.envShort,
                    color: f.envColor,
                  )
                : null,
            onChanged: f.setEnv,
          ),
        ),
        if (widget.inheritors case final n? when n > 0)
          Padding(
            padding: const EdgeInsets.only(
              left: editorLabelWidth,
              right: editorResetWidth,
              bottom: OwSpace.s5,
            ),
            child: Text(
              l.envInheritors(n),
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ),
        EditorSection(widget.connectionTitle),
        _row(
          field: 'protocol',
          label: l.protocol,
          editor: DropdownButtonFormField<ProtocolKind>(
            style: fieldTextStyle(context),
            key: const ValueKey('settings.protocol'),
            autofocus: focusFor('protocol'),
            initialValue: f.protocol ?? ProtocolKind.ssh,
            isExpanded: true,
            items: [
              for (final p in ProtocolKind.values)
                DropdownMenuItem(value: p, child: Text(_protocolName(l, p))),
            ],
            onChanged: (v) => f.update(() => f.protocol = v),
          ),
        ),
        if (_protocol == ProtocolKind.telnet)
          Padding(
            padding: const EdgeInsets.only(
              left: editorLabelWidth,
              right: editorResetWidth,
              bottom: OwSpace.s5,
            ),
            child: Text(
              l.telnetUnencryptedNote,
              key: const ValueKey('settings.telnetNote'),
              style: TextStyle(fontSize: OwText.small, color: c.warn),
            ),
          ),
        if (_protocol == ProtocolKind.serial)
          _row(
            field: 'serial',
            label: l.serialLine,
            editor: SerialLineFields(
              line: f.serial ?? defaultSerialLine,
              autofocus: focusFor('serial'),
              onChanged: (v) => f.update(() => f.serial = v),
            ),
          ),
        if (_protocol == ProtocolKind.ssh) ...[
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
        ],
        if (_protocol != ProtocolKind.serial)
          _row(
            field: 'port',
            label: l.port,
            mono: true,
            editor: TextField(
              key: const ValueKey('settings.port'),
              controller: f.port,
              focusNode: f.focus['port'],
              autofocus: focusFor('port'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => f.edited('port'),
              style: monoStyle(context, size: 13, color: ow.colors.text),
              decoration: InputDecoration(errorText: f.errorOn('port')),
            ),
          ),
        if (_protocol == ProtocolKind.ssh)
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
              decoration: InputDecoration(
                helperText: l.keysHelp,
                suffixIcon: IconButton(
                  key: const ValueKey('settings.pickKey'),
                  tooltip: l.chooseSshKey,
                  icon: const Icon(Icons.key),
                  onPressed: () async {
                    final path = await showSshKeyPicker(context);
                    if (!mounted || path == null) return;
                    final paths = f.keys.text
                        .split('\n')
                        .where((p) => p.trim().isNotEmpty)
                        .toList();
                    if (!paths.contains(path)) {
                      f.update(() => f.keys.text = [...paths, path].join('\n'));
                      f.edited('identity_files');
                    }
                  },
                ),
              ),
            ),
          ),
        if (_protocol != ProtocolKind.serial)
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
                  onChanged: (v) => f.update(() => f.route = v),
                ),
                if (f.route == RouteKind.jump) ...[
                  const SizedBox(height: 10),
                  JumpChain(
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
                    focusNode: f.focus['command'],
                    onChanged: (_) => f.edited('command'),
                    style: monoStyle(context, size: 13, color: ow.colors.text),
                    decoration: InputDecoration(
                      hintText: 'cloudflared access ssh --hostname %h',
                      errorText: f.errorOn('command'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        AdvancedToggle(
          open: _more,
          setHere: _advanced.where(f.setHere.contains).length,
          list: switch (_protocol) {
            ProtocolKind.ssh => null,
            ProtocolKind.telnet => l.advancedListTelnet,
            ProtocolKind.serial => l.advancedListSerial,
          },
          onTap: () => setState(() => _more = !_more),
        ),
        if (_more) ...[
          if (_protocol != ProtocolKind.serial)
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
                    onChanged: (v) => f.update(() => f.proxy = v),
                  ),
                  if (f.proxyServer) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('settings.proxyHost'),
                            controller: f.proxyHost,
                            focusNode: f.focus['proxy'],
                            onChanged: (_) {
                              f.edited('proxy');
                              setState(() {});
                            },
                            style: monoStyle(
                              context,
                              size: 13,
                              color: ow.colors.text,
                            ),
                            decoration: InputDecoration(
                              labelText: l.proxyServer,
                              errorText: f.errorOn('proxy'),
                            ),
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
                      style: monoStyle(
                        context,
                        size: 13,
                        color: ow.colors.text,
                      ),
                      decoration: InputDecoration(
                        labelText: l.proxyUser,
                        helperText: l.proxyUserHelp,
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.proxyRouteTitle,
                      style: TextStyle(
                        fontSize: OwText.small,
                        color: ow.colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _proxyRoute(l),
                      style: monoStyle(
                        context,
                        size: 12,
                        color: ow.colors.text,
                      ),
                    ),
                    if ((f.setHere.contains('route') ? f.route : _from.route) ==
                        RouteKind.command) ...[
                      const SizedBox(height: 8),
                      Text(
                        l.proxyNotWithCommand,
                        style: TextStyle(
                          fontSize: OwText.small,
                          color: ow.colors.warn,
                        ),
                      ),
                    ],
                    if (f.proxy == ProxyKind.http) ...[
                      const SizedBox(height: 8),
                      Text(
                        l.proxyHttpNote,
                        style: TextStyle(
                          fontSize: OwText.small,
                          color: ow.colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          if (_protocol == ProtocolKind.ssh) ...[
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
                onChanged: (v) => f.update(() => f.policy = v),
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
                    onChanged: (v) => f.update(() => f.legacyHostKeys = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.legacyHostKeysNote,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: ow.colors.textMuted,
                    ),
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
                onChanged: (v) => f.update(() => f.persistent = v),
              ),
            ),
          ],
          if (_protocol == ProtocolKind.ssh) ...[
            _row(
              field: 'mosh',
              label: 'Mosh',
              editor: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<bool>(
                    style: fieldTextStyle(context),
                    key: const ValueKey('settings.mosh'),
                    autofocus: focusFor('mosh'),
                    initialValue: f.mosh ?? false,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(value: true, child: Text(l.moshOn)),
                      DropdownMenuItem(value: false, child: Text(l.moshOff)),
                    ],
                    onChanged: (v) => f.update(() => f.mosh = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.moshNote,
                    style: TextStyle(
                      fontSize: OwText.small,
                      color: ow.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Where its server is: only while Mosh is on.
            if ((f.setHere.contains('mosh') ? f.mosh : _from.mosh) ?? false)
              _row(
                field: 'mosh_server',
                label: l.moshServer,
                mono: true,
                editor: TextField(
                  key: const ValueKey('settings.moshServer'),
                  controller: f.moshServer,
                  autofocus: focusFor('mosh_server'),
                  style: monoStyle(context, size: 13, color: ow.colors.text),
                  decoration: InputDecoration(
                    hintText: 'mosh-server',
                    helperText: l.moshServerHelp,
                    helperMaxLines: 2,
                  ),
                ),
              ),
          ],
          _row(
            field: 'session_log',
            label: l.sessionLog,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<bool>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.sessionLog'),
                  autofocus: focusFor('session_log'),
                  initialValue: f.sessionLog ?? false,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: true, child: Text(l.sessionLogOn)),
                    DropdownMenuItem(
                      value: false,
                      child: Text(l.sessionLogOff),
                    ),
                  ],
                  onChanged: (v) => f.update(() => f.sessionLog = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l.sessionLogNote,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _row(
            field: 'encoding',
            label: l.encodingLabel,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.encoding'),
                  autofocus: focusFor('encoding'),
                  initialValue: f.encoding ?? 'utf-8',
                  isExpanded: true,
                  items: [
                    for (final c in {
                      ...ref.read(openWardProvider).charsets(),
                      ?f.encoding,
                    })
                      DropdownMenuItem(value: c, child: Text(charsetLabel(c))),
                  ],
                  onChanged: (v) => f.update(() => f.encoding = v),
                ),
                const SizedBox(height: 8),
                Text(
                  _protocol == ProtocolKind.ssh
                      ? l.encodingNoteMosh
                      : l.encodingNote,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _row(
            field: 'backspace',
            label: l.backspaceLabel,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<BackspaceKind>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.backspace'),
                  autofocus: focusFor('backspace'),
                  initialValue: f.backspace ?? BackspaceKind.delete,
                  isExpanded: true,
                  items: [
                    for (final b in BackspaceKind.values)
                      DropdownMenuItem(
                        value: b,
                        child: Text(backspaceLabel(l, b)),
                      ),
                  ],
                  onChanged: (v) => f.update(() => f.backspace = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l.backspaceNote,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _row(
            field: 'terminal_scheme',
            label: l.terminalSchemeLabel,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.terminalScheme'),
                  autofocus: focusFor('terminal_scheme'),
                  initialValue: f.terminalScheme ?? '',
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(l.terminalSchemeApp),
                    ),
                    for (final (id, name) in _schemes)
                      DropdownMenuItem(value: id, child: Text(name)),
                    // One that is gone (an imported scheme deleted).
                    if (f.terminalScheme case final id?
                        when id.isNotEmpty && !_schemes.any((s) => s.$1 == id))
                      DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: (v) => f.update(() => f.terminalScheme = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l.terminalSchemeNote,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _row(
            field: 'startup_snippet',
            label: l.startupSnippet,
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  style: fieldTextStyle(context),
                  key: const ValueKey('settings.startupSnippet'),
                  autofocus: focusFor('startup_snippet'),
                  initialValue: f.startupSnippet ?? '',
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(l.startupSnippetNone),
                    ),
                    for (final s in _startupSnippets)
                      DropdownMenuItem(value: s.id, child: Text(s.spec.label)),
                    // One deleted since, or that asks for values now.
                    if (f.startupSnippet case final id?
                        when id.isNotEmpty &&
                            !_startupSnippets.any((s) => s.id == id))
                      DropdownMenuItem(
                        value: id,
                        child: Text(l.startupSnippetGone),
                      ),
                  ],
                  onChanged: (v) => f.update(() => f.startupSnippet = v),
                ),
                const SizedBox(height: 8),
                Text(
                  l.startupSnippetNote,
                  style: TextStyle(
                    fontSize: OwText.small,
                    color: ow.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_protocol == ProtocolKind.ssh)
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
                onChanged: (v) => f.update(() => f.keepalive = v),
              ),
            ),
          if (_protocol != ProtocolKind.serial)
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
                onChanged: (v) => f.update(() => f.connectTimeout = v),
              ),
            ),
          if (_protocol == ProtocolKind.ssh) ...[
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
                    onChanged: (v) => f.update(() => f.agent = v),
                  ),
                  if (f.agent == AgentKind.socket) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: f.socket,
                      focusNode: f.focus['socket'],
                      onChanged: (_) => f.edited('socket'),
                      style: monoStyle(
                        context,
                        size: 13,
                        color: ow.colors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: agentSocketExample,
                        errorText: f.errorOn('socket'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.system == null) _osReleaseRow(l),
          ],
        ],
      ],
    );
  }
}

/// A character set's name as people know it.
String charsetLabel(String label) => switch (label.toLowerCase()) {
  'utf-8' => 'UTF-8',
  'iso-8859-1' => 'Latin-1 (ISO-8859-1)',
  'iso-8859-15' => 'Latin-9 (ISO-8859-15)',
  'windows-1252' => 'Windows-1252',
  'cp437' => 'CP437 (IBM PC)',
  'iso-8859-2' => 'Latin-2 (ISO-8859-2)',
  'windows-1250' => 'Windows-1250',
  'windows-1251' => 'Windows-1251',
  'koi8-r' => 'KOI8-R',
  'ibm866' => 'CP866',
  'shift_jis' => 'Shift-JIS',
  'euc-jp' => 'EUC-JP',
  'big5' => 'Big5',
  'gb18030' => 'GB18030',
  'euc-kr' => 'EUC-KR',
  _ => label,
};

String backspaceLabel(AppLocalizations l, BackspaceKind b) => switch (b) {
  BackspaceKind.delete => l.backspaceDelete,
  BackspaceKind.controlH => l.backspaceControlH,
};
