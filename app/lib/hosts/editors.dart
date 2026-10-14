import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/vault.dart';

/// Creates (no `id`) or edits a host. True if something was saved.
Future<bool> showHostEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? groupId,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _HostEditor(id: id, groupId: groupId),
  );
  return saved ?? false;
}

/// Creates (no `id`) or edits a group. True if something was saved.
Future<bool> showGroupEditor(
  BuildContext context,
  WidgetRef ref, {
  String? id,
  String? parentId,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _GroupEditor(id: id, parentId: parentId),
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

/// The connection settings a host or group may set; empty inherits.
class _SettingsForm {
  _SettingsForm(this.original)
    : user = TextEditingController(text: original.user ?? ''),
      port = TextEditingController(text: original.port?.toString() ?? ''),
      keys = TextEditingController(
        text: (original.identityFiles ?? const []).join('\n'),
      ),
      socket = TextEditingController(text: original.agentSocket),
      command = TextEditingController(text: original.proxyCommand),
      agent = original.agent,
      route = original.route,
      policy = original.hostKeyPolicy,
      jumps = [...original.jumps];

  final SettingsSpec original;
  final TextEditingController user, port, keys, socket, command;
  AgentKind? agent;
  RouteKind? route;
  KeyPolicy? policy;

  /// The jump chain, first hop first.
  final List<JumpSpec> jumps;
  final TextEditingController jumpAddress = TextEditingController();

  void dispose() {
    for (final c in [user, port, keys, socket, command, jumpAddress]) {
      c.dispose();
    }
  }

  String? validate() {
    final p = port.text.trim();
    if (p.isNotEmpty) {
      final n = int.tryParse(p);
      if (n == null || n < 1 || n > 65535) return 'El puerto va de 1 a 65535.';
    }
    if (agent == AgentKind.socket && socket.text.trim().isEmpty) {
      return 'Falta la ruta del socket del agente.';
    }
    if (route == RouteKind.jump && jumps.isEmpty) {
      return 'Añade al menos un host por el que saltar.';
    }
    if (route == RouteKind.command && command.text.trim().isEmpty) {
      return 'Falta el ProxyCommand.';
    }
    return null;
  }

  SettingsSpec toSpec() {
    final files = keys.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return SettingsSpec(
      user: user.text.trim().isEmpty ? null : user.text.trim(),
      port: int.tryParse(port.text.trim()),
      identityFiles: files.isEmpty ? null : files,
      certificateFiles: original.certificateFiles,
      identitiesOnly: original.identitiesOnly,
      agent: agent,
      agentSocket: agent == AgentKind.socket ? socket.text.trim() : '',
      route: route,
      jumps: route == RouteKind.jump ? jumps : const [],
      proxyCommand: route == RouteKind.command ? command.text.trim() : '',
      keepaliveSecs: original.keepaliveSecs,
      agentForward: original.agentForward,
      term: original.term,
      env: original.env,
      hostKeyPolicy: policy,
    );
  }
}

/// What a host inherits, for hints: `field` → `value (where from)`.
Map<String, String> _inherited(HostDetail? d, Library library) {
  if (d == null) return const {};
  final e = d.effective;
  String from(FieldOrigin o) => switch (o.origin) {
    OriginKind.group => 'grupo ${library.group(o.groupId ?? '')?.name ?? ''}',
    OriginKind.default_ => 'por defecto',
    _ => '',
  };
  final values = <String, String?>{
    'user': e.user,
    'port': e.port?.toString(),
    'identity_files': e.identityFiles?.join(', '),
    'agent': switch (e.agent) {
      AgentKind.off => 'ninguno',
      AgentKind.system => 'el del sistema',
      AgentKind.socket => e.agentSocket,
      null => null,
    },
    'route': switch (e.route) {
      RouteKind.direct => 'directa',
      RouteKind.jump => 'saltos',
      RouteKind.command => 'ProxyCommand',
      null => null,
    },
    'host_key_policy': switch (e.hostKeyPolicy) {
      KeyPolicy.ask => 'preguntar',
      KeyPolicy.acceptNew => 'aceptar nuevas',
      KeyPolicy.strict => 'estricta',
      null => null,
    },
  };
  return {
    for (final o in d.origins)
      if (o.origin == OriginKind.group || o.origin == OriginKind.default_)
        if (values[o.field] case final v?) o.field: '$v (${from(o)})',
  };
}

class _SettingsFields extends StatefulWidget {
  const _SettingsFields({
    required this.form,
    required this.hosts,
    required this.inherited,
  });

  final _SettingsForm form;

  /// Hosts that can be jumped through: (id, label).
  final List<(String, String)> hosts;
  final Map<String, String> inherited;

  @override
  State<_SettingsFields> createState() => _SettingsFieldsState();
}

class _SettingsFieldsState extends State<_SettingsFields> {
  _SettingsForm get f => widget.form;

  String _hint(String field, [String fallback = 'Heredado']) {
    final v = widget.inherited[field];
    return v == null ? fallback : 'Heredado: $v';
  }

  @override
  Widget build(BuildContext context) {
    final inherit = 'Heredar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: f.user,
                decoration: InputDecoration(
                  labelText: 'Usuario',
                  // Inherited values show as hints, always visible.
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: _hint('user', 'Tu usuario local'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: f.port,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Puerto',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: widget.inherited['port']?.split(' ').first ?? '22',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: f.keys,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Claves privadas (una ruta por línea)',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: _hint(
              'identity_files',
              '~/.ssh/id_ed25519, id_ecdsa, id_rsa',
            ),
            helperText: 'Se usan por su ruta; OpenWard no guarda claves ni contraseñas.',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<AgentKind?>(
                initialValue: f.agent,
                decoration: InputDecoration(
                  labelText: 'Agente SSH',
                  helperText: f.agent == null ? _hint('agent') : null,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(inherit)),
                  const DropdownMenuItem(
                    value: AgentKind.system,
                    child: Text('El del sistema'),
                  ),
                  const DropdownMenuItem(
                    value: AgentKind.off,
                    child: Text('Ninguno'),
                  ),
                  const DropdownMenuItem(
                    value: AgentKind.socket,
                    child: Text('Otro socket…'),
                  ),
                ],
                onChanged: (v) => setState(() => f.agent = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<KeyPolicy?>(
                initialValue: f.policy,
                decoration: InputDecoration(
                  labelText: 'Claves de host nuevas',
                  helperText: f.policy == null
                      ? _hint('host_key_policy')
                      : null,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(inherit)),
                  const DropdownMenuItem(
                    value: KeyPolicy.ask,
                    child: Text('Preguntar'),
                  ),
                  const DropdownMenuItem(
                    value: KeyPolicy.acceptNew,
                    child: Text('Aceptar nuevas'),
                  ),
                  const DropdownMenuItem(
                    value: KeyPolicy.strict,
                    child: Text('Estricta'),
                  ),
                ],
                onChanged: (v) => setState(() => f.policy = v),
              ),
            ),
          ],
        ),
        if (f.agent == AgentKind.socket) ...[
          const SizedBox(height: 12),
          TextField(
            controller: f.socket,
            decoration: const InputDecoration(
              labelText: 'Socket del agente',
              hintText: '~/Library/Group Containers/…/agent.sock',
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<RouteKind?>(
          initialValue: f.route,
          decoration: InputDecoration(
            labelText: 'Cómo llegar',
            helperText: f.route == null ? _hint('route') : null,
          ),
          items: [
            DropdownMenuItem(value: null, child: Text(inherit)),
            const DropdownMenuItem(
              value: RouteKind.direct,
              child: Text('Directo'),
            ),
            const DropdownMenuItem(
              value: RouteKind.jump,
              child: Text('Saltando por otro host'),
            ),
            const DropdownMenuItem(
              value: RouteKind.command,
              child: Text('ProxyCommand'),
            ),
          ],
          onChanged: (v) => setState(() => f.route = v),
        ),
        if (f.route == RouteKind.jump) ...[
          const SizedBox(height: 12),
          _JumpChain(
            jumps: f.jumps,
            hosts: widget.hosts,
            address: f.jumpAddress,
            onChanged: () => setState(() {}),
          ),
        ],
        if (f.route == RouteKind.command) ...[
          const SizedBox(height: 12),
          TextField(
            controller: f.command,
            decoration: const InputDecoration(
              labelText: 'ProxyCommand',
              hintText: 'cloudflared access ssh --hostname %h',
            ),
          ),
        ],
      ],
    );
  }
}

/// `[user@]host[:port]`, with `[…]` around IPv6 addresses; null if it
/// does not parse.
JumpSpec? parseJumpAddress(String text) {
  var rest = text.trim();
  if (rest.isEmpty || rest.contains(' ')) return null;
  String? user;
  final at = rest.lastIndexOf('@');
  if (at >= 0) {
    user = rest.substring(0, at);
    rest = rest.substring(at + 1);
    if (user.isEmpty) return null;
  }
  String host = rest;
  int? port;
  if (rest.startsWith('[')) {
    final close = rest.indexOf(']');
    if (close < 0) return null;
    host = rest.substring(1, close);
    final after = rest.substring(close + 1);
    if (after.isNotEmpty) {
      if (!after.startsWith(':')) return null;
      port = int.tryParse(after.substring(1));
      if (port == null) return null;
    }
  } else if (rest.contains(':')) {
    final colon = rest.lastIndexOf(':');
    host = rest.substring(0, colon);
    port = int.tryParse(rest.substring(colon + 1));
    if (port == null || host.contains(':')) return null;
  }
  if (host.isEmpty || (port != null && (port < 1 || port > 65535))) {
    return null;
  }
  return JumpSpec(address: host, user: user, port: port);
}

/// The hops in order, each removable, and ways to add one: a saved host or
/// an address.
class _JumpChain extends StatelessWidget {
  const _JumpChain({
    required this.jumps,
    required this.hosts,
    required this.address,
    required this.onChanged,
  });

  final List<JumpSpec> jumps;
  final List<(String, String)> hosts;
  final TextEditingController address;
  final VoidCallback onChanged;

  String _label(JumpSpec j) {
    final id = j.hostId;
    if (id != null) {
      for (final (hid, label) in hosts) {
        if (hid == id) return label;
      }
      return '(host eliminado)';
    }
    final host = j.address ?? '';
    final shown = host.contains(':') ? '[$host]' : host;
    return '${j.user == null ? '' : '${j.user}@'}$shown'
        '${j.port == null ? '' : ':${j.port}'}';
  }

  void _addAddress() {
    final j = parseJumpAddress(address.text);
    if (j == null) return;
    jumps.add(j);
    address.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saltar por, en orden', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < jumps.length; i++) ...[
              if (i > 0) const Icon(Icons.arrow_forward, size: 14),
              InputChip(
                label: Text(_label(jumps[i])),
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
                'Ninguno todavía.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(jumps.length),
                decoration: const InputDecoration(
                  labelText: 'Añadir un host guardado',
                ),
                items: [
                  for (final (id, label) in hosts)
                    DropdownMenuItem(value: id, child: Text(label)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  jumps.add(JumpSpec(hostId: id));
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: address,
                decoration: InputDecoration(
                  labelText: 'o una dirección',
                  hintText: 'usuario@host:puerto',
                  suffixIcon: IconButton(
                    tooltip: 'Añadir',
                    icon: const Icon(Icons.add),
                    onPressed: _addAddress,
                  ),
                ),
                onSubmitted: (_) => _addAddress(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.title,
    required this.error,
    required this.onSave,
    required this.children,
  });

  final String title;
  final String? error;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSave,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onSave,
      },
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: onSave, child: const Text('Guardar')),
        ],
      ),
    );
  }
}

Widget _section(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 20, bottom: 4),
  child: Text(text, style: Theme.of(context).textTheme.titleSmall),
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
  late final _tags = TextEditingController(text: _spec.tags.join(', '));
  late final _notes = TextEditingController(text: _spec.notes ?? '');
  late final _settings = _SettingsForm(_spec.settings);
  late String? _group = _spec.groupId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _address, _tags, _notes]) {
      c.dispose();
    }
    _settings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final address = _address.text.trim();
    final problem = label.isEmpty
        ? 'El host necesita un nombre.'
        : address.isEmpty
        ? 'Falta la dirección.'
        : _settings.validate();
    if (problem != null) return setState(() => _error = problem);
    final spec = HostSpec(
      label: label,
      address: address,
      groupId: _group,
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      settings: _settings.toSpec(),
    );
    final app = ref.read(openWardProvider);
    try {
      final d = _detail;
      if (d == null) {
        await app.createHost(spec: spec);
      } else {
        await app.updateHost(id: d.id, rev: d.rev, spec: spec);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(
        () => _error = '$e'.contains('changed since')
            ? 'Otro cambio ha llegado antes: cierra y vuelve a abrir el editor.'
            : 'No se ha podido guardar: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final groups = _groupChoices(library);
    return _EditorFrame(
      title: _detail == null ? 'Nuevo host' : 'Editar ${_spec.label}',
      error: _error,
      onSave: _save,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  hintText: 'servidor.example.com o 10.0.0.5',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _group,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin grupo')),
                  for (final (id, name) in groups)
                    DropdownMenuItem(value: id, child: Text(name)),
                ],
                onChanged: (v) => setState(() => _group = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Etiquetas',
                  hintText: 'prod, eu',
                ),
              ),
            ),
          ],
        ),
        _section(context, 'Conexión'),
        _SettingsFields(
          form: _settings,
          hosts: [
            for (final h in library.hosts)
              if (h.id != widget.id) (h.id, h.label),
          ],
          inherited: _inherited(_detail, library),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notas'),
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
    final name = _name.text.trim();
    final problem = name.isEmpty
        ? 'El grupo necesita un nombre.'
        : _settings.validate();
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
            ? 'Un grupo no puede estar dentro de sí mismo.'
            : 'No se ha podido guardar: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    return _EditorFrame(
      title: _detail == null ? 'Nuevo grupo' : 'Editar ${_spec.name}',
      error: _error,
      onSave: _save,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _parent,
                decoration: const InputDecoration(labelText: 'Dentro de'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Ningún grupo'),
                  ),
                  for (final (id, name) in _groupChoices(
                    library,
                    excluding: widget.id,
                  ))
                    DropdownMenuItem(value: id, child: Text(name)),
                ],
                onChanged: (v) => setState(() => _parent = v),
              ),
            ),
          ],
        ),
        _section(context, 'Ajustes para todo lo que contiene'),
        _SettingsFields(
          form: _settings,
          hosts: [for (final h in library.hosts) (h.id, h.label)],
          inherited: const {},
        ),
      ],
    );
  }
}
