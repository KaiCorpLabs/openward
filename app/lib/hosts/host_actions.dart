// What can be done to a saved host or group wherever they are listed (the
// sidebar, the Hosts page): connect, browse its files, star it, find out
// its system, edit or delete it, and the menu that offers all of that.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../import/import_dialog.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import '../tabs/tabs.dart';
import '../ui/environment.dart';
import 'editors.dart';

/// `user@address`, and the port when it is not 22.
String hostAddress(HostView h) =>
    '${h.user.isEmpty ? '' : '${h.user}@'}${h.address}'
    '${h.port == 22 ? '' : ':${h.port}'}';

/// The actions, for the widget at `context`.
class HostActions {
  HostActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  void refresh() => ref.read(libraryProvider.notifier).refresh();

  void connect(HostView h) => ref.read(tabsProvider.notifier).openHost(h);

  void sftp(HostView h) =>
      ref.read(tabsProvider.notifier).openSftp(hostId: h.id, label: h.label);

  /// Stars it, or takes the star away; says so if that fails.
  Future<void> toggleFavorite(HostView h) async {
    await runAction(
      context,
      () => ref
          .read(openWardProvider)
          .setFavorite(id: h.id, favorite: h.favorite == null),
    );
    refresh();
  }

  Future<void> editHost({String? id, String? groupId}) async {
    if (await showHostEditor(context, ref, id: id, groupId: groupId)) {
      refresh();
    }
  }

  Future<void> editGroup({String? id, String? parentId}) async {
    if (await showGroupEditor(context, ref, id: id, parentId: parentId)) {
      refresh();
    }
  }

  Future<void> import() async {
    await showImport(context, ref);
    refresh();
  }

  /// Asks first; a host others jump through stays.
  Future<void> delete(String id, String name, {required bool group}) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group ? l.deleteGroupTitle(name) : l.deleteHostTitle(name)),
        content: Text(group ? l.deleteGroupBody : l.deleteHostBody),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(openWardProvider).delete(id: id);
    } catch (e) {
      if (!context.mounted) return;
      showErrorNotice(
        ScaffoldMessenger.of(context),
        isVaultError(e, VaultErrorKind.inUse)
            ? l.hostInUse(name)
            : l.deleteFailed(errorReason(l, e)),
        e,
      );
    }
    refresh();
  }

  /// From now on, reads the host's `/etc/os-release` after connecting, and
  /// now if it is connected; says what came of it.
  Future<void> findOutSystem(HostView h) async {
    final l = context.l10n;
    final app = ref.read(openWardProvider);
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      if (await app.readOsRelease(id: h.id)) {
        final s = app.host(id: h.id).system;
        text = systemKnown(s?.code)
            ? l.systemTold(
                h.label,
                s!.name.isEmpty ? systemName(l, s.code) : s.name,
              )
            : l.systemStillUnknown(h.label);
      } else {
        text = l.systemOnNextConnection(h.label);
      }
    } catch (e) {
      refresh();
      return showErrorNotice(messenger, saveErrorText(l, e), e);
    }
    refresh();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// A menu at `at`, in global coordinates; runs what is picked.
  Future<void> menu(Offset at, List<PopupMenuEntry<VoidCallback>> items) async {
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    action?.call();
  }

  PopupMenuItem<VoidCallback> item(String text, VoidCallback action) =>
      PopupMenuItem(value: action, height: 36, child: Text(text));

  /// A host's menu: connect, its files, the star, finding out its system
  /// while it is not known, edit and delete.
  List<PopupMenuEntry<VoidCallback>> hostMenu(HostView h) {
    final l = context.l10n;
    return [
      item(l.connect, () => connect(h)),
      item(l.openSftp, () => sftp(h)),
      item(
        h.favorite == null ? l.addFavorite : l.removeFavorite,
        () => toggleFavorite(h),
      ),
      if (!systemKnown(h.system?.code))
        item(l.findOutSystem, () => findOutSystem(h)),
      item(l.editEllipsis, () => editHost(id: h.id)),
      item(l.delete, () => delete(h.id, h.label, group: false)),
    ];
  }

  /// A group's menu: a host or a group in it, edit and delete.
  List<PopupMenuEntry<VoidCallback>> groupMenu(GroupView g) {
    final l = context.l10n;
    return [
      item(l.newHostHere, () => editHost(groupId: g.id)),
      item(l.newSubgroup, () => editGroup(parentId: g.id)),
      item(l.editGroup, () => editGroup(id: g.id)),
      item(l.deleteGroup, () => delete(g.id, g.name, group: true)),
    ];
  }
}
