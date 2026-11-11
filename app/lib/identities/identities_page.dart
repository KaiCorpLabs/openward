// The «Identidades» page: every identity with its user, keys, agent and who
// uses it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/identities.dart';
import '../ui/page.dart';
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
    final all = ref.watch(identitiesProvider);
    final shown = all.where(_matches).toList();
    final inUse = all.where((i) => i.hostCount > 0 || i.chooserIds.isNotEmpty);
    return ColoredBox(
      color: c.surface,
      child: ListView(
        padding: pagePadding,
        children: [
          OwPageHeader(
            title: l.identities,
            intro: l.identitiesIntro,
            action: FilledButton.icon(
              key: const ValueKey('identities.new'),
              onPressed: () => showIdentityEditor(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l.newIdentity),
            ),
          ),
          const SizedBox(height: 16),
          if (all.isEmpty)
            OwEmptyState(
              icon: Icons.badge_outlined,
              title: l.noIdentities,
              body: l.noIdentitiesBody,
            )
          else ...[
            OwFilterField(
              controller: _filter,
              hint: l.filterIdentities,
              onChanged: (_) => setState(() {}),
              count: l.identitiesCount(all.length, inUse.length),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              OwEmptyState.noMatch(
                filter: _filter.text.trim(),
                onClear: () => setState(_filter.clear),
              )
            else
              OwDataTable(
                widths: _widths,
                headings: [l.name, l.user, l.keys, l.agentShort, l.usedBy, ''],
                hideBelow: const [null, null, 520, 620, 720, null],
                rows: [for (final i in shown) _row(context, i)],
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: c.textSubtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.identitiesNoSecrets,
                  style: TextStyle(fontSize: OwText.small, color: c.textSubtle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _widths = [1.25, 0.6, 2.1, 0.9, 1.35, 0.75];

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
          padding: const EdgeInsets.symmetric(
            horizontal: OwSpace.s8,
            vertical: OwSpace.s6,
          ),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          // The cells, and under them the keys that are missing.
          child: Column(
            children: [
              OwDataTable.cells(_widths, [
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
                        padding: const EdgeInsets.symmetric(
                          vertical: OwSpace.hair,
                        ),
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
                                if (k.certificate case final cert?)
                                  certificatePill(
                                    l,
                                    expired: cert.expired,
                                    untilMs: cert.validBeforeMs,
                                    plain: l.certificate,
                                    tone: PillTone.neutral,
                                  ),
                              ],
                            ),
                            Text(
                              keyDetail(l, k),
                              style: TextStyle(
                                fontSize: OwText.small,
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
                    style: compactButtonStyle(
                      context,
                      foreground: c.accentText,
                    ),
                    onPressed: () => showUseIdentity(context, ref, i),
                    child: Text(l.useOn),
                  ),
                ),
              ]),
              for (final k in missing)
                Padding(
                  padding: const EdgeInsets.only(top: OwSpace.s4),
                  child: Callout(
                    tone: Tone.warn,
                    padding: const EdgeInsets.fromLTRB(
                      OwSpace.s6,
                      OwSpace.s3,
                      OwSpace.s3,
                      OwSpace.s3,
                    ),
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
                            style: TextStyle(
                              fontSize: OwText.small,
                              color: c.warn,
                            ),
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
