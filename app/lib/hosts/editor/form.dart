// The connection settings a host or group edits, as a form: pure, and
// told to whoever shows it when it changes.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/address.dart' show defaultSerialLine;
import '../../l10n/l10n.dart';
import '../../src/rust/api/vault.dart';

/// Where an agent's socket tends to be, on this system: a password
/// manager's on macOS and Linux, OpenSSH's pipe on Windows.
String get agentSocketExample => Platform.isMacOS
    ? '~/Library/Group Containers/…/agent.sock'
    : Platform.isWindows
    ? r'\\.\pipe\openssh-ssh-agent'
    : '~/.1password/agent.sock';

/// What stops an editor from saving, and the field it is on.
typedef FieldProblem = ({String field, String text});

/// The connection settings a host or group may set. A field is either set
/// here or inherited; [setHere] says which.
class SettingsForm extends ChangeNotifier {
  SettingsForm(this.original)
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
      moshServer = TextEditingController(text: original.moshServer ?? ''),
      mosh = original.mosh,
      proxy = original.proxy,
      agent = original.agent,
      route = original.route,
      policy = original.hostKeyPolicy,
      legacyHostKeys = original.legacyHostKeys,
      persistent = original.persistentSession,
      sessionLog = original.sessionLog,
      keepalive = original.keepaliveSecs,
      connectTimeout = original.connectTimeoutSecs,
      identity = original.identity,
      identityId = original.identityId,
      envKind = original.environment,
      envName = original.environmentName,
      envShort = original.environmentShort,
      envColor = original.environmentColor,
      readOsRelease = original.readOsRelease,
      protocol = original.protocol,
      serial = original.serial,
      encoding = original.encoding,
      backspace = original.backspace,
      terminalScheme = original.terminalScheme,
      startupSnippet = original.startupSnippet,
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
        if (original.sessionLog != null) 'session_log',
        if (original.keepaliveSecs != null) 'keepalive_secs',
        if (original.connectTimeoutSecs != null) 'connect_timeout_secs',
        if (original.environment != null) 'environment',
        if (original.readOsRelease != null) 'read_os_release',
        if (original.protocol != null) 'protocol',
        if (original.serial != null) 'serial',
        if (original.mosh != null) 'mosh',
        if (original.moshServer != null) 'mosh_server',
        if (original.encoding != null) 'encoding',
        if (original.backspace != null) 'backspace',
        if (original.terminalScheme != null) 'terminal_scheme',
        if (original.startupSnippet != null) 'startup_snippet',
      };

  final SettingsSpec original;
  final TextEditingController user, port, keys, socket, command;
  final TextEditingController proxyHost, proxyPort, proxyUser;

  /// Where mosh-server is on the server, when not on its PATH.
  final TextEditingController moshServer;

  /// The shell over Mosh.
  bool? mosh;

  /// The host's character set (`utf-8`, `iso-8859-1`…).
  String? encoding;

  /// What Backspace sends.
  BackspaceKind? backspace;

  /// The terminal's scheme, by id; empty for the app's own colors.
  String? terminalScheme;

  /// The snippet typed in each new shell, by id; empty for none.
  String? startupSnippet;
  AgentKind? agent;
  RouteKind? route;
  ProxyKind? proxy;
  KeyPolicy? policy;
  bool? legacyHostKeys;
  IdentityChoice? identity;
  bool? persistent;
  bool? sessionLog;
  int? keepalive;
  int? connectTimeout;

  /// With [IdentityChoice.use].
  String identityId;

  /// The mark: none, or the one in [envName], [envShort] and [envColor].
  EnvironmentKind? envKind;
  String envName, envShort, envColor;
  bool? readOsRelease;

  /// SSH, Telnet or a serial port.
  ProtocolKind? protocol;

  /// A serial port's settings.
  SerialLineSpec? serial;

  /// The jump chain, first hop first.
  final List<JumpSpec> jumps;
  final TextEditingController jumpAddress = TextEditingController();

  /// Fields this item sets itself, by their vault name.
  final Set<String> setHere;

  /// What stops it from saving, on its field: shown there, with the
  /// focus, «Advanced» opened if it is under it.
  final problem = ValueNotifier<FieldProblem?>(null);

  /// The fields a problem can be on, to take the focus.
  final focus = {
    for (final f in ['port', 'socket', 'command', 'proxy']) f: FocusNode(),
  };

  /// The problem's text if it is on `field`.
  String? errorOn(String field) =>
      problem.value?.field == field ? problem.value!.text : null;

  /// Typing in `field` puts its problem away.
  void edited(String field) {
    if (problem.value?.field == field) problem.value = null;
  }

  @override
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
      moshServer,
    ]) {
      c.dispose();
    }
    for (final n in focus.values) {
      n.dispose();
    }
    problem.dispose();
    super.dispose();
  }

  /// Changes fields by hand, and tells whoever shows the form (the
  /// fields, and the system's preview beside them, which shows the mark).
  void update(void Function() change) {
    change();
    notifyListeners();
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
      case 'session_log':
        sessionLog = inherited.sessionLog ?? false;
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
      case 'protocol':
        protocol = inherited.protocol ?? ProtocolKind.ssh;
      case 'serial':
        serial = inherited.serial ?? defaultSerialLine;
      case 'mosh':
        mosh = inherited.mosh ?? false;
      case 'mosh_server':
        moshServer.text = inherited.moshServer ?? 'mosh-server';
      case 'encoding':
        encoding = inherited.encoding ?? 'utf-8';
      case 'backspace':
        backspace = inherited.backspace ?? BackspaceKind.delete;
      case 'terminal_scheme':
        terminalScheme = inherited.terminalScheme ?? '';
      case 'startup_snippet':
        startupSnippet = inherited.startupSnippet ?? '';
    }
    notifyListeners();
  }

  /// The protocol in force with what the form says now: its own, or the
  /// one it inherits.
  ProtocolKind protocolWith(SettingsSpec inherited) =>
      (setHere.contains('protocol') ? protocol : inherited.protocol) ??
      ProtocolKind.ssh;

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
      case 'session_log':
        sessionLog = null;
      case 'keepalive_secs':
        keepalive = null;
      case 'connect_timeout_secs':
        connectTimeout = null;
      case 'environment':
        envKind = null;
        envName = envShort = envColor = '';
      case 'read_os_release':
        readOsRelease = null;
      case 'protocol':
        protocol = null;
      case 'serial':
        serial = null;
      case 'mosh':
        mosh = null;
      case 'mosh_server':
        moshServer.clear();
      case 'encoding':
        encoding = null;
      case 'backspace':
        backspace = null;
      case 'terminal_scheme':
        terminalScheme = null;
      case 'startup_snippet':
        startupSnippet = null;
    }
    notifyListeners();
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
    moshServer.text,
    mosh,
    encoding,
    backspace,
    terminalScheme,
    startupSnippet,
    jumpAddress.text,
    agent,
    route,
    proxy,
    policy,
    legacyHostKeys,
    identity,
    identityId,
    persistent,
    sessionLog,
    keepalive,
    connectTimeout,
    envKind,
    envName,
    envShort,
    envColor,
    readOsRelease,
    protocol,
    serial == null
        ? null
        : '${serial!.baud}|${serial!.dataBits}|${serial!.parity}|'
              '${serial!.stopBits}|${serial!.flow}',
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
    notifyListeners();
  }

  /// The identity choice as the vault would take it, or null to inherit.
  IdentityChoice? get identityChoice =>
      setHere.contains('identity') ? identity : null;

  /// A proxy server is in use (not "none", not inherited).
  bool get proxyServer =>
      setHere.contains('proxy') &&
      (proxy == ProxyKind.http || proxy == ProxyKind.socks5);

  /// What stops it from saving, and on which field; null if nothing.
  FieldProblem? validate(AppLocalizations l) {
    final p = port.text.trim();
    if (setHere.contains('port') && p.isNotEmpty) {
      final n = int.tryParse(p);
      if (n == null || n < 1 || n > 65535) {
        return (field: 'port', text: l.portRange);
      }
    }
    if (agent == AgentKind.socket && socket.text.trim().isEmpty) {
      return (field: 'socket', text: l.missingSocket);
    }
    if (identityChoice == IdentityChoice.use && identityId.isEmpty) {
      return (field: 'identity', text: l.pickIdentity);
    }
    if (setHere.contains('environment') &&
        envKind == EnvironmentKind.mark &&
        envName.trim().isEmpty) {
      return (field: 'environment', text: l.envNeedsName);
    }
    if (route == RouteKind.jump && jumps.isEmpty) {
      return (field: 'route', text: l.missingJump);
    }
    if (route == RouteKind.command && command.text.trim().isEmpty) {
      return (field: 'command', text: l.missingProxyCommand);
    }
    if (proxyServer) {
      final n = int.tryParse(proxyPort.text.trim());
      if (proxyHost.text.trim().isEmpty || n == null || n < 1 || n > 65535) {
        return (field: 'proxy', text: l.missingProxy);
      }
    }
    if (setHere.contains('serial') && (serial?.baud ?? 0) < 1) {
      return (field: 'serial', text: l.serialBaudMissing);
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
      sessionLog: setHere.contains('session_log') ? sessionLog : null,
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
      protocol: setHere.contains('protocol') ? protocol : null,
      serial: setHere.contains('serial') ? serial : null,
      mosh: setHere.contains('mosh') ? mosh : null,
      moshServer: text('mosh_server', moshServer),
      encoding: setHere.contains('encoding') ? encoding : null,
      backspace: setHere.contains('backspace') ? backspace : null,
      terminalScheme: setHere.contains('terminal_scheme')
          ? terminalScheme
          : null,
      startupSnippet: setHere.contains('startup_snippet')
          ? startupSnippet
          : null,
    );
  }
}
