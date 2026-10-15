import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../hosts/editors.dart';
import '../hosts/import_ssh_config.dart';
import '../l10n/l10n.dart';
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// What the window shows with no tab open: connect to an address at once,
/// or the usual ways to start.
class StartPage extends ConsumerStatefulWidget {
  const StartPage({super.key, required this.searchFocus});

  /// The sidebar's search, for "search hosts".
  final FocusNode searchFocus;

  @override
  ConsumerState<StartPage> createState() => _StartPageState();
}

class _StartPageState extends ConsumerState<StartPage> {
  final _address = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _connect() {
    final target = QuickTarget.parse(_address.text);
    if (target == null) {
      setState(() => _error = context.l10n.quickConnectInvalid);
      return;
    }
    ref.read(tabsProvider.notifier).openAddress(target);
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final key = isApple ? '⌘' : l.ctrlShiftPrefix;
    Widget action(
      IconData icon,
      String text,
      String? keys,
      VoidCallback onTap,
    ) => InkWell(
      onTap: onTap,
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
      action(Icons.download_outlined, l.importFrom, null, () async {
        await importSshConfig(context, ref);
        ref.read(libraryProvider.notifier).refresh();
      }),
      action(
        Icons.search,
        l.searchHosts,
        '${key}K',
        widget.searchFocus.requestFocus,
      ),
    ];
    return ColoredBox(
      color: c.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(l.startHere, style: theme.textTheme.titleLarge),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('quick.address'),
                        controller: _address,
                        style: monoStyle(context, size: 13, color: c.text),
                        decoration: InputDecoration(
                          hintText: l.quickConnectHint,
                          errorText: _error,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => _connect(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: _connect,
                        child: Text(l.connect),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
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
            ),
          ),
        ),
      ),
    );
  }
}
