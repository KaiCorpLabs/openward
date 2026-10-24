import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/identities.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'identities.dart';

/// Picks the groups and hosts that use `identity`, saying what changes
/// for each host before anything is saved.
Future<void> showUseIdentity(
  BuildContext context,
  WidgetRef ref,
  IdentityView identity,
) => showDialog<void>(
  context: context,
  builder: (_) => _UseIdentity(identity: identity),
);

class _UseIdentity extends ConsumerStatefulWidget {
  const _UseIdentity({required this.identity});

  final IdentityView identity;

  @override
  ConsumerState<_UseIdentity> createState() => _UseIdentityState();
}

class _UseIdentityState extends ConsumerState<_UseIdentity> {
  late final Set<String> _choosers = {...widget.identity.chooserIds};
  final _filter = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<IdentityUseRow> _rows() => ref
      .read(openWardProvider)
      .identityUse(identityId: widget.identity.id, choosers: [..._choosers]);

  bool _matches(IdentityUseRow r) {
    final f = _filter.text.trim().toLowerCase();
    return f.isEmpty ||
        r.label.toLowerCase().contains(f) ||
        (r.groupLabel ?? '').toLowerCase().contains(f);
  }

  Future<void> _apply() async {
    try {
      await ref
          .read(openWardProvider)
          .useIdentity(
            identityId: widget.identity.id,
            choosers: [..._choosers],
          );
      identitiesChanged(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = saveErrorText(context.l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final rows = _rows();
    final hosts = rows.where((r) => !r.isGroup).toList();
    final changed = hosts.where((r) => r.after != r.nowIsThis).length;
    final using = hosts.where((r) => r.after).length;
    final groups = rows.where((r) => r.isGroup && _matches(r)).toList();
    final shownHosts = hosts.where(_matches).toList();
    return Dialog(
      backgroundColor: c.raised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.control),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge + 4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l.useIdentityOn(widget.identity.spec.label),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontSize: 17),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.useIdentityHint,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _filter,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l.filterHostsAndGroups,
                        prefixIcon: Icon(
                          Icons.search,
                          size: 16,
                          color: c.textSubtle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 22),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (groups.isNotEmpty) ...[
                      _head(context, l.groups),
                      for (final g in groups) _group(context, g),
                    ],
                    if (shownHosts.isNotEmpty) ...[
                      _head(context, l.hostsSection),
                      for (final h in shownHosts) _host(context, h),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Text(_error!, style: TextStyle(color: c.danger)),
              ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.useIdentitySummary(changed, using),
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('identity.use.apply'),
                    onPressed: _apply,
                    child: Text(l.apply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(BuildContext context, String text) {
    final c = context.ow.colors;
    return Container(
      color: c.sunken,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: c.textSubtle,
        ),
      ),
    );
  }

  void _toggle(String id, bool on) =>
      setState(() => on ? _choosers.add(id) : _choosers.remove(id));

  Widget _group(BuildContext context, IdentityUseRow g) {
    final l = context.l10n;
    final now = g.nowIsThis
        ? l.alreadyUses
        : g.now != null
        ? l.nowIdentity(g.now!)
        : g.nowNone
        ? l.nowNoIdentity
        : null;
    return _Pick(
      key: ValueKey('use.${g.label}'),
      icon: Icons.folder_outlined,
      label: g.label,
      detail: [l.hostCountText(g.hostCount), ?now].join(' · '),
      checked: g.chooses,
      onChanged: (v) => _toggle(g.id, v),
    );
  }

  Widget _host(BuildContext context, IdentityUseRow h) {
    final l = context.l10n;
    final c = context.ow.colors;
    // It gets it from a ticked group: nothing to tick.
    final inherits = !h.chooses && h.after && h.afterFromGroup != null;
    final now = inherits
        ? l.inheritsFrom(h.afterFromGroup!)
        : h.nowIsThis
        ? l.alreadyUses
        : h.now == null
        ? l.noIdentityNow
        : h.nowFromGroup != null
        ? l.nowIdentityFromGroup(h.now!, h.nowFromGroup!)
        : l.nowIdentity(h.now!);
    final badge = h.after && !h.nowIsThis
        ? (h.now == null ? l.badgeNew : l.badgeChanges)
        : !h.after && h.nowIsThis
        ? l.badgeLeaves
        : null;
    return _Pick(
      key: ValueKey('use.${h.label}'),
      label: h.label,
      detail: [
        if (h.groupLabel != null && !inherits) l.inGroup(h.groupLabel!),
        now,
      ].join(' · '),
      checked: h.chooses || inherits,
      onChanged: inherits ? null : (v) => _toggle(h.id, v),
      badge: badge,
      warning: h.after && h.ownUser != null ? l.ownUserWins(h.ownUser!) : null,
      warnColor: c.warn,
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    super.key,
    required this.label,
    required this.detail,
    required this.checked,
    required this.onChanged,
    this.icon,
    this.badge,
    this.warning,
    this.warnColor,
  });

  final String label;
  final String detail;
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? badge;
  final String? warning;
  final Color? warnColor;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!checked) : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: checked,
                onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
              ),
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: Icon(icon, size: 15, color: c.textMuted),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: enabled ? c.text : c.textMuted,
                        ),
                      ),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 12, color: c.textSubtle),
                      ),
                      if (warning != null)
                        Text(
                          warning!,
                          style: TextStyle(fontSize: 12, color: warnColor),
                        ),
                    ],
                  ),
                ),
              ),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 8),
                  child: Pill(badge!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
