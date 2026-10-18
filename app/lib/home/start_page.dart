import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/connection.dart' show Phase;
import '../core/providers.dart';
import '../hosts/editors.dart';
import '../import/import_dialog.dart';
import '../l10n/l10n.dart';
import '../palette/command_palette.dart';
import '../src/rust/api/tunnels.dart' show TunnelStateKind;
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../tunnels/tunnels.dart';
import '../tunnels/tunnels_page.dart' show forwardText;
import '../ui/environment.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import '../window/shortcuts.dart';
import 'recent.dart';

/// What the window shows with no tab open: a quick connection that
/// completes with hosts and addresses used before, the recent connections
/// and the open tunnels. The first day, the usual ways to start.
class StartPage extends ConsumerStatefulWidget {
  const StartPage({super.key});

  @override
  ConsumerState<StartPage> createState() => _StartPageState();
}

/// What the quick connection offers for what was typed.
sealed class _Suggestion {
  const _Suggestion();
}

final class _Host extends _Suggestion {
  const _Host(this.host);
  final HostView host;
}

/// An address connected to before without saving it.
final class _Used extends _Suggestion {
  const _Used(this.target, this.at);
  final QuickTarget target;
  final int at;
}

/// What was typed, as an address.
final class _Typed extends _Suggestion {
  const _Typed(this.target);
  final QuickTarget target;
}

/// Save what was typed as a host.
final class _Save extends _Suggestion {
  const _Save(this.target);
  final QuickTarget target;
}

class _StartPageState extends ConsumerState<StartPage> {
  final _address = TextEditingController();
  final _focus = FocusNode(debugLabel: 'quick connection');
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _hostAddress(HostView h) =>
      '${h.user.isEmpty ? '' : '${h.user}@'}${h.address}'
      '${h.port == 22 ? '' : ':${h.port}'}';

  /// Connects to what was typed, as an address.
  void _connectTyped() {
    final target = QuickTarget.parse(_address.text);
    if (target == null) {
      setState(() => _error = context.l10n.quickConnectInvalid);
      return;
    }
    ref.read(tabsProvider.notifier).openAddress(target);
  }

  Future<void> _save(QuickTarget t) async {
    final saved = await showHostEditor(
      context,
      ref,
      draft: HostSpec(
        label: t.address,
        address: t.address,
        settings: SettingsSpec(user: t.user, port: t.port),
      ),
    );
    if (saved) ref.read(libraryProvider.notifier).refresh();
  }

  void _run(_Suggestion s) {
    final tabs = ref.read(tabsProvider.notifier);
    switch (s) {
      case _Host(:final host):
        tabs.openHost(host);
      case _Used(:final target) || _Typed(:final target):
        tabs.openAddress(target);
      case _Save(:final target):
        _save(target);
    }
  }

  /// Saved hosts first (best match, then the most recent), the addresses
  /// used before, then what was typed as it is and saving it.
  List<_Suggestion> _suggest(String text) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final recent = ref.read(recentProvider).connections;
    final rank = {
      for (final (i, r) in recent.indexed)
        if (r.hostId != null) r.hostId!: i,
    };
    final hosts = <(HostView, int)>[];
    for (final h in ref.read(libraryProvider).hosts) {
      final score = [
        matchScore(h.label, q),
        matchScore(_hostAddress(h), q),
      ].nonNulls;
      if (score.isNotEmpty) {
        hosts.add((h, score.reduce((a, b) => a < b ? a : b)));
      }
    }
    hosts.sort((a, b) {
      final s = a.$2 - b.$2;
      if (s != 0) return s;
      return (rank[a.$1.id] ?? 999) - (rank[b.$1.id] ?? 999);
    });
    final used = [
      for (final r in recent)
        if (r.address case final a? when matchScore(a, q) != null)
          if (QuickTarget.parse(a) case final t?) _Used(t, r.at),
    ];
    final typed = QuickTarget.parse(text.trim());
    final address = typed != null && RegExp(r'[@.:]').hasMatch(text);
    final known = used.any((u) => u.target.label == typed?.label);
    return [
      for (final (h, _) in hosts.take(6)) _Host(h),
      ...used.take(3),
      if (address && !known) _Typed(typed),
      if (address) _Save(typed),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final recent = ref.watch(recentProvider).connections;
    final library = ref.watch(libraryProvider);
    final firstDay = recent.isEmpty;
    // Favorites beside the recent ones, once there are hosts to choose.
    final favorites = library.hosts.isNotEmpty;
    final recents = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (firstDay)
          _firstDay(context)
        else ...[
          _Heading(l.paletteRecent),
          const SizedBox(height: 6),
          for (final r in recent.take(8)) ?_recentRow(context, r, library),
        ],
      ],
    );
    return ColoredBox(
      color: c.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: favorites ? 980 : 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    firstDay ? l.startHere : l.startTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                _quick(context),
                const SizedBox(height: 28),
                if (!favorites)
                  recents
                else
                  LayoutBuilder(
                    builder: (context, box) => box.maxWidth >= 720
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 105, child: recents),
                              const SizedBox(width: 28),
                              const Expanded(flex: 100, child: _Favorites()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              recents,
                              const SizedBox(height: 24),
                              const _Favorites(),
                            ],
                          ),
                  ),
                const _OpenTunnels(),
                const SizedBox(height: 20),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 14),
                _shortcuts(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quick(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The suggestions as wide as the field (the button takes 104).
        final width = constraints.maxWidth - 104;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RawAutocomplete<_Suggestion>(
                textEditingController: _address,
                focusNode: _focus,
                displayStringForOption: (_) => _address.text,
                optionsBuilder: (value) => _suggest(value.text),
                onSelected: _run,
                fieldViewBuilder: (context, controller, focus, submit) =>
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          alt: true,
                        ): _connectTyped,
                      },
                      child: TextField(
                        key: const ValueKey('quick.address'),
                        controller: controller,
                        focusNode: focus,
                        style: monoStyle(context, size: 13, color: c.text),
                        decoration: InputDecoration(
                          hintText: l.quickConnectHint,
                          errorText: _error,
                          prefixIcon: const Icon(Icons.terminal, size: 16),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        // A suggestion if there is one; else, as typed.
                        onSubmitted: (text) =>
                            _suggest(text).isEmpty ? _connectTyped() : submit(),
                      ),
                    ),
                optionsViewBuilder: (context, select, options) => Align(
                  alignment: Alignment.topLeft,
                  child: _Suggestions(
                    width: width,
                    options: options.toList(),
                    onSelect: select,
                    hostAddress: _hostAddress,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              height: 44,
              child: FilledButton(
                onPressed: () {
                  final options = _suggest(_address.text);
                  options.isEmpty ? _connectTyped() : _run(options.first);
                },
                child: Text(l.connect),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget? _recentRow(
    BuildContext context,
    RecentConnection r,
    Library library,
  ) {
    final l = context.l10n;
    final c = context.ow.colors;
    final hostId = r.hostId;
    final host = hostId == null ? null : library.host(hostId);
    final target = r.address == null ? null : QuickTarget.parse(r.address!);
    if (host == null && target == null) return null;
    final tabs = ref.read(tabsProvider.notifier);
    final length = r.length;
    return _Row(
      key: ValueKey('recent.${r.where}'),
      // An address not saved has no system to tell.
      leading: SystemBadge(
        code: host == null ? '?' : host.system?.code,
        env: host?.environment,
      ),
      env: host?.environment,
      title: host?.label ?? target!.label,
      subtitle: host != null ? _hostAddress(host) : l.notSaved,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            agoText(
              l,
              DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(r.at),
              ),
            ),
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          if (length != null)
            Text(
              [durationText(l, length), if (r.tmux) 'tmux'].join(' · '),
              style: monoStyle(context, size: 12, color: c.textSubtle),
            ),
        ],
      ),
      onTap: () =>
          host != null ? tabs.openHost(host) : tabs.openAddress(target!),
    );
  }

  Widget _firstDay(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    Widget action(IconData icon, String text, String? keys, VoidCallback f) =>
        InkWell(
          onTap: f,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 16, color: c.textMuted),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
                if (keys != null) KeyCap(keys),
              ],
            ),
          ),
        );
    final actions = [
      action(
        Icons.terminal,
        l.openLocal,
        '${key}T',
        ref.read(tabsProvider.notifier).openLocal,
      ),
      action(Icons.add, l.saveNewHost, '${key}N', () async {
        if (await showHostEditor(context, ref)) {
          ref.read(libraryProvider.notifier).refresh();
        }
      }),
      action(Icons.download_outlined, l.importAnything, null, () async {
        await showImport(context, ref);
        ref.read(libraryProvider.notifier).refresh();
      }),
      action(
        Icons.keyboard_command_key,
        l.commandPalette,
        '${key}K',
        () => showCommandPalette(context, ref),
      ),
    ];
    final start = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l.toStart),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.border),
                  actions[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
    final empty = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l.paletteRecent),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: c.control),
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, size: 20, color: c.textMuted),
              const SizedBox(height: 8),
              Text(
                l.recentEmptyTitle,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                l.recentEmptyBody,
                style: TextStyle(color: c.textMuted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [start, const SizedBox(height: 20), empty],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: start),
                const SizedBox(width: 24),
                Expanded(child: empty),
              ],
            ),
    );
  }

  Widget _shortcuts(BuildContext context) {
    final l = context.l10n;
    final c = context.ow.colors;
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    Widget item(String keys, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyCap(keys),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: c.textMuted)),
      ],
    );
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item('${key}T', l.startShortcutLocal),
        item('${key}N', l.startShortcutNewHost),
        item('${key}K', l.startShortcutSearch),
        item(sidebarKeys(l), l.shortcutSidebar),
        // The rest, on the sheet.
        InkWell(
          key: const ValueKey('start.shortcuts'),
          borderRadius: BorderRadius.circular(context.ow.shape.radius),
          onTap: () => showShortcuts(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: item('$key/', l.shortcutAll),
          ),
        ),
      ],
    );
  }
}

/// How long, in a few words: «menos de 1 min», «38 min», «2 h 14 min».
String durationText(AppLocalizations l, Duration d) {
  if (d.inMinutes < 1) return l.durationUnderMinute;
  if (d.inHours < 1) return l.durationMinutes(d.inMinutes);
  return l.durationHours(d.inHours, d.inMinutes % 60);
}

/// The favorites as cards, in their order: a drag puts one before
/// another (and so do the actions of a screen reader).
class _Favorites extends ConsumerWidget {
  const _Favorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final favorites = ref.watch(libraryProvider).favorites;
    final live = {
      for (final s in ref.watch(tabsProvider).sessions)
        if (s.phase == Phase.connected || s.phase == Phase.running) ?s.hostId,
    };
    Future<void> move(String id, int to) async {
      final ids = [for (final h in favorites) h.id];
      final from = ids.indexOf(id);
      if (from < 0 || to < 0 || to >= ids.length || from == to) return;
      ids.insert(to, ids.removeAt(from));
      await ref.read(openWardProvider).orderFavorites(ids: ids);
      ref.read(libraryProvider.notifier).refresh();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Heading(l.favorites)),
            if (favorites.length > 1)
              Text(
                l.dragToOrder,
                style: TextStyle(fontSize: 12, color: c.textSubtle),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (favorites.isEmpty)
          Container(
            key: const ValueKey('start.favorites.empty'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: c.control),
              borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.star_outline_rounded, size: 18, color: c.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.favoritesEmpty,
                    style: TextStyle(color: c.textMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 420 ? 3 : 2;
              final w = (box.maxWidth - 8 * (columns - 1)) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, h) in favorites.indexed)
                    SizedBox(
                      width: w,
                      child: _FavoriteCard(
                        host: h,
                        live: live.contains(h.id),
                        width: w,
                        onOpen: () =>
                            ref.read(tabsProvider.notifier).openHost(h),
                        onDropped: (id) => move(id, i),
                        onEarlier: i == 0 ? null : () => move(h.id, i - 1),
                        onLater: i == favorites.length - 1
                            ? null
                            : () => move(h.id, i + 1),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.host,
    required this.live,
    required this.width,
    required this.onOpen,
    required this.onDropped,
    required this.onEarlier,
    required this.onLater,
  });

  final HostView host;
  final bool live;
  final double width;
  final VoidCallback onOpen;

  /// Another favorite dropped here: it takes this one's place.
  final ValueChanged<String> onDropped;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;

  Widget _card(BuildContext context, {bool over = false}) {
    final l = context.l10n;
    final ow = context.ow;
    final c = ow.colors;
    final h = host;
    final env = h.environment;
    final address = '${h.user}@${h.address}${h.port == 22 ? '' : ':${h.port}'}';
    return Material(
      color: c.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: over ? c.accent : c.control),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: InkWell(
        key: ValueKey('start.favorite.${h.label}'),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 2,
              color: env == null ? c.border : envColors(c, env.color).fg,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SystemBadge(code: h.system?.code, env: env, size: 28),
                      const Spacer(),
                      if (live)
                        Tooltip(
                          message: l.statusConnected,
                          child: const StatusDot(Status.connected),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    h.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(context, size: 12),
                  ),
                  const SizedBox(height: 8),
                  if (env != null)
                    EnvChip(env)
                  else
                    Text(
                      l.envNoneNote,
                      style: TextStyle(fontSize: 12, color: c.textSubtle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ow = context.ow;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.moveEarlier): ?onEarlier,
        CustomSemanticsAction(label: l.moveLater): ?onLater,
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != host.id,
        onAcceptWithDetails: (d) => onDropped(d.data),
        builder: (context, over, _) => Draggable<String>(
          data: host.id,
          feedback: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
            child: SizedBox(width: width, child: _card(context)),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _card(context)),
          child: FocusOutline(
            radius: ow.shape.radiusLarge,
            child: _card(context, over: over.isNotEmpty),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SectionLabel(text);
}

/// A row of the start page: an icon, a name and an address, and what goes
/// on the right.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.env,
  });

  final Widget leading;
  final EnvironmentView? env;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return FocusOutline(
      radius: ow.shape.radius + 2,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(ow.shape.radius + 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (env case final env?) ...[
                            const SizedBox(width: 8),
                            EnvChip(env),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(context, size: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The quick connection's suggestions, under the field.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.width,
    required this.options,
    required this.onSelect,
    required this.hostAddress,
  });

  final double width;
  final List<_Suggestion> options;
  final ValueChanged<_Suggestion> onSelect;
  final String Function(HostView) hostAddress;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final highlighted = AutocompleteHighlightedOption.of(context);
    Widget row(int i, _Suggestion s) {
      Widget icon(IconData i) =>
          SizedBox(width: 32, child: Icon(i, size: 16, color: c.textMuted));
      final (lead, title, subtitle, keys) = switch (s) {
        _Host(:final host) => (
          SystemBadge(code: host.system?.code, env: host.environment, size: 24),
          host.label,
          hostAddress(host),
          null,
        ),
        _Used(:final target, :final at) => (
          icon(Icons.history),
          target.label,
          l.usedNotSaved(
            agoText(
              l,
              DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(at),
              ),
            ),
          ),
          null,
        ),
        _Typed(:final target) => (
          icon(Icons.terminal),
          l.connectToAddress(target.label),
          l.asTyped,
          isApple ? '⌥↩' : 'Alt+↩',
        ),
        _Save(:final target) => (
          icon(Icons.bookmark_add_outlined),
          l.saveAsHost,
          target.label,
          null,
        ),
      };
      final kind = switch (s) {
        _Host() => 'host',
        _Used() => 'used',
        _Typed() => 'typed',
        _Save() => 'save',
      };
      return Material(
        color: i == highlighted ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(ow.shape.radius),
        child: InkWell(
          key: ValueKey('quick.$kind.$title'),
          borderRadius: BorderRadius.circular(ow.shape.radius),
          onTap: () => onSelect(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (s case _Host(:final host)
                              when host.environment != null) ...[
                            const SizedBox(width: 8),
                            EnvChip(host.environment!),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(context, size: 12),
                      ),
                    ],
                  ),
                ),
                if (keys != null) KeyCap(keys),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: c.raised,
        elevation: 12,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.control),
          borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        ),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              padding: const EdgeInsets.all(6),
              shrinkWrap: true,
              children: [for (final (i, s) in options.indexed) row(i, s)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tunnels open now, with «Stop».
class _OpenTunnels extends ConsumerWidget {
  const _OpenTunnels();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(tunnelBoardProvider);
    final l = context.l10n;
    final c = context.ow.colors;
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) {
        final open = [
          for (final t in board.tunnels)
            if (t.state == TunnelStateKind.open) t,
        ];
        if (open.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(l.openTunnels),
              const SizedBox(height: 6),
              for (final t in open)
                _Row(
                  key: ValueKey('start.tunnel.${t.spec.label}'),
                  leading: SizedBox(
                    width: 32,
                    child: Icon(Icons.swap_horiz, size: 18, color: c.textMuted),
                  ),
                  title: t.spec.label,
                  subtitle: '${forwardText(t)} · ${l.tunnelVia(t.hostLabel)}',
                  trailing: OutlinedButton(
                    key: ValueKey('start.tunnel.stop.${t.spec.label}'),
                    onPressed: () => board.close(t.id),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      foregroundColor: c.text,
                    ),
                    child: Text(l.stopAction),
                  ),
                  onTap: () => ref
                      .read(tabsProvider.notifier)
                      .openPage(PageKind.tunnels),
                ),
            ],
          ),
        );
      },
    );
  }
}
