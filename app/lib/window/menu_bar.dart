import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../history/history.dart';
import '../hosts/editors.dart';
import '../l10n/l10n.dart';
import '../palette/command_palette.dart';
import '../security/state.dart';
import '../src/rust/api/security.dart';
import '../tabs/close_guard.dart' as guard;
import '../tabs/tabs.dart';
import '../terminal/keys.dart';
import '../welcome/whats_new.dart';
import 'shortcuts.dart';
import 'sidebar_state.dart';

/// Native desktop menu bar wrapping [child] on macOS. On mobile and
/// non-macOS targets it renders [child] directly without altering layout.
///
/// Edit shortcuts (`⌘C`, `⌘V`, `⌘X`, `⌘A`, `⌘Z`) are intentionally omitted
/// here so Cocoa responder and widget/terminal key handling keep ownership
/// inside `TextField` and `TerminalPane`.
class OwMenuBar extends ConsumerWidget {
  const OwMenuBar({
    super.key,
    required this.child,
    this.enabled = true,
    this.onCommandPalette,
    this.onNewHost,
    this.onCloseCurrent,
    this.onWhatsNew,
  });

  final Widget child;

  /// False while first-run onboarding is shown over the window.
  final bool enabled;
  final VoidCallback? onCommandPalette;
  final VoidCallback? onNewHost;
  final VoidCallback? onCloseCurrent;
  final VoidCallback? onWhatsNew;

  static PlatformProvidedMenuItem? _provided(
    PlatformProvidedMenuItemType type,
  ) => PlatformProvidedMenuItem.hasMenu(type)
      ? PlatformProvidedMenuItem(type: type)
      : null;

  static List<PlatformMenuItem> _group(List<PlatformMenuItem?> items) {
    final members = items.nonNulls.toList();
    return members.isEmpty
        ? const []
        : [PlatformMenuItemGroup(members: members)];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usePlatformMenu =
        !Device.mobile &&
        (Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS);
    if (!usePlatformMenu) return child;

    ref.watch(settingsProvider.select((s) => s.shortcutProfile));
    final phase = ref.watch(securityProvider.select((s) => s.phase));
    final tabsState = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final l = context.l10n;

    final visible =
        enabled && (phase == VaultPhase.legacy || phase == VaultPhase.unlocked);
    final canLock =
        enabled &&
        (phase == VaultPhase.unlocked || phase == VaultPhase.changing);
    final current = tabsState.current;
    final sessionTab = current is SessionTab ? current : null;
    final isSplit = sessionTab != null && sessionTab.panes.isSplit;
    final isMaximized =
        sessionTab != null && sessionTab.panes.maximized != null;
    final isBroadcast = sessionTab != null && sessionTab.panes.broadcast;

    void openSettings() => tabs.openPage(PageKind.settings);
    void lockVault() {
      ref.read(historyProvider.notifier).flush();
      unawaited(ref.read(openWardProvider).lockVault());
    }

    Future<void> newHost() async {
      if (await showHostEditor(context, ref)) {
        ref.read(libraryProvider.notifier).refresh();
      }
    }

    final commandPalette =
        onCommandPalette ?? () => showCommandPalette(context, ref);
    final createHost = onNewHost ?? newHost;
    final closeCurrent = onCloseCurrent ?? () => guard.closeCurrent(context);
    final whatsNew = onWhatsNew ?? () => showWhatsNew(context, ref);
    final toggleSidebar = ref.read(sidebarProvider.notifier).toggle;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'OpenWard',
          menus: [
            ..._group([_provided(PlatformProvidedMenuItemType.about)]),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l.menuPreferences,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.comma,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.comma,
                          control: true,
                        ),
                  onSelected: visible ? openSettings : null,
                ),
                if (canLock)
                  PlatformMenuItem(
                    label: l.menuLockVault,
                    shortcut: macShortcuts
                        ? const SingleActivator(
                            LogicalKeyboardKey.keyL,
                            meta: true,
                          )
                        : const SingleActivator(
                            LogicalKeyboardKey.keyL,
                            control: true,
                            alt: true,
                          ),
                    onSelected: lockVault,
                  ),
              ],
            ),
            ..._group([
              _provided(PlatformProvidedMenuItemType.servicesSubmenu),
            ]),
            ..._group([
              _provided(PlatformProvidedMenuItemType.hide),
              _provided(PlatformProvidedMenuItemType.hideOtherApplications),
              _provided(PlatformProvidedMenuItemType.showAllApplications),
            ]),
            ..._group([_provided(PlatformProvidedMenuItemType.quit)]),
          ],
        ),
        PlatformMenu(
          label: l.menuFile,
          menus: [
            PlatformMenuItemGroup(
              members: [
                if (Device.localTerminal)
                  PlatformMenuItem(
                    label: l.menuNewTab,
                    shortcut: macShortcuts
                        ? const SingleActivator(
                            LogicalKeyboardKey.keyT,
                            meta: true,
                          )
                        : const SingleActivator(
                            LogicalKeyboardKey.keyT,
                            control: true,
                            shift: true,
                          ),
                    onSelected: visible ? tabs.openLocal : null,
                  ),
                PlatformMenuItem(
                  label: l.saveNewHost,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyN,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyN,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible ? createHost : null,
                ),
                PlatformMenuItem(
                  label: l.reopenTab,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyT,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyT,
                          control: true,
                          shift: true,
                          alt: true,
                        ),
                  onSelected: visible && tabs.canReopen ? tabs.reopen : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l.splitRight,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyD,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyD,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible && sessionTab != null
                      ? () => tabs.split(Axis.horizontal)
                      : null,
                ),
                PlatformMenuItem(
                  label: l.splitDown,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyD,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyE,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible && sessionTab != null
                      ? () => tabs.split(Axis.vertical)
                      : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: isSplit ? l.closePane : l.closeTab,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyW,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyW,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible && current != null ? closeCurrent : null,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l.menuView,
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l.commandPalette,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyK,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyP,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible ? commandPalette : null,
                ),
                PlatformMenuItem(
                  label: l.toggleSidebar,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyB,
                          meta: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyL,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible ? toggleSidebar : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l.hosts,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyH,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyH,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible
                      ? () => tabs.openPage(PageKind.hosts)
                      : null,
                ),
                PlatformMenuItem(
                  label: l.logs,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyR,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyR,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible
                      ? () => tabs.openPage(PageKind.logs)
                      : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: isMaximized ? l.restorePanes : l.maximizePane,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.enter,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.enter,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible && isSplit ? tabs.toggleMaximize : null,
                ),
                PlatformMenuItem(
                  label: l.equalizePanes,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.equal,
                          meta: true,
                          alt: true,
                        )
                      : null,
                  onSelected: visible && isSplit ? tabs.equalize : null,
                ),
                PlatformMenuItem(
                  label: isBroadcast ? l.broadcastOff : l.broadcastOn,
                  shortcut: macShortcuts
                      ? const SingleActivator(
                          LogicalKeyboardKey.keyB,
                          meta: true,
                          shift: true,
                        )
                      : const SingleActivator(
                          LogicalKeyboardKey.keyB,
                          control: true,
                          shift: true,
                        ),
                  onSelected: visible && isSplit ? tabs.toggleBroadcast : null,
                ),
              ],
            ),
            ..._group([
              _provided(PlatformProvidedMenuItemType.toggleFullScreen),
            ]),
          ],
        ),
        PlatformMenu(
          label: l.menuWindow,
          menus: [
            ..._group([
              _provided(PlatformProvidedMenuItemType.minimizeWindow),
              _provided(PlatformProvidedMenuItemType.zoomWindow),
            ]),
            ..._group([
              _provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
            ]),
          ],
        ),
        PlatformMenu(
          label: l.menuHelp,
          menus: [
            PlatformMenuItem(
              label: l.shortcutsTitle,
              shortcut: macShortcuts
                  ? const SingleActivator(LogicalKeyboardKey.slash, meta: true)
                  : const SingleActivator(
                      LogicalKeyboardKey.slash,
                      control: true,
                      shift: true,
                    ),
              onSelected: visible ? () => showShortcuts(context) : null,
            ),
            PlatformMenuItem(
              label: l.whatsNew,
              onSelected: visible ? whatsNew : null,
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
