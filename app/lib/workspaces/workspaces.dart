// Workspaces: the open tabs and their panes, saved by name in the vault to
// open again. What each pane connects to is kept, never what it showed.

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/address.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart' show ProtocolKind;
import '../src/rust/api/workspaces.dart';
import '../tabs/tabs.dart';
import '../terminal/controller.dart';

/// Every workspace, by name.
class WorkspacesNotifier extends Notifier<List<WorkspaceView>> {
  @override
  List<WorkspaceView> build() => ref.read(openWardProvider).workspaces();

  void refresh() => state = ref.read(openWardProvider).workspaces();
}

final workspacesProvider =
    NotifierProvider<WorkspacesNotifier, List<WorkspaceView>>(
      WorkspacesNotifier.new,
    );

WorkspaceTarget _targetOf(ConnectionController c) {
  final t = c.target;
  // Telnet and serial ports go as they are written (`telnet://…`,
  // `serial://…`): the address says how to open them again.
  if (t != null && t.protocol != ProtocolKind.ssh) {
    return WorkspaceTarget(hostId: c.hostId, address: t.label);
  }
  return WorkspaceTarget(
    hostId: c.hostId,
    address: t?.address,
    user: t?.user,
    port: t?.port,
  );
}

/// The address a workspace keeps, as a target to open.
QuickTarget? _quick(WorkspaceTarget t) {
  final address = t.address;
  if (address == null) return null;
  if (address.contains('://')) return QuickTarget.parse(address);
  return QuickTarget(address: address, user: t.user, port: t.port);
}

void _preorder(PaneNode n, Pane active, List<WorkspacePane> out) {
  switch (n) {
    case PaneSplit(:final axis, :final first, :final second, :final ratio):
      out.add(
        WorkspacePane(
          split: WorkspaceSplit(vertical: axis == Axis.vertical, ratio: ratio),
          active: false,
        ),
      );
      _preorder(first, active, out);
      _preorder(second, active, out);
    case Pane(:final controller):
      out.add(
        WorkspacePane(
          target: controller == null ? null : _targetOf(controller),
          active: identical(n, active),
        ),
      );
  }
}

/// The open terminal and file tabs, laid out as they are; pages are left
/// out. Empty when there is nothing to keep.
List<WorkspaceTabSpec> captureTabs(TabsState state) {
  final out = <WorkspaceTabSpec>[];
  for (final tab in state.tabs) {
    switch (tab) {
      case SessionTab(:final panes):
        final list = <WorkspacePane>[];
        _preorder(panes.root, panes.active, list);
        out.add(
          WorkspaceTabSpec(
            title: panes.active.controller?.customTitle,
            panes: list,
          ),
        );
      case SftpTab(:final controller):
        out.add(WorkspaceTabSpec(panes: const [], sftp: _targetOf(controller)));
      case PageTab():
        break;
    }
  }
  return out;
}

/// The saved tab that was in front: the front tab, or the last one before
/// it that is kept.
int capturedActive(TabsState state) {
  var index = -1;
  for (final (i, tab) in state.tabs.indexed) {
    // Past the front tab: a page in front is not kept, and the one after
    // it is not the one that was in front.
    if (i > state.active) break;
    if (tab is PageTab) continue;
    index++;
  }
  return index < 0 ? 0 : index;
}

WorkspaceSpec captureWorkspace(TabsState state, String name) => WorkspaceSpec(
  name: name.trim(),
  tabs: captureTabs(state),
  active: capturedActive(state),
);

/// `2 pestañas · 3 sesiones`.
String workspaceSummary(AppLocalizations l, int tabs, int sessions) =>
    '${l.workspaceTabs(tabs)} · ${l.workspaceSessions(sessions)}';

/// What a target is called: the saved host's name, the address, or the
/// local shell.
String targetLabel(AppLocalizations l, WidgetRef ref, WorkspaceTarget? t) {
  if (t == null) return l.emptyPane;
  final hostId = t.hostId;
  if (hostId != null) {
    return ref.read(libraryProvider).host(hostId)?.label ?? l.deletedHost;
  }
  if (_quick(t) case final quick?) {
    return quick.isSerial ? quick.address : quick.label;
  }
  if (t.address case final address?) return address;
  return l.localShell;
}

/// The targets of a tab, left to right.
List<WorkspaceTarget?> tabTargets(WorkspaceTabSpec t) => t.sftp != null
    ? [t.sftp]
    : [
        for (final p in t.panes)
          if (p.split == null) p.target,
      ];

/// Opens the workspace's tabs after those open now: each pane connects
/// again. A saved host deleted since leaves a pane that asks what to open,
/// and its file tab is left out.
void openWorkspace(WidgetRef ref, WorkspaceView w) {
  final tabs = ref.read(tabsProvider.notifier);
  final library = ref.read(libraryProvider);
  final added = <OpenTab>[];
  OpenTab? front;

  QuickTarget? address(WorkspaceTarget t) => _quick(t);

  for (final (i, t) in w.spec.tabs.indexed) {
    final OpenTab? tab;
    final sftp = t.sftp;
    if (sftp != null) {
      final host = sftp.hostId == null ? null : library.host(sftp.hostId!);
      final target = address(sftp);
      tab = host == null && target == null
          ? null
          : SftpTab(
              tabs.startSftp(
                hostId: host?.id,
                target: target,
                label: host?.label ?? target!.label,
              ),
            );
    } else {
      Pane? active;
      final it = t.panes.iterator;
      PaneNode build() {
        if (!it.moveNext()) return Pane();
        final p = it.current;
        final split = p.split;
        if (split != null) {
          final first = build();
          final second = build();
          return PaneSplit(
            split.vertical ? Axis.vertical : Axis.horizontal,
            first,
            second,
            split.ratio,
          );
        }
        final target = p.target;
        TerminalController? c;
        if (target != null) {
          final hostId = target.hostId;
          if (hostId != null) {
            final host = library.host(hostId);
            if (host != null) c = tabs.startSession(host: host);
          } else {
            c = tabs.startSession(target: address(target));
          }
        }
        final pane = Pane(c);
        if (p.active) active = pane;
        return pane;
      }

      final root = build();
      final panes = Panes.of(root, active: active);
      final title = t.title;
      if (title != null) {
        (panes.active.controller ?? panes.controllers.firstOrNull)
                ?.customTitle =
            title;
      }
      tab = SessionTab.withPanes(panes);
    }
    if (tab == null) continue;
    added.add(tab);
    if (i == w.spec.active) front = tab;
  }
  tabs.addTabs(added, front: front);
}
