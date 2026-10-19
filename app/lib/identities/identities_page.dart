// The «Identidades» page: every identity with its user, keys, agent and who
// uses it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/identities.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'identities.dart';
import 'identity_editor.dart';
import 'use_identity.dart';

class IdentitiesPage extends ConsumerStatefulWidget {
  const IdentitiesPage({super.key});

  @override
  ConsumerState<IdentitiesPage> createState() => _IdentitiesPageState();
}

class _IdentitiesPageState extends ConsumerState<IdentitiesPage> {
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keys may have come or gone since the last look.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(identitiesProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(IdentityView i) {
    final f = _filter.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    return [
      i.spec.label,
      i.spec.user ?? '',
      ...i.spec.identityFiles,
    ].any((s) => s.toLowerCase().contains(f));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final all = ref.watch(identitiesProvider);
    final shown = all.where(_matches).toList();
    final inUse = all.where((i) => i.hostCount > 0 || i.chooserIds.isNotEmpty);
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l.identities,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.identitiesIntro,
                          style: TextStyle(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                key: const ValueKey('identities.new'),
                onPressed: () => showIdentityEditor(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.newIdentity),
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
                      hintText: l.filterIdentities,
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
                  l.identitiesCount(all.length, inUse.length),
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _table(context, shown),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textSubtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.identitiesNoSecrets,
                  style: TextStyle(fontSize: 12, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ],
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
          Icon(Icons.badge_outlined, size: 36, color: c.textSubtle),
          const SizedBox(height: 12),
          Text(
            l.noIdentities,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              l.noIdentitiesBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  static const _widths = [1.25, 0.6, 2.1, 0.9, 1.35, 0.75];

  Widget _cells(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        Expanded(
          flex: (_widths[i] * 100).round(),
          child: Padding(
            padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : 12),
            child: cells[i],
          ),
        ),
    ],
  );

  Widget _table(BuildContext context, List<IdentityView> rows) {
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
                l.user,
                l.keys,
                l.agentShort,
                l.usedBy,
                '',
              ])
                Text(h.toUpperCase(), style: head),
            ]),
          ),
          for (final i in rows) _row(context, i),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IdentityView i) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final missing = missingKeys(i);
    final mono = monoStyle(context, color: c.text);
    return FocusOutline(
      radius: 0,
      child: InkWell(
        key: ValueKey('identity.${i.spec.label}'),
        onTap: () => showIdentityEditor(context, ref, id: i.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Column(
            children: [
              _cells([
                Text(
                  i.spec.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(i.spec.user ?? '—', style: mono),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i.keys.isEmpty)
                      Text(l.usualKeys, style: TextStyle(color: c.textMuted)),
                    for (final k in i.keys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  k.path,
                                  style: monoStyle(
                                    context,
                                    color: k.state == KeyStateKind.missing
                                        ? c.warn
                                        : c.text,
                                  ),
                                ),
                                if (k.certificate != null)
                                  Pill(
                                    k.certificate!.expired
                                        ? l.certificateExpired
                                        : l.certificate,
                                    tone: PillTone.neutral,
                                  ),
                              ],
                            ),
                            Text(
                              keyDetail(l, k),
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Text(agentText(l, i.spec)),
                Text(
                  usedByText(l, i),
                  style: TextStyle(
                    color: i.chooserIds.isEmpty ? c.textSubtle : c.text,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    key: ValueKey('identity.use.${i.spec.label}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      visualDensity: VisualDensity.standard,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: smallButtonText(context),
                      foregroundColor: c.accentText,
                    ),
                    onPressed: () => showUseIdentity(context, ref, i),
                    child: Text(l.useOn),
                  ),
                ),
              ]),
              for (final k in missing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
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
                            l.keyMissingWarning(k.path, i.hostCount),
                            style: TextStyle(fontSize: 12, color: c.warn),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              showIdentityEditor(context, ref, id: i.id),
                          child: Text(l.editEllipsis),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
