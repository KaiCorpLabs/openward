import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import 'editors.dart';
import 'import_ssh_config.dart';

/// Saved hosts in their groups, a search box over them, and the actions
/// that add to them. Double-click (or Enter) on a host connects in a new
/// tab.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key, required this.searchFocus});

  /// Focused by ⌘K / Ctrl+Shift+K.
  final FocusNode searchFocus;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _search = TextEditingController();
  final Set<String> _collapsed = {};
  String? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _connect(HostView host) {
    ref.read(tabsProvider.notifier).openHost(host);
  }

  void _refresh() => ref.read(libraryProvider.notifier).refresh();

  Future<void> _editHost({String? id, String? groupId}) async {
    if (await showHostEditor(context, ref, id: id, groupId: groupId)) {
      _refresh();
    }
  }

  Future<void> _editGroup({String? id, String? parentId}) async {
    if (await showGroupEditor(context, ref, id: id, parentId: parentId)) {
      _refresh();
    }
  }

  Future<void> _delete(String id, String what, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar $what?'),
        content: Text(
          what == 'el grupo'
              ? '«$name» desaparece; lo que contiene pasa a su grupo padre.'
              : '«$name» desaparece de la lista. Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(openWardProvider).delete(id: id);
    } catch (e) {
      if (!mounted) return;
      final inUse = '$e'.contains('jump host');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inUse
                ? 'Otros hosts saltan por «$name»: cámbialos antes de eliminarlo.'
                : 'No se ha podido eliminar: $e',
          ),
        ),
      );
    }
    _refresh();
  }

  Future<void> _menu(
    Offset at,
    List<PopupMenuEntry<VoidCallback>> items,
  ) async {
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    action?.call();
  }

  PopupMenuItem<VoidCallback> _item(String text, VoidCallback action) =>
      PopupMenuItem(value: action, child: Text(text));

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final results = ref.watch(searchResultsProvider);
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  final first = results?.firstOrNull;
                  if (first != null) _connect(first);
                },
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  _search.clear();
                  ref.read(searchProvider.notifier).set('');
                },
              },
              child: TextField(
                controller: _search,
                focusNode: widget.searchFocus,
                onChanged: ref.read(searchProvider.notifier).set,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Buscar hosts',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _editHost(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Host'),
                ),
                TextButton.icon(
                  onPressed: () => _editGroup(),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                  label: const Text('Grupo'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Importar ~/.ssh/config',
                  icon: const Icon(Icons.download_outlined, size: 18),
                  onPressed: () async {
                    await importSshConfig(context, ref);
                    _refresh();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: library.hosts.isEmpty && library.groups.isEmpty
                ? _Empty(
                    onImport: () async {
                      await importSshConfig(context, ref);
                      _refresh();
                    },
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: results != null
                        ? [for (final h in results) _hostRow(h, 0, library)]
                        : _tree(library, null, 0),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tree(Library library, String? parent, int depth) {
    return [
      for (final g in library.groupsIn(parent)) ...[
        _groupRow(g, depth, library),
        if (!_collapsed.contains(g.id)) ..._tree(library, g.id, depth + 1),
      ],
      for (final h in library.hostsIn(parent)) _hostRow(h, depth, library),
    ];
  }

  Widget _groupRow(GroupView g, int depth, Library library) {
    final open = !_collapsed.contains(g.id);
    final theme = Theme.of(context);
    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(d.globalPosition, [
        _item('Nuevo host aquí', () => _editHost(groupId: g.id)),
        _item('Nuevo subgrupo', () => _editGroup(parentId: g.id)),
        _item('Editar grupo…', () => _editGroup(id: g.id)),
        _item('Eliminar grupo', () => _delete(g.id, 'el grupo', g.name)),
      ]),
      child: InkWell(
        onTap: () => setState(() {
          open ? _collapsed.add(g.id) : _collapsed.remove(g.id);
        }),
        onDoubleTap: () => _editGroup(id: g.id),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.0 + depth * 14, 6, 10, 6),
          child: Row(
            children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16),
              const SizedBox(width: 4),
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${library.countUnder(g.id)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hostRow(HostView h, int depth, Library library) {
    final theme = Theme.of(context);
    final selected = h.id == _selected;
    final address = h.port == 22 ? h.address : '${h.address}:${h.port}';
    return GestureDetector(
      onSecondaryTapDown: (d) {
        setState(() => _selected = h.id);
        _menu(d.globalPosition, [
          _item('Conectar', () => _connect(h)),
          _item('Editar…', () => _editHost(id: h.id)),
          _item('Eliminar', () => _delete(h.id, 'el host', h.label)),
        ]);
      },
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selected = h.id),
          onDoubleTap: () {
            setState(() => _selected = h.id);
            _connect(h);
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(28.0 + depth * 14, 5, 10, 5),
            child: Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${h.user}@$address',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final t in h.tags.take(2))
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _Tag(t),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: scheme.onTertiaryContainer),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Todavía no hay hosts.',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Añade uno o trae los de tu ~/.ssh/config.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onImport,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Importar ~/.ssh/config'),
          ),
        ],
      ),
    );
  }
}
